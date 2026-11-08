import Foundation

/// Manual logging for socket engines Cerebro can't reach by itself, such as Starscream or Socket.IO.
///
/// Make one `Connection` per socket and keep it, then make one call per frame or event. While Cerebro
/// is off, every call does nothing.
public enum ExternalNetworkBridge {
    /// One socket in your engine.
    public struct Connection: Sendable, Hashable {
        fileprivate let id = UUID()

        /// What to call the socket if it has no URL.
        public let name: String

        /// The socket's URL, if it has one. Redaction rules apply to its query.
        public let url: URL?

        /// Creates a connection. Keep it for as long as the socket lives.
        public init(name: String, url: URL? = nil) {
            self.name = name
            self.url = url
        }
    }

    /// Logs one frame.
    public static func log(_ payload: SocketPayload, _ direction: SocketDirection, on connection: Connection) {
        submit(.frame(direction, payload), on: connection)
    }

    /// Logs anything else that happened on the socket.
    public static func log(_ event: SocketEvent, on connection: Connection) {
        submit(.event(event), on: connection)
    }

    private static func submit(_ content: RawSocketActivity.Content, on connection: Connection) {
        guard let engine = SocketCaptureEngine.active else { return }
        let socket = engine.identity(
            id: connection.id,
            source: .external,
            url: connection.url,
            fallbackName: connection.name
        )
        engine.submit(content, on: socket)
    }
}
