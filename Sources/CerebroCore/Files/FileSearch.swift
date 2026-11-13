import Foundation

/// What a search through subfolders found.
public struct FileSearchResult: Sendable, Equatable {
    /// Why a search stopped before it looked everywhere.
    public enum Stop: Sendable, Equatable {
        /// It visited as many items as it may.
        case visitLimit

        /// It found as many results as it may.
        case resultLimit
    }

    /// The items whose names match, in the order they were found.
    public let entries: [FileEntry]

    /// Why it stopped early, or `nil` if it looked everywhere.
    public let stop: Stop?

    /// Creates a result.
    public init(entries: [FileEntry], stop: Stop?) {
        self.entries = entries
        self.stop = stop
    }
}

/// Finds items by name.
public enum FileSearch {
    /// Items a search through subfolders visits before it stops.
    public static let visitLimit = 50_000

    /// Results a search through subfolders returns before it stops.
    public static let resultLimit = 500

    /// Whether a name holds the query, ignoring case and accents. An empty query matches everything.
    public static func matches(_ name: String, query: String) -> Bool {
        query.isEmpty || name.localizedStandardContains(query)
    }

    /// Searches a folder and every folder below it. Links are matched but never followed. It blocks,
    /// so call it from a task off the main thread, and cancelling that task stops it with
    /// `CancellationError`.
    public static func subfolders(
        of folder: URL,
        root: FileRoot,
        matching query: String,
        visitLimit: Int = Self.visitLimit,
        resultLimit: Int = Self.resultLimit
    ) throws -> FileSearchResult {
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        guard
            let items = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: FileEntry.listedKeys, options: [],
                errorHandler: { _, _ in true })
        else { return FileSearchResult(entries: [], stop: nil) }
        let keys = Set(FileEntry.listedKeys)
        var (entries, visited) = ([FileEntry](), 0)
        while let item = items.nextObject() as? URL {
            try Task.checkCancellation()
            guard visited < visitLimit else { return FileSearchResult(entries: entries, stop: .visitLimit) }
            visited += 1
            guard matches(item.lastPathComponent, query: query), let values = try? item.resourceValues(forKeys: keys)
            else { continue }
            entries.append(FileEntry(url: item, values: values))
            if entries.count == resultLimit {
                return FileSearchResult(entries: entries, stop: .resultLimit)
            }
        }
        return FileSearchResult(entries: entries, stop: nil)
    }
}
