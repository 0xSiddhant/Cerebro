import UniformTypeIdentifiers

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The SF Symbol and the type name each kind of item shows, from its extension.
enum FileSymbols {
    static func symbol(for entry: FileEntry) -> String {
        switch entry.kind {
        case .folder: return "folder"
        case .symbolicLink: return "link"
        case .file: break
        }
        guard let type = contentType(of: entry.url) else { return "doc" }
        let symbols: [(UTType, String)] = [
            (.image, "photo"),
            (.movie, "film"),
            (.audio, "waveform"),
            (.pdf, "doc.richtext"),
            (.json, "curlybraces"),
            (.propertyList, "list.bullet.indent"),
            (.database, "cylinder.split.1x2"),
            (.archive, "doc.zipper"),
            (.text, "doc.text"),
        ]
        return symbols.first { type.conforms(to: $0.0) }?.1 ?? "doc"
    }

    /// What the Info page calls an item's type, such as "PNG image".
    static func typeName(of entry: FileEntry) -> String {
        switch entry.kind {
        case .folder: return "Folder"
        case .symbolicLink: return "Symbolic link"
        case .file: return contentType(of: entry.url)?.localizedDescription ?? "Unknown"
        }
    }

    private static func contentType(of url: URL) -> UTType? {
        let pathExtension = url.pathExtension
        return pathExtension.isEmpty ? nil : UTType(filenameExtension: pathExtension)
    }
}
