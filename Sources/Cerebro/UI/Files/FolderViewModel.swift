import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

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

    /// The items that were already listed and now read differently, such as a file that grew. The list
    /// has to redraw these itself, because their paths are the same.
    private(set) var changedItems: [URL] = []

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

    /// Whether the rows are subfolder results, which also say where each one is.
    private var showsParents = false
    private var sizes: [URL: FolderMeasurement] = [:]
    private var measurements: [URL: Task<Void, Never>] = [:]
    private var watching: Task<Void, Never>?
    private var generation = 0

    /// Counts loads, so one that finishes after a newer one doesn't replace it.
    private var loads = 0

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
        loads += 1
        let (load, root, folder) = (loads, root, folder)
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                let entries = try FolderListing.entries(in: folder, root: root)
                let isWritable = !root.isReadOnly && (try? FileEntry.read(folder).isWritable) == true
                return (entries, isWritable)
            }
        }
        .value
        guard load == loads else { return }
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
            generation += 1
            let failed = Listing(
                items: [], visible: [:], changed: [], showsParents: false, notice: error.localizedDescription)
            show(failed, generation: generation)
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
        let (generation, root, folder, entries, previous) = (generation, root, folder, entries, visible)
        let (order, query) = (sortOrder, searchText.trimmingCharacters(in: .whitespaces))
        let searchesSubfolders = searchScope == .subfolders && !query.isEmpty
        // A row reads differently once it says where it is, so every row is redrawn when that changes.
        let redrawsAll = searchesSubfolders != showsParents
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
            // Everything a large folder costs is worked out here, so the main thread only shows it.
            let sorted = order.sorted(found)
            let listing = Listing(
                items: sorted.map(\.url),
                visible: Dictionary(sorted.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first }),
                changed: sorted.filter { entry in
                    previous[entry.url].map { redrawsAll || $0 != entry } ?? false
                }
                .map(\.url),
                showsParents: searchesSubfolders,
                notice: notice
            )
            guard !Task.isCancelled else { return }
            await self?.show(listing, generation: generation)
        }
    }

    /// A folder's rows, ready to show.
    private struct Listing: Sendable {
        let items: [URL]
        let visible: [URL: FileEntry]
        let changed: [URL]
        let showsParents: Bool
        let notice: String?
    }

    private func show(_ listing: Listing, generation: Int) {
        guard generation == self.generation else { return }
        items = listing.items
        visible = listing.visible
        changedItems = listing.changed
        showsParents = listing.showsParents
        notice = listing.notice
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
        if showsParents, let parent = root.relativePath(of: entry.url.deletingLastPathComponent()) {
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

}

// MARK: - Actions

extension FolderViewModel {
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
            guard let resolved = try? FileEntry.read(target) else {
                return .refused("This link's target doesn't exist.")
            }
            return resolved.kind == .folder ? .folder(target) : Self.viewer(for: target)
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
