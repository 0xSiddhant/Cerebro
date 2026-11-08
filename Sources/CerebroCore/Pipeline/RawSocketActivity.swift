import Foundation

/// Who a socket is, already redacted. The same value travels with every frame and event.
struct SocketIdentity: Sendable, Equatable {
    let id: UUID
    let source: SocketSource
    let name: String
}

/// One thing that happened on a socket, before the pipeline runs.
struct RawSocketActivity: Sendable {
    enum Content: Sendable {
        case frame(SocketDirection, SocketPayload)
        case event(SocketEvent)
    }

    let socket: SocketIdentity
    let content: Content
    let date: Date
}
