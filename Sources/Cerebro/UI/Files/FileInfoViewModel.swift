import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One line of the Info page.
struct FileInfoRow: Equatable {
    let title: String
    let value: String
}

/// What the Info page shows about one item. The basics come from the listing, and the rest is read when
/// the page opens, off the main thread.
@MainActor
final class FileInfoViewModel {
    let entry: FileEntry
    private let root: FileRoot

    private(set) var rows: [FileInfoRow]

    /// Called after `rows` changes.
    var onChange: (() -> Void)?

    init(entry: FileEntry, root: FileRoot) {
        self.entry = entry
        self.root = root
        rows = Self.rows(for: entry, in: root, details: nil, contents: nil)
    }

    /// Reads the permissions, protection and backup flag, and for a folder what it holds.
    func load() async {
        let (entry, root) = (entry, root)
        let (details, contents) = await Task.detached(priority: .userInitiated) {
            (
                try? FileDetails.read(entry.url, root: root),
                entry.kind == .folder ? try? FolderMeasurement.measure(entry.url, root: root) : nil
            )
        }
        .value
        rows = Self.rows(for: entry, in: root, details: details, contents: contents)
        onChange?()
    }

    static func rows(
        for entry: FileEntry,
        in root: FileRoot,
        details: FileDetails?,
        contents: FolderMeasurement?
    ) -> [FileInfoRow] {
        var rows = [
            FileInfoRow(title: "Name", value: entry.name),
            FileInfoRow(title: "Kind", value: FileSymbols.typeName(of: entry)),
            FileInfoRow(title: "Location", value: root.name),
            FileInfoRow(title: "Path in Location", value: root.relativePath(of: entry.url) ?? entry.name),
            FileInfoRow(title: "Full Path", value: entry.url.path),
        ]
        if let target = entry.linkTarget {
            rows.append(FileInfoRow(title: "Link Target", value: target))
        }
        if let size = entry.size {
            let rounded = DisplayFormat.bytes(size)
            let exact = "\(size.formatted()) bytes"
            rows.append(FileInfoRow(title: "Size", value: rounded == exact ? exact : "\(rounded) (\(exact))"))
        }
        if let contents {
            rows.append(FileInfoRow(title: "Contents", value: DisplayFormat.folderContents(contents)))
        }
        if let created = entry.created {
            rows.append(FileInfoRow(title: "Created", value: DisplayFormat.fileDate(created)))
        }
        if let modified = entry.modified {
            rows.append(FileInfoRow(title: "Modified", value: DisplayFormat.fileDate(modified)))
        }
        rows.append(FileInfoRow(title: "Writable", value: !root.isReadOnly && entry.isWritable ? "Yes" : "No"))
        if let details {
            if let permissions = details.permissions {
                rows.append(FileInfoRow(title: "Permissions", value: permissionsText(permissions)))
            }
            rows.append(FileInfoRow(title: "Data Protection", value: protectionText(details.protection)))
            rows.append(
                FileInfoRow(title: "Backed Up", value: details.isExcludedFromBackup ? "No, excluded" : "Yes"))
        }
        return rows
    }

    /// Such as `rw-r--r-- (644)`.
    static func permissionsText(_ bits: Int) -> String {
        let symbols = (0..<9).map { position -> Character in
            guard bits & (1 << (8 - position)) != 0 else { return "-" }
            return ["r", "w", "x"][position % 3]
        }
        return "\(String(symbols)) (\(String(bits & 0o777, radix: 8)))"
    }

    static func protectionText(_ protection: String?) -> String {
        guard let protection else { return "Not set" }
        switch URLFileProtection(rawValue: protection) {
        case .complete: return "Complete"
        case .completeUnlessOpen: return "Complete unless open"
        case .completeUntilFirstUserAuthentication: return "Until first unlock"
        case URLFileProtection.none: return "None"
        default: return protection
        }
    }
}
