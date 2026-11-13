import Foundation

/// What only the Info page shows about an item, read when it opens.
public struct FileDetails: Sendable, Equatable {
    /// The POSIX permission bits, such as `0o644`.
    public let permissions: Int?

    /// The data protection class, such as `NSFileProtectionComplete`. A simulator usually has none.
    public let protection: String?

    /// Whether the item is left out of iCloud and computer backups.
    public let isExcludedFromBackup: Bool

    /// Creates details.
    public init(permissions: Int?, protection: String?, isExcludedFromBackup: Bool) {
        self.permissions = permissions
        self.protection = protection
        self.isExcludedFromBackup = isExcludedFromBackup
    }

    /// Reads an item's details. A link's are its own, not its target's. It blocks, so call it off the
    /// main thread.
    public static func read(_ item: URL, root: FileRoot) throws -> Self {
        guard root.containsItem(at: item) else { throw FileOperationError.outsideRoot }
        let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
        let values = try? item.resourceValues(forKeys: [.fileProtectionKey, .isExcludedFromBackupKey])
        return Self(
            permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue,
            protection: values?.fileProtection?.rawValue,
            isExcludedFromBackup: values?.isExcludedFromBackup == true
        )
    }
}
