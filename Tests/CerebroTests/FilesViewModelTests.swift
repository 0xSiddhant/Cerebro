import Foundation
import Testing
@testable import Cerebro

/// A fresh folder to browse, removed at the end of the test.
private struct FilesFixture {
    let base: URL
    let url: URL

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("files-ui-\(UUID().uuidString)")
        url = base.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func root(_ kind: FileRoot.Kind = .dataContainer) -> FileRoot {
        FileRoot(kind: kind, url: url)
    }

    @discardableResult
    func file(_ path: String, _ text: String = "x") throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}

@MainActor
private func loaded(_ fixture: FilesFixture, root: FileRoot? = nil) async -> FolderViewModel {
    let viewModel = FolderViewModel(root: root ?? fixture.root(), folder: fixture.url, bodyLimit: 1_000)
    await viewModel.load()
    return viewModel
}

@MainActor
private func names(_ viewModel: FolderViewModel) -> [String] {
    viewModel.items.map(\.lastPathComponent)
}

@Test @MainActor func aFolderListsFoldersFirstAndSortsAndSearches() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("small.txt", "1")
    try fixture.file("large.json", String(repeating: "1", count: 2_000))
    try fixture.file("Logs/today.log")
    try fixture.file("Logs/archive/old.log")
    let viewModel = await loaded(fixture)

    #expect(names(viewModel) == ["Logs", "large.json", "small.txt"])
    #expect(viewModel.isFolderWritable)
    #expect(viewModel.title == "Data Container")

    viewModel.sortOrder = .size
    await viewModel.pendingRefresh?.value
    #expect(names(viewModel) == ["Logs", "large.json", "small.txt"])

    viewModel.searchText = "SMALL"
    await viewModel.pendingRefresh?.value
    #expect(names(viewModel) == ["small.txt"])

    viewModel.searchText = "log"
    await viewModel.pendingRefresh?.value
    #expect(names(viewModel) == ["Logs"])

    // A row that stays gets redrawn, because a subfolder result also says where it is.
    viewModel.searchScope = .subfolders
    await viewModel.pendingRefresh?.value
    #expect(Set(names(viewModel)) == ["Logs", "today.log", "old.log"])
    #expect(viewModel.changedItems.map(\.lastPathComponent) == ["Logs"])
    let deep = try #require(viewModel.items.first { $0.lastPathComponent == "old.log" })
    #expect(viewModel.row(for: deep)?.detail.hasPrefix("Logs/archive · ") == true)

    viewModel.searchText = "nothing-matches"
    await viewModel.pendingRefresh?.value
    #expect(viewModel.items.isEmpty)
    #expect(viewModel.notice == "No matches here or in subfolders.")
}

@Test @MainActor func rowsShowSizeDateAndAFolderSizeOnceMeasured() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("data", String(repeating: "x", count: 2_048))
    try fixture.file("Caches/a", "12")
    try fixture.file("Caches/b", "34")
    let viewModel = await loaded(fixture)
    let caches = fixture.url.appendingPathComponent("Caches")
    let folderID = try #require(viewModel.items.first { $0.lastPathComponent == "Caches" })
    let file = try #require(viewModel.items.first { $0.lastPathComponent == "data" })
    let measured = AsyncStream.makeStream(of: [URL].self)
    viewModel.onSizesChange = { measured.continuation.yield($0) }

    #expect(viewModel.row(for: file)?.detail.hasPrefix("2 KB · ") == true)
    #expect(viewModel.row(for: file)?.symbol == "doc")
    #expect(viewModel.row(for: folderID)?.detail.hasPrefix("…") == true)
    #expect(viewModel.row(for: folderID)?.isFolder == true)

    viewModel.measureIfNeeded(folderID)
    var updates = measured.stream.makeAsyncIterator()
    #expect(await updates.next()?.first?.lastPathComponent == caches.lastPathComponent)
    #expect(viewModel.row(for: folderID)?.detail.hasPrefix("2 items, 4 bytes") == true)
}

