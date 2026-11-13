import Foundation

/// One item in a folder, as the Files tab lists it.
public struct FileEntry: Sendable, Hashable {
    /// What an item is.
    public enum Kind: Sendable, Hashable {
        /// A regular file, or anything that isn't a folder or a link.
        case file

        /// A folder.
        case folder

        /// A symbolic link, which is listed as itself and never followed out of its root.
        case symbolicLink
    }

    /// Where the item is.
    public let url: URL

    /// What it is.
    public let kind: Kind

    /// A file's size in bytes. `nil` for a folder or a link.
    public let size: Int64?

    /// When the item was created, if the file system says.
    public let created: Date?

    /// When the item's contents last changed, if the file system says.
    public let modified: Date?

    /// Where a link points, exactly as it's written in the link.
    public let linkTarget: String?

    /// Whether this process can write to the item.
    public let isWritable: Bool

    /// Creates an entry.
    public init(
        url: URL,
        kind: Kind,
        size: Int64? = nil,
        created: Date? = nil,
        modified: Date? = nil,
        linkTarget: String? = nil,
        isWritable: Bool = true
    ) {
        self.url = url
        self.kind = kind
        self.size = size
        self.created = created
        self.modified = modified
        self.linkTarget = linkTarget
        self.isWritable = isWritable
    }

    /// The item's name, with its extension.
    public var name: String {
        url.lastPathComponent
    }

    /// The attributes a listing reads for every item, in one batched call.
    static let listedKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
        .isWritableKey,
    ]

    /// Reads an entry from attributes a listing or a search already fetched.
    init(url: URL, values: URLResourceValues) {
        let kind: Kind =
            values.isSymbolicLink == true ? .symbolicLink : values.isDirectory == true ? .folder : .file
        self.init(
            url: url,
            kind: kind,
            size: kind == .file ? values.fileSize.map(Int64.init) : nil,
            created: values.creationDate,
            modified: values.contentModificationDate,
            linkTarget: kind == .symbolicLink
                ? try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil,
            isWritable: values.isWritable ?? false
        )
    }

    /// Reads one item's entry.
    public static func read(_ url: URL) throws -> Self {
        Self(url: url, values: try url.resourceValues(forKeys: Set(listedKeys)))
    }
}

/// The orders a folder can be listed in. Folders always come first.
public enum FileSortOrder: Sendable, CaseIterable {
    /// A to Z, comparing numbers by value, as the Files app does.
    case name

    /// The most recently modified first.
    case date

    /// The largest file first. Folders keep their name order, because their size isn't known yet.
    case size

    /// Sorts entries in this order, with folders first.
    public func sorted(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { first, second in
            let (firstIsFolder, secondIsFolder) = (first.kind == .folder, second.kind == .folder)
            guard firstIsFolder == secondIsFolder else { return firstIsFolder }
            switch self {
            // Missing values compare as their stand-ins in both places, so the order is always the same.
            case .date where (first.modified ?? .distantPast) != (second.modified ?? .distantPast):
                return (first.modified ?? .distantPast) > (second.modified ?? .distantPast)
            case .size where !firstIsFolder && (first.size ?? 0) != (second.size ?? 0):
                return (first.size ?? 0) > (second.size ?? 0)
            default:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }
}

/// Reads folders, one level at a time and never outside their root.
public enum FolderListing {
    /// Every item in a folder, hidden ones included, in one batched read. Call it off the main thread.
    public static func entries(in folder: URL, root: FileRoot) throws -> [FileEntry] {
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: FileEntry.listedKeys, options: [])
        let keys = Set(FileEntry.listedKeys)
        return urls.compactMap { url in
            // The values were fetched with the listing, so this reads them from memory.
            (try? url.resourceValues(forKeys: keys)).map { FileEntry(url: url, values: $0) }
        }
    }
}
