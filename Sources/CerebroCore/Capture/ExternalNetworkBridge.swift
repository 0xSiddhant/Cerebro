import Foundation

/// Manual logging for socket engines Cerebro can't reach by itself, such as Starscream or Socket.IO.
///
/// Make one `Connection` per socket and keep it, then make one call per frame or event. While Cerebro
/// is off, every call does nothing.
public enum ExternalNetworkBridge {
    /// One socket in your engine.
    public struct Connection: Sendable, Hashable {
        fileprivate let id = UUID()
        fileprivate let identity = SocketIdentitySlot()

        /// What to call the socket if it has no URL.
        public let name: String

        /// The socket's URL, if it has one. Redaction rules apply to its query.
        public let url: URL?

        /// Creates a connection. Keep it for as long as the socket lives.
        public init(name: String, url: URL? = nil) {
            self.name = name
            self.url = url
        }

        /// Whether two values are the same socket.
        public static func == (first: Self, second: Self) -> Bool {
            first.id == second.id
        }

        /// Hashes the socket's identity.
        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    /// Logs one frame.
    public static func log(_ payload: SocketPayload, _ direction: SocketDirection, on connection: Connection) {
        guard let engine = SocketCaptureEngine.active else { return }
        engine.submit(payload, direction, on: identity(of: connection, with: engine))
    }

    /// Logs anything else that happened on the socket.
    public static func log(_ event: SocketEvent, on connection: Connection) {
        guard let engine = SocketCaptureEngine.active else { return }
        engine.submit(event, on: identity(of: connection, with: engine))
    }

    private static func identity(of connection: Connection, with engine: SocketCaptureEngine) -> SocketIdentity {
        connection.identity.value {
            engine.identity(id: connection.id, source: .external, url: connection.url, fallbackName: connection.name)
        }
    }
}