@Test @MainActor func anEmptyOrMissingFolderSaysSo() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    let empty = await loaded(fixture)
    let missing = FolderViewModel(
        root: fixture.root(), folder: fixture.url.appendingPathComponent("gone"), bodyLimit: 1)
    await missing.load()

    #expect(empty.notice == "This folder is empty.")
    #expect(missing.items.isEmpty)
    #expect(missing.notice != nil)
}

@Test @MainActor func eachKindOfItemOffersOnlyTheActionsThatApply() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("file.txt")
    let locked = try fixture.file("locked.txt")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: locked.path)
    try fixture.file("Folder/inside")
    let outside = try FilesFixture()
    defer { outside.remove() }
    try FileManager.default.createSymbolicLink(
        at: fixture.url.appendingPathComponent("escape"), withDestinationURL: outside.url)
    let viewModel = await loaded(fixture)
    let bundle = await loaded(fixture, root: fixture.root(.appBundle))
    func actions(_ name: String, in viewModel: FolderViewModel) throws -> [FileAction] {
        let id = try #require(viewModel.items.first { $0.lastPathComponent == name })
        return viewModel.actions(for: try #require(viewModel.entry(for: id)))
    }
    let preview: [FileAction] = [.quickLook, .openAsText, .info, .copyPath, .share]

    #expect(try actions("file.txt", in: viewModel) == FileAction.allCases.filter { $0 != .deleteContents })
    #expect(
        try actions("Folder", in: viewModel) == FileAction.allCases.filter { $0 != .quickLook && $0 != .openAsText })
    #expect(try actions("locked.txt", in: viewModel) == preview)
    #expect(try actions("file.txt", in: bundle) == preview)
    #expect(try actions("Folder", in: bundle) == [.info, .copyPath, .share])
    #expect(try actions("escape", in: viewModel).contains(.share) == false)
    #expect(!bundle.isFolderWritable)
}

@Test @MainActor func eachTypeOpensInItsViewer() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    let base = fixture.url
    func viewer(_ name: String) -> FileOpening {
        FolderViewModel.viewer(for: base.appendingPathComponent(name))
    }

    #expect(viewer("photo.png") == .quickLook(base.appendingPathComponent("photo.png")))
    #expect(viewer("doc.pdf") == .quickLook(base.appendingPathComponent("doc.pdf")))
    #expect(viewer("clip.mp4") == .quickLook(base.appendingPathComponent("clip.mp4")))
    #expect(viewer("notes.txt") == .quickLook(base.appendingPathComponent("notes.txt")))
    #expect(viewer("prefs.plist") == .bodyViewer(base.appendingPathComponent("prefs.plist")))
    #expect(viewer("data.json") == .bodyViewer(base.appendingPathComponent("data.json")))
    #expect(viewer("store.sqlite") == .bodyViewer(base.appendingPathComponent("store.sqlite")))
    #expect(viewer("no-extension") == .bodyViewer(base.appendingPathComponent("no-extension")))

    let target = try fixture.file("Inside/target.json")
    try FileManager.default.createSymbolicLink(
        at: base.appendingPathComponent("folder-link"), withDestinationURL: target.deletingLastPathComponent())
    try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("file-link"), withDestinationURL: target)
    try FileManager.default.createSymbolicLink(
        at: base.appendingPathComponent("outside-link"), withDestinationURL: fixture.base)
    let viewModel = await loaded(fixture)
    func opening(_ name: String) throws -> FileOpening {
        let id = try #require(viewModel.items.first { $0.lastPathComponent == name })
        return viewModel.opening(for: try #require(viewModel.entry(for: id)))
    }

    guard case .folder = try opening("Inside"), case .folder = try opening("folder-link"),
        case .bodyViewer = try opening("file-link"), case .refused = try opening("outside-link")
    else {
        Issue.record("A folder, a link to a folder, a link to a file or a link outside opened wrongly")
        return
    }
}

