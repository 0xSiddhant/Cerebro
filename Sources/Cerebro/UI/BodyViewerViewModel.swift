import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Formats a body only when it's opened, and off the main thread.
@MainActor
final class BodyViewerViewModel {
    /// How the viewer shows a body.
    enum Mode: Int {
        case pretty
        case raw
    }

    let title: String
    private let data: Data

    init(title: String, body: CapturedBody) {
        self.title = title
        data = body.data ?? Data()
    }

    /// The text for a mode. A body that isn't JSON has nothing to pretty-print, so it falls back to raw.
    func text(for mode: Mode) async -> String {
        await Task.detached(priority: .userInitiated) { [data] in
            let pretty = mode == .pretty ? BodyFormatter.prettyJSON(data) : nil
            return pretty ?? BodyFormatter.text(data)
        }
        .value
    }
}
