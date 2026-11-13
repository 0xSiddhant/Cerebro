import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Where a body came from, which changes what the viewer says about it.
enum BodyViewerSource {
    /// Captured traffic.
    case capture

    /// A file in the app's sandbox, read up to the stored-body cap.
    case file
}

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

    /// What the copy confirmation says, which warns when part of the body was never stored.
    let copyMessage: String

    /// The views this body offers, in order. Only a decoded body has a tree, and it opens there.
    let modes: [Mode]

    /// A line above the body saying it was cut off, for a file. A captured body says so where it's listed.
    let notice: String?

    /// What the warning says before the body is shared.
    let shareWarning: ShareWarning

    private let body: CapturedBody

    init(title: String, body: CapturedBody, source: BodyViewerSource = .capture) {
        self.title = title
        self.body = body
        modes = body.isDecoded ? [.tree, .pretty, .raw] : [.pretty, .raw]
        shareWarning = source == .file ? .files : .capturedData
        guard case .truncated(let data) = body.content else {
            copyMessage = "Copied."
            notice = nil
            return
        }
        switch source {
        case .capture:
            copyMessage = "Copied. This body was cut off at capture, so it's incomplete."
            notice = nil
        case .file:
            copyMessage = "Copied. This file was cut off at the body limit, so it's incomplete."
            let shown = DisplayFormat.bytes(Int64(data.count))
            let hex = body.undecoded == nil ? "" : ", as hex"
            notice = "Truncated: the first \(shown) of \(DisplayFormat.bytes(Int64(body.byteCount)))\(hex)"
        }
    }

    /// A name for this body when it's shared as a file from a mode. Hex is never JSON, even when the
    /// stored bytes are.
    func fileName(for mode: Mode) -> String {
        let stem = title.lowercased().replacingOccurrences(of: " ", with: "-")
        let isHex = body.undecoded != nil || (mode == .raw && body.rawData != nil)
        return stem + (!isHex && Self.looksLikeJSON(body.data ?? Data()) ? ".json" : ".txt")
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