@Test @MainActor func aSelectionOffersWhatEveryItemAllows() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("one.txt")
    try fixture.file("two.txt")
    let locked = try fixture.file("locked.txt")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: locked.path)
    let viewModel = await loaded(fixture)
    let ids = Dictionary(uniqueKeysWithValues: viewModel.items.map { ($0.lastPathComponent, $0) })
    let pair = [ids["one.txt"], ids["two.txt"]].compactMap { $0 }
    let withLocked = pair + [ids["locked.txt"]].compactMap { $0 }

    #expect(viewModel.selectionActions(for: pair) == [.share, .copyTo, .moveTo, .delete])
    #expect(viewModel.selectionActions(for: withLocked) == [.share])
    #expect(viewModel.selectionActions(for: []).isEmpty)

    try await viewModel.perform { try $0.delete(pair) }

    #expect(names(viewModel) == ["locked.txt"])
}

@Test @MainActor func aDeleteSaysHowManyItemsItsFoldersHold() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("a.txt")
    try fixture.file("Caches/one")
    try fixture.file("Caches/two")
    let viewModel = await loaded(fixture)
    let entries = viewModel.items.compactMap(viewModel.entry(for:))
    let caches = try #require(entries.first { $0.name == "Caches" })
    let file = try #require(entries.first { $0.name == "a.txt" })

    #expect(await viewModel.deleteQuestion(for: [file]) == "This deletes “a.txt”. It can't be undone.")
    #expect(
        await viewModel.deleteQuestion(for: [caches])
            == "This deletes “Caches” and the 2 items in it. It can't be undone.")
    #expect(
        await viewModel.deleteQuestion(for: [caches, file])
            == "This deletes 2 items and the 2 items inside the folder. It can't be undone.")
    #expect(
        await viewModel.deleteQuestion(for: [caches], contentsOnly: true)
            == "This deletes the 2 items in “Caches” and keeps the folder. It can't be undone.")
}

@Test func theFilesTabSitsBeforeSystemInfoOnlyWhenItsOn() {
    #expect(
        DashboardTab.visible(hasProtoMappings: false, isFileBrowserEnabled: true)
            == [.http, .sockets, .files, .systemInfo])
    #expect(
        DashboardTab.visible(hasProtoMappings: true, isFileBrowserEnabled: true)
            == [.http, .sockets, .protoConfig, .files, .systemInfo])
    #expect(
        DashboardTab.visible(hasProtoMappings: true, isFileBrowserEnabled: false)
            == [.http, .sockets, .protoConfig, .systemInfo])
}

@Test @MainActor func theInfoPageListsWhatTheDiskSays() throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    let root = fixture.root()
    let entry = FileEntry(
        url: fixture.url.appendingPathComponent("Library/data.json"), kind: .file, size: 2_048, isWritable: true)
    let details = FileDetails(
        permissions: 0o644, protection: URLFileProtection.complete.rawValue, isExcludedFromBackup: true)
    let rows = FileInfoViewModel.rows(for: entry, in: root, details: details, contents: nil)
    let values = Dictionary(rows.map { ($0.title, $0.value) }) { first, _ in first }

    #expect(values["Name"] == "data.json")
    #expect(values["Location"] == "Data Container")
    #expect(values["Path in Location"] == "Library/data.json")
    #expect(values["Size"] == "2 KB (2,048 bytes)")
    #expect(values["Permissions"] == "rw-r--r-- (644)")
    #expect(values["Data Protection"] == "Complete")
    #expect(values["Backed Up"] == "No, excluded")
    #expect(values["Writable"] == "Yes")
    #expect(FileInfoViewModel.protectionText(nil) == "Not set")
}

@Test @MainActor func aFileInTheBodyViewerSaysItWasCutOffAndWarnsAsAFile() {
    let cut = CapturedBody(content: .truncated(Data("abc".utf8)), byteCount: 4_096)
    let file = BodyViewerViewModel(title: "log", body: cut, source: .file)
    let captured = BodyViewerViewModel(title: "Response", body: cut)

    #expect(file.notice == "Truncated: the first 3 bytes of 4 KB")
    #expect(file.copyMessage.contains("This file was cut off"))
    #expect(file.shareWarning == .files)
    #expect(captured.notice == nil)
    #expect(captured.shareWarning == .capturedData)
}

