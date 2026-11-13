import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Where the folder screen searches, in the order the scope bar shows them.
enum FileSearchScope: Int, CaseIterable {
    case thisFolder
    case subfolders

    var title: String {
        switch self {
        case .thisFolder: return "This Folder"
        case .subfolders: return "Subfolders"
        }
    }
}

/// Something the developer can do with an item.
enum FileAction: CaseIterable {
    case quickLook
    case openAsText
    case info
    case copyPath
    case share
    case rename
    case duplicate
    case copyTo
    case moveTo
    case deleteContents
    case delete

    var title: String {
        switch self {
        case .quickLook: return "Open in Quick Look"
        case .openAsText: return "Open as Text or Hex"
        case .info: return "Info"
        case .copyPath: return "Copy Path"
        case .share: return "Share"
        case .rename: return "Rename"
        case .duplicate: return "Duplicate"
        case .copyTo: return "Copy To…"
        case .moveTo: return "Move To…"
        case .deleteContents: return "Delete Contents"
        case .delete: return "Delete"
        }
    }

    /// An SF Symbol.
    var symbol: String {
        switch self {
        case .quickLook: return "eye"
        case .openAsText: return "doc.plaintext"
        case .info: return "info.circle"
        case .copyPath: return "doc.on.clipboard"
        case .share: return "square.and.arrow.up"
        case .rename: return "pencil"
        case .duplicate: return "plus.square.on.square"
        case .copyTo: return "doc.on.doc"
        case .moveTo: return "folder"
        case .deleteContents: return "xmark.bin"
        case .delete: return "trash"
        }
    }

    var isDestructive: Bool {
        self == .delete || self == .deleteContents
    }
}

/// What tapping an item opens.
enum FileOpening: Equatable {
    case folder(URL)
    case quickLook(URL)
    case bodyViewer(URL)

    /// It can't be opened, and this says why.
    case refused(String)
}

/// One line of a folder's list.
struct FileRow: Equatable {
    let name: String
    let symbol: String
    let detail: String
    let isFolder: Bool
}

/// What a folder screen shows: the folder's items, sorted and searched, with each folder's size worked out
/// once its row appears. Listing, sorting, searching and measuring all run off the main thread, and the
/// folder is watched while the screen is on, so changes show without a refresh.
@MainActor
final class FolderViewModel {
    let root: FileRoot
    let folder: URL
    let bodyLimit: Int

    /// The visible items, in order.
    private(set) var items: [URL] = []

    /// What the list's footer says, such as why a search stopped, or `nil` for nothing.
    private(set) var notice: String?

    /// Whether items can be added here, which decides New Folder and Import.
    private(set) var isFolderWritable = false

    /// Called after `items` or `notice` changes.
    var onChange: (() -> Void)?

    /// Called with the rows whose folder size just arrived.
    var onSizesChange: (([URL]) -> Void)?

    var sortOrder = FileSortOrder.name {
        didSet { refreshIfChanged(oldValue != sortOrder) }
    }

    var searchText = "" {
        didSet { refreshIfChanged(oldValue != searchText) }
    }

    var searchScope = FileSearchScope.thisFolder {
        didSet { refreshIfChanged(oldValue != searchScope) }
    }

    /// The work behind the current `items`, which tests wait for.
    private(set) var pendingRefresh: Task<Void, Never>?

    private var entries: [FileEntry] = []
    private var visible: [URL: FileEntry] = [:]
    private var sizes: [URL: FolderMeasurement] = [:]
    private var measurements: [URL: Task<Void, Never>] = [:]
    private var watching: Task<Void, Never>?
    private var generation = 0

    init(root: FileRoot, folder: URL, bodyLimit: Int) {
        self.root = root
        self.folder = folder
        self.bodyLimit = bodyLimit
    }

    deinit {
        pendingRefresh?.cancel()
        watching?.cancel()
        measurements.values.forEach { $0.cancel() }
    }

    var title: String {
        root.isRootFolder(folder) ? root.name : folder.lastPathComponent
    }

    var operations: FileOperations {
        FileOperations(root: root)
    }

    func entry(for id: URL) -> FileEntry? {
        visible[id]
    }

    // MARK: - Listing

