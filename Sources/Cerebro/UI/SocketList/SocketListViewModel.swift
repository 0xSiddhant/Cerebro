import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One line of the Sockets list.
struct SocketListRow: Equatable, Identifiable {
    let id: UUID
    let tag: String
    let name: String
    let detail: String
    let status: String
    let outcome: TransactionOutcome
}

/// What the Sockets tab shows: every socket, newest first.
@MainActor
final class SocketListViewModel {
    private(set) var rows: [SocketListRow] = []

    /// Called after `rows` changes.
    var onChange: (() -> Void)?

    private let store: SocketStore
    private var connections: [SocketConnection] = []
    private var updates: Task<Void, Never>?

    init(store: SocketStore) {
        self.store = store
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
        self.connections = connections.reversed()
        rows = self.connections.map(Self.row)
        onChange?()
    }

    func connection(id: UUID) -> SocketConnection? {
        connections.first { $0.id == id }
    }

    private static func row(for connection: SocketConnection) -> SocketListRow {
        let frames = connection.frameCount == 1 ? "1 frame" : "\(connection.frameCount) frames"
        let sent = DisplayFormat.bytes(connection.bytesSent)
        let received = DisplayFormat.bytes(connection.bytesReceived)
        return SocketListRow(
            id: connection.id,
            tag: tag(for: connection.source),
            name: connection.name,
            detail: "\(frames) · \(sent) sent · \(received) received",
            status: status(of: connection.status),
            outcome: outcome(of: connection.status)
        )
    }

    private static func tag(for source: SocketSource) -> String {
        switch source {
        case .webSocketTask: return "WS"
        case .nwConnection: return "NW"
        case .external: return "EXT"
        }
    }

    private static func status(of status: SocketStatus) -> String {
        switch status {
        case .connecting: return "Connecting"
        case .open: return "Open"
        case .closed: return "Closed"
        case .failed: return "Failed"
        }
    }

    /// Sockets share the HTTP badge colours: green for healthy, gray for finished, red for failed.
    private static func outcome(of status: SocketStatus) -> TransactionOutcome {
        switch status {
        case .connecting: return .redirection
        case .open: return .success
        case .closed: return .cancelled
        case .failed: return .failed
        }
    }
}