@Test func aSharedFolderIsZippedAndAFileIsSharedAsItIs() throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    let file = try fixture.file("note.txt")
    try fixture.file("Folder/inside.txt")
    let entries = [
        FileEntry(url: file, kind: .file),
        FileEntry(url: fixture.url.appendingPathComponent("Folder"), kind: .folder),
    ]

    let prepared = try FileSharePreparation.prepare(entries, root: fixture.root())
    defer { prepared.temporaryFolder.map { try? FileManager.default.removeItem(at: $0) } }

    #expect(prepared.files.first == file)
    #expect(prepared.files.last?.lastPathComponent == "Folder.zip")
    #expect(prepared.files.last.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(prepared.temporaryFolder != nil)
    #expect(throws: FileOperationError.outsideRoot) {
        try FileSharePreparation.prepare([FileEntry(url: fixture.base, kind: .folder)], root: fixture.root())
    }
}

@Test @MainActor func aSharedFileKeepsItsNameWithTheExtensionOfWhatsShared() {
    let json = CapturedBody(content: .complete(Data("{\"a\":1}".utf8)), byteCount: 7)
    let text = CapturedBody(content: .complete(Data("hello".utf8)), byteCount: 5)

    #expect(
        BodyViewerViewModel(title: "profile.json", body: json, source: .file).fileName(for: .pretty) == "profile.json")
    #expect(
        BodyViewerViewModel(title: "My Settings.plist", body: json, source: .file).fileName(for: .pretty)
            == "My Settings.json")
    #expect(BodyViewerViewModel(title: "notes.txt", body: text, source: .file).fileName(for: .raw) == "notes.txt")
    #expect(
        BodyViewerViewModel(title: "session-token", body: text, source: .file).fileName(for: .raw)
            == "session-token.txt")
    #expect(BodyViewerViewModel(title: "Response Body", body: json).fileName(for: .pretty) == "response-body.json")
}

@Test @MainActor func aFolderWithoutASizeIsRedrawnSoItGetsMeasured() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("Caches/a")
    try fixture.file("note.txt")
    let viewModel = await loaded(fixture)
    let caches = try #require(viewModel.items.first { $0.lastPathComponent == "Caches" })
    let measured = AsyncStream.makeStream(of: [URL].self)
    viewModel.onSizesChange = { measured.continuation.yield($0) }

    // Not measured yet, so a reload redraws it.
    await viewModel.load()
    #expect(viewModel.changedItems == [caches])

    viewModel.measureIfNeeded(caches)
    var updates = measured.stream.makeAsyncIterator()
    _ = await updates.next()

    // Measured, so an ordinary reload leaves it alone, and one that resets sizes redraws it again.
    await viewModel.load()
    #expect(viewModel.changedItems.isEmpty)
    await viewModel.load(resettingSizes: true)
    #expect(viewModel.changedItems == [caches])
    #expect(viewModel.row(for: caches)?.detail.hasPrefix("…") == true)
}

@Test @MainActor func aWatcherReloadDoesntSearchSubfoldersAgain() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    try fixture.file("Logs/today.log")
    let viewModel = await loaded(fixture)
    viewModel.searchScope = .subfolders
    viewModel.searchText = "log"
    await viewModel.pendingRefresh?.value
    try fixture.file("Logs/tomorrow.log")

    await viewModel.load(refreshingSearch: false)
    #expect(!names(viewModel).contains("tomorrow.log"))

    await viewModel.load()
    #expect(names(viewModel).contains("tomorrow.log"))
}

@Test @MainActor func aFolderThatsGoneTakesNoNewItems() async throws {
    let fixture = try FilesFixture()
    defer { fixture.remove() }
    let folder = fixture.url.appendingPathComponent("Doomed", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let viewModel = FolderViewModel(root: fixture.root(), folder: folder, bodyLimit: 1)
    await viewModel.load()
    #expect(viewModel.isFolderWritable)

    try FileManager.default.removeItem(at: folder)
    await viewModel.load()

    #expect(!viewModel.isFolderWritable)
    #expect(viewModel.notice != nil)
}
