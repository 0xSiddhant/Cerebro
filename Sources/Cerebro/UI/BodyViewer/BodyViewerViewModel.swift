import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Formats a body only when it's opened, and off the main thread.
@MainActor
final class BodyViewerViewModel {
    /// How the viewer shows a body.
    enum Mode {
        case tree
        case pretty
        case raw

        var title: String {
            switch self {
            case .tree: return "Tree"
            case .pretty: return "Pretty"
            case .raw: return "Raw"
            }
        }
    }

    let title: String

    /// A name for this body when it's shared as a file.
    let fileName: String

    /// What the copy confirmation says, which warns when part of the body was never stored.
    let copyMessage: String

    /// The views this body offers, in order. Only a decoded body has a tree, and it opens there.
    let modes: [Mode]

    private let body: CapturedBody

    init(title: String, body: CapturedBody) {
        self.title = title
        self.body = body
        modes = body.isDecoded ? [.tree, .pretty, .raw] : [.pretty, .raw]
        let content = body.data ?? Data()
        let stem = title.lowercased().replacingOccurrences(of: " ", with: "-")
        fileName = stem + (Self.looksLikeJSON(content) ? ".json" : ".txt")
        if case .truncated = body.content {
            copyMessage = "Copied. This body was cut off at capture, so it's incomplete."
        } else {
            copyMessage = "Copied."
        }
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        let whitespace = Set("  \n\r\t".utf8)
        let first = data.first { !whitespace.contains($0) }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    /// The text for a mode. A body that isn't JSON has nothing to pretty-print, so it falls back to raw.
    func text(for mode: Mode) async -> String {
        await Task.detached(priority: .userInitiated) { [body] in
            mode == .raw ? BodyFormatter.raw(body) : BodyFormatter.pretty(body)
        }
        .value
    }

    /// The body as a tree, or `nil` if it isn't JSON.
    func tree() async -> JSONTree? {
        await Task.detached(priority: .userInitiated) { [body] in
            body.data.flatMap { JSONTree(json: $0) }
        }
        .value
    }
}