    /// Reads the folder again. `resettingSizes` also measures its folders again when they next appear,
    /// which a reload for an added or removed entry doesn't need.
    func load(resettingSizes: Bool = false) async {
        let (root, folder) = (root, folder)
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                let entries = try FolderListing.entries(in: folder, root: root)
                let isWritable = !root.isReadOnly && (try? FileEntry.read(folder).isWritable) == true
                return (entries, isWritable)
            }
        }
        .value
        switch result {
        case .success(let (entries, isWritable)):
            self.entries = entries
            isFolderWritable = isWritable
            if resettingSizes {
                sizes = [:]
            }
            refresh()
            await pendingRefresh?.value
        case .failure(let error):
            entries = []
            show([], notice: error.localizedDescription)
        }
    }

    /// Reloads whenever the folder's entries change, until `stopWatching`.
    func startWatching() {
        guard watching == nil else { return }
        let changes = FolderWatcher.changes(in: folder)
        watching = Task { [weak self] in
            for await _ in changes {
                await self?.load()
            }
        }
    }

    /// Stops watching and measuring, for when the screen goes away.
    func stopWatching() {
        watching?.cancel()
        watching = nil
        measurements.values.forEach { $0.cancel() }
        measurements = [:]
    }

    private func refreshIfChanged(_ isChanged: Bool) {
        if isChanged {
            refresh()
        }
    }

    /// Sorts and searches off the main thread. A newer call replaces an older one, so each keystroke
    /// cancels the search before it.
    private func refresh() {
        pendingRefresh?.cancel()
        generation += 1
        let (generation, root, folder, entries) = (generation, root, folder, entries)
        let (order, query) = (sortOrder, searchText.trimmingCharacters(in: .whitespaces))
        let searchesSubfolders = searchScope == .subfolders && !query.isEmpty
        pendingRefresh = Task.detached(priority: .userInitiated) { [weak self] in
            let found: [FileEntry]
            var notice: String?
            if searchesSubfolders {
                guard let result = try? FileSearch.subfolders(of: folder, root: root, matching: query) else { return }
                found = result.entries
                notice = Self.notice(for: result.stop) ?? (found.isEmpty ? "No matches here or in subfolders." : nil)
            } else {
                found = entries.filter { FileSearch.matches($0.name, query: query) }
                if found.isEmpty {
                    notice = entries.isEmpty ? "This folder is empty." : "No matches in this folder."
                }
            }
            let sorted = order.sorted(found)
            guard !Task.isCancelled else { return }
            await self?.show(sorted, notice: notice, generation: generation)
        }
    }

    private func show(_ found: [FileEntry], notice: String?, generation: Int? = nil) {
        guard generation == nil || generation == self.generation else { return }
        items = found.map(\.url)
        visible = Dictionary(found.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        self.notice = notice
        onChange?()
    }

    private nonisolated static func notice(for stop: FileSearchResult.Stop?) -> String? {
        switch stop {
        case .resultLimit:
            return "Showing the first \(FileSearch.resultLimit.formatted()) matches. Search for more of the name."
        case .visitLimit:
            return "Stopped after looking through \(FileSearch.visitLimit.formatted()) items. Search a smaller folder."
        case nil:
            return nil
        }
    }

    // MARK: - Rows

    func row(for id: URL) -> FileRow? {
        guard let entry = visible[id] else { return nil }
        var detail: [String] = []
        // A result from a subfolder says where it is.
        let isFromSubfolders = searchScope == .subfolders && !searchText.isEmpty
        if isFromSubfolders, let parent = root.relativePath(of: entry.url.deletingLastPathComponent()) {
            detail.append(parent.isEmpty ? root.name : parent)
        }
        switch entry.kind {
        case .folder:
            detail.append(sizes[id].map(DisplayFormat.folderContents) ?? "…")
        case .file:
            detail.append(DisplayFormat.bytes(entry.size ?? 0))
        case .symbolicLink:
            detail.append("→ " + (entry.linkTarget ?? "?"))
        }
        if let modified = entry.modified {
            detail.append(DisplayFormat.fileDate(modified))
        }
        return FileRow(
            name: entry.name,
            symbol: FileSymbols.symbol(for: entry),
            detail: detail.joined(separator: " · "),
            isFolder: entry.kind == .folder
        )
    }

    /// Works out a folder's size once its row is on screen. Leaving the screen cancels it.
    func measureIfNeeded(_ id: URL) {
        guard visible[id]?.kind == .folder, sizes[id] == nil, measurements[id] == nil else { return }
        let root = root
        measurements[id] = Task.detached(priority: .utility) { [weak self] in
            let measurement = try? FolderMeasurement.measure(id, root: root)
            await self?.finishMeasuring(id, measurement)
        }
    }

    private func finishMeasuring(_ id: URL, _ measurement: FolderMeasurement?) {
        measurements[id] = nil
        guard let measurement else { return }
        sizes[id] = measurement
        onSizesChange?([id])
    }

    // MARK: - Actions

    /// What an item offers. The app bundle's items, and any the process can't write, only offer the
    /// ones that change nothing.
    func actions(for entry: FileEntry) -> [FileAction] {
        let canChange = !root.isReadOnly && entry.isWritable
        let canReachTarget = entry.kind != .symbolicLink || root.containsTarget(of: entry.url)
        return FileAction.allCases.filter { action in
            switch action {
            case .quickLook, .openAsText: return entry.kind == .file
            case .info, .copyPath: return true
            case .share: return canReachTarget
            case .rename, .duplicate, .copyTo, .moveTo, .delete: return canChange
            case .deleteContents: return canChange && entry.kind == .folder
            }
        }
    }

    /// What a selection offers: the actions every selected item allows, of those that work on several.
    func selectionActions(for ids: [URL]) -> [FileAction] {
        let selected = ids.compactMap { visible[$0] }
        guard !selected.isEmpty else { return [] }
        return [.share, .copyTo, .moveTo, .delete].filter { action in
            selected.allSatisfy { actions(for: $0).contains(action) }
        }
    }

    /// Where tapping an item leads. A link is followed only if it stays inside the root.
    func opening(for entry: FileEntry) -> FileOpening {
        switch entry.kind {
        case .folder:
            return .folder(entry.url)
        case .file:
            return Self.viewer(for: entry.url)
        case .symbolicLink:
            guard root.containsTarget(of: entry.url) else {
                return .refused("This link leads outside \(root.name), so Cerebro doesn't follow it.")
            }
            let target = entry.url.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
                return .refused("This link's target doesn't exist.")
            }
            return isDirectory.boolValue ? .folder(target) : Self.viewer(for: target)
        }
    }

    /// Quick Look renders documents and media well. Everything else opens in the Body Viewer.
    nonisolated static func viewer(for file: URL) -> FileOpening {
        FileFormat(name: file.lastPathComponent, header: Data()) == .document ? .quickLook(file) : .bodyViewer(file)
    }

    /// A file's contents for the Body Viewer, read off the main thread.
    func body(of file: URL, asRaw: Bool) async throws -> CapturedBody {
        let (root, limit) = (root, bodyLimit)
        return try await Task.detached(priority: .userInitiated) {
            try FileContents.body(of: file, root: root, limit: limit, asRaw: asRaw)
        }
        .value
    }

    /// Runs a file operation off the main thread, then lists the folder again, whether it worked or not.
    func perform(_ operation: @escaping @Sendable (FileOperations) throws -> Void) async throws {
        let operations = operations
        let result = await Task.detached(priority: .userInitiated) { Result { try operation(operations) } }.value
        await load(resettingSizes: true)
        try result.get()
    }

    /// What a delete asks before it runs, including how many items its folders hold.
    func deleteQuestion(for entries: [FileEntry], contentsOnly: Bool = false) async -> String {
        let root = root
        let folders = entries.filter { $0.kind == .folder }.map(\.url)
        let inside = await Task.detached(priority: .userInitiated) {
            folders.compactMap { try? FolderMeasurement.measure($0, root: root) }
        }
        .value
        let count = inside.reduce(0) { $0 + $1.itemCount }
        let held = DisplayFormat.itemCount(count, isPartial: inside.contains(where: \.isPartial))
        let what = entries.count == 1 ? "“\(entries[0].name)”" : DisplayFormat.itemCount(entries.count)
        if contentsOnly {
            return "This deletes the \(held) in \(what) and keeps the folder. It can't be undone."
        }
        if folders.isEmpty {
            return "This deletes \(what). It can't be undone."
        }
        let place = entries.count == 1 ? "in it" : folders.count == 1 ? "inside the folder" : "inside the folders"
        return "This deletes \(what) and the \(held) \(place). It can't be undone."
    }
}
