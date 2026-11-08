import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One bubble of a socket's timeline.
struct SocketFrameRow: Equatable {
    let text: String
    let detail: String
    let isSent: Bool
    let didFail: Bool
    let body: CapturedBody?
}

/// One line of a socket's timeline.
enum SocketTimelineRow: Equatable {
    case frame(SocketFrameRow)
    case event(String)
}

/// One socket as a conversation, oldest first. Rows are formatted when a cell asks for one, so a long
/// timeline only ever pays for what's on screen.
@MainActor
final class SocketTimelineViewModel {
    let title: String
    private(set) var items: [SocketTimelineItem] = []

    /// Called after `items` changes.
    var onChange: (() -> Void)?

    private let store: SocketStore
    private let connectionID: UUID
    private var updates: Task<Void, Never>?

    init(store: SocketStore, connection: SocketConnection) {
        self.store = store
        connectionID = connection.id
        title = URL(string: connection.name)?.host ?? connection.name
        items = connection.timeline
    }

    deinit {
        updates?.cancel()
    }

    func startObserving() {
        guard updates == nil else { return }
        updates = Task { [weak self, store] in
            for await connections in await store.updates() {
                self?.show(connections)
            }
        }
    }

    func show(_ connections: [SocketConnection]) {
        guard let connection = connections.first(where: { $0.id == connectionID }),
            connection.timeline != items
        else { return }
        items = connection.timeline
        onChange?()
    }

    func row(at index: Int) -> SocketTimelineRow {
        switch items[index] {
        case .frame(let frame):
            return .frame(Self.row(for: frame))
        case .event(let event, let date):
            return .event("\(Self.description(of: event)) · \(DisplayFormat.time(date))")
        }
    }

    private static func row(for frame: SocketFrame) -> SocketFrameRow {
        SocketFrameRow(
            text: text(of: frame),
            detail: detail(of: frame),
            isSent: frame.direction == .sent,
            didFail: frame.didFail,
            body: frame.payload?.data == nil ? nil : frame.payload
        )
    }

    private static func text(of frame: SocketFrame) -> String {
        guard let payload = frame.payload else { return "Empty frame" }
        guard let data = payload.data else {
            return payload.content == .withheld
                ? "Withheld, because it couldn't be redacted"
                : "Not stored, because frames arrived too fast"
        }
        return DisplayFormat.preview(of: data) ?? "Binary data"
    }

    private static func detail(of frame: SocketFrame) -> String {
        var parts = [
            frame.kind == .text ? "Text" : "Binary",
            DisplayFormat.bytes(Int64(frame.byteCount)),
        ]
        if case .truncated = frame.payload?.content {
            parts.append("truncated")
        }
        if let compression = frame.payload?.compression {
            parts.append(compression.rawValue)
        }
        if frame.didFail {
            parts.append("failed")
        }
        parts.append(DisplayFormat.time(frame.date))
        return parts.joined(separator: " · ")
    }

    private static func description(of event: SocketEvent) -> String {
        switch event {
        case .opened: return "Opened"
        case .closed(let code, let reason): return closeDescription(code: code, reason: reason)
        case .ping: return "Ping"
        case .pong: return "Pong"
        case .stateChanged(let state): return state
        case .failed(let description): return "Failed: \(description)"
        }
    }

    private static func closeDescription(code: Int?, reason: String?) -> String {
        let parts = [code.map(String.init), reason].compactMap { $0 }
        return parts.isEmpty ? "Closed" : "Closed: \(parts.joined(separator: " "))"
    }
}
