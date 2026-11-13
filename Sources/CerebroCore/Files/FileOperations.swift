import Foundation

/// Why Cerebro refused a file operation. A failure the system reports is passed on as it is.
public enum FileOperationError: LocalizedError, Equatable {
    /// The path, with its symlinks followed, ends outside the root.
    case outsideRoot

    /// The root is the app bundle, which is never changed.
    case readOnly

    /// The root's own folder can't be renamed, moved or deleted.
    case rootFolder

    /// A name that's empty, `.` or `..`, or holds a `/`.
    case invalidName

    /// Another item already has the name.
    case nameTaken(String)

    /// A folder can't be copied or moved into itself.
    case intoItself

    /// Every free numbered name was tried.
    case noFreeName(String)

    /// What the alert says.
    public var errorDescription: String? {
        switch self {
        case .outsideRoot: return "This path leads outside its location, so Cerebro won't touch it."
        case .readOnly: return "The app bundle can't be changed."
        case .rootFolder: return "A location's own folder can't be changed."
        case .invalidName: return "A name can't be empty, \".\" or \"..\", or contain \"/\"."
        case .nameTaken(let name): return "An item named \"\(name)\" already exists here."
        case .intoItself: return "A folder can't be copied or moved into itself."
        case .noFreeName(let name): return "There's no free name left for \"\(name)\" here."
        }
    }
}

/// Changes files inside one root and nowhere else. Nothing overwrites: a copy, a move or an import
/// gets a numbered name, and a rename or a new folder with a taken name is refused. Each check runs
/// before anything changes, and every call blocks, so run them off the main thread.
public struct FileOperations: Sendable {
    /// Numbered names tried before giving up.
    private static let nameAttempts = 10_000

    /// The root every path must stay inside.
    public let root: FileRoot

    /// Creates the operations for one root.
    public init(root: FileRoot) {
        self.root = root
    }

    /// Renames an item in place and returns its new location.
    @discardableResult
    public func rename(_ item: URL, to name: String) throws -> URL {
        try checkChangeable(item)
        try Self.checkName(name)
        let destination = item.deletingLastPathComponent().appendingPathComponent(name)
        guard destination.lastPathComponent != item.lastPathComponent else { return item }
        // A rename that only changes case finds itself on a case-insensitive disk, such as a simulator's.
        if FileManager.default.fileExists(atPath: destination.path), !Self.isSameItem(item, destination) {
            throw FileOperationError.nameTaken(name)
        }
        try FileManager.default.moveItem(at: item, to: destination)
        return destination
    }

    /// Copies an item beside itself as `name 2.ext`, and returns the copy.
    @discardableResult
    public func duplicate(_ item: URL) throws -> URL {
        try checkChangeable(item)
        let copy = try freeLocation(for: item.lastPathComponent, in: item.deletingLastPathComponent())
        try FileManager.default.copyItem(at: item, to: copy)
        return copy
    }

    /// Copies items into a folder of the same root, numbering any name that's taken. A link is copied
    /// as a link.
    @discardableResult
    public func copy(_ items: [URL], into folder: URL) throws -> [URL] {
        try checkDestination(folder, for: items)
        return try items.map { item in
            let copy = try freeLocation(for: item.lastPathComponent, in: folder)
            try FileManager.default.copyItem(at: item, to: copy)
            return copy
        }
    }

    /// Moves items into a folder of the same root, numbering any name that's taken. An item already in
    /// that folder stays where it is.
    @discardableResult
    public func move(_ items: [URL], into folder: URL) throws -> [URL] {
        try checkDestination(folder, for: items)
        try items.forEach(checkChangeable)
        return try items.map { item in
            guard !Self.isSameItem(item.deletingLastPathComponent(), folder) else { return item }
            let destination = try freeLocation(for: item.lastPathComponent, in: folder)
            try FileManager.default.moveItem(at: item, to: destination)
            return destination
        }
    }

    /// Deletes items. A link is deleted, never its target. This can't be undone.
    public func delete(_ items: [URL]) throws {
        try items.forEach(checkChangeable)
        try items.forEach { try FileManager.default.removeItem(at: $0) }
    }

    /// Deletes everything in a folder and keeps the folder, for `Caches` and `tmp`. This can't be undone.
    public func deleteContents(of folder: URL) throws {
        try checkWritable()
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        guard !root.isRootFolder(folder) else { throw FileOperationError.rootFolder }
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [])
        try contents.forEach { try FileManager.default.removeItem(at: $0) }
    }

    /// Creates a folder, refusing a name that's taken, and returns it.
    @discardableResult
    public func createFolder(named name: String, in folder: URL) throws -> URL {
        try checkWritable()
        try Self.checkName(name)
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        let created = folder.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: created.path) else { throw FileOperationError.nameTaken(name) }
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: false)
        return created
    }

    /// Moves a file from outside the root, such as the copy a document picker made, into a folder,
    /// numbering its name if it's taken.
    @discardableResult
    public func importItem(at source: URL, into folder: URL) throws -> URL {
        try checkWritable()
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        let destination = try freeLocation(for: source.lastPathComponent, in: folder)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    // MARK: - Checks

    private func checkWritable() throws {
        guard !root.isReadOnly else { throw FileOperationError.readOnly }
    }

    /// The item itself must be inside the root and not be the root.
    private func checkChangeable(_ item: URL) throws {
        try checkWritable()
        guard root.containsItem(at: item) else { throw FileOperationError.outsideRoot }
        guard !root.isRootFolder(item) else { throw FileOperationError.rootFolder }
    }

    /// Every item and the folder they go to must be inside the root, and no folder may go into itself.
    private func checkDestination(_ folder: URL, for items: [URL]) throws {
        try checkWritable()
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        let destination = FileRoot.canonicalComponents(of: folder)
        for item in items {
            guard root.containsItem(at: item) else { throw FileOperationError.outsideRoot }
            guard !root.isRootFolder(item) else { throw FileOperationError.rootFolder }
            // A link is the item itself, so a link to a folder can be copied into that folder.
            if destination.starts(with: FileRoot.location(of: item)) {
                throw FileOperationError.intoItself
            }
        }
    }

    static func checkName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileOperationError.invalidName
        }
    }

    /// `name`, or the first of `name 2.ext`, `name 3.ext` and so on that's free in `folder`.
    func freeLocation(for name: String, in folder: URL) throws -> URL {
        let first = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) || Self.isLink(first) else { return first }
        let original = URL(fileURLWithPath: name)
        let (stem, pathExtension) = (original.deletingPathExtension().lastPathComponent, original.pathExtension)
        for number in 2...Self.nameAttempts {
            let numbered = pathExtension.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(pathExtension)"
            let candidate = folder.appendingPathComponent(numbered)
            if !FileManager.default.fileExists(atPath: candidate.path), !Self.isLink(candidate) {
                return candidate
            }
        }
        throw FileOperationError.noFreeName(name)
    }

    /// `fileExists` follows links, so a link whose target is gone would otherwise look free.
    private static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func isSameItem(_ first: URL, _ second: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let firstID = try? first.resourceValues(forKeys: key).fileResourceIdentifier,
            let secondID = try? second.resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return firstID.isEqual(secondID)
    }
}
