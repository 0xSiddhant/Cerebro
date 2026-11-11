import Foundation
import os

/// Who a socket is, already redacted. The same value travels with every frame and event.
struct SocketIdentity: Sendable, Equatable, Codable {
    let id: UUID
    let source: SocketSource
    let name: String
}

/// Works out a socket's identity once, because naming it again for every frame would be wasted work
/// on the caller's thread. If two threads race, both arrive at the same value.
struct SocketIdentitySlot: Sendable {
    private let stored = OSAllocatedUnfairLock<SocketIdentity?>(initialState: nil)

    func value(orMake make: () -> SocketIdentity) -> SocketIdentity {
        if let existing = stored.withLock({ $0 }) {
            return existing
        }
        let made = make()
        stored.withLock { $0 = made }
        return made
    }
}

/// A frame as captured, before the pipeline runs. It only ever holds up to the stored-body cap.
struct RawSocketFrame: Sendable {
    let direction: SocketDirection
    let kind: SocketFrame.Kind

    /// `nil` when frames were arriving too fast to queue, so only the frame's size was kept.
    let body: RawBody?
    let byteCount: Int
    let didFail: Bool
}

/// One thing that happened on a socket, before the pipeline runs.
struct RawSocketActivity: Sendable {
    enum Content: Sendable {
        case frame(RawSocketFrame)
        case event(SocketEvent)
    }

    let socket: SocketIdentity
    let content: Content
    let date: Date

    /// How many payload bytes this holds while it waits for the pipeline.
    var backlogBytes: Int {
        guard case .frame(let frame) = content else { return 0 }
        return frame.body?.data.count ?? 0
    }
}
