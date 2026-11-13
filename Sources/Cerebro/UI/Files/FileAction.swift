import Foundation

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
