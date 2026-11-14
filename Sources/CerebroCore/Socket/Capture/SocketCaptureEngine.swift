import Foundation
import os

/// Takes socket activity from every source. Hooks, wrappers and the bridge have no owner to hold
/// them, so they reach this through `active`, the one shared reference, set while capture runs.
final class SocketCaptureEngine: Sendable {
    private static let current = OSAllocatedUnfairLock<SocketCaptureEngine?>(initialState: nil)

    static var active: SocketCaptureEngine? {
        current.withLock { $0 }
    }

    private let bodyLimit: Int
    private let backlog: CaptureBacklog
    private let redactor: Redactor
    private let record: @Sendable (RawSocketActivity) -> Void

    init(
        bodyLimit: Int,
        backlog: CaptureBacklog,
        redactor: Redactor,
        record: @escaping @Sendable (RawSocketActivity) -> Void
    ) {
        self.bodyLimit = bodyLimit
        self.backlog = backlog
        self.redactor = redactor
        self.record = record
    }

    /// Names a socket, redacting its URL so a secret in the query never reaches the store.
    func identity(id: UUID = UUID(), source: SocketSource, url: URL?, fallbackName: String) -> SocketIdentity {
        SocketIdentity(id: id, source: source, name: redactor.redact(url: url)?.absoluteString ?? fallbackName)
    }

    /// Applies the stored-body cap and hands the frame to the background pipeline.
    func submit(
        _ payload: SocketPayload, _ direction: SocketDirection, didFail: Bool = false, on socket: SocketIdentity
    ) {
        let (kind, body) = capped(payload)
        let frame = RawSocketFrame(
            direction: direction,
            kind: kind,
            body: backlog.admit(bytes: body.data.count) ? body : nil,
            byteCount: body.byteCount,
            didFail: didFail
        )
        record(RawSocketActivity(socket: socket, content: .frame(frame), date: Date()))
    }

    /// Hands an event to the background pipeline.
    func submit(_ event: SocketEvent, on socket: SocketIdentity) {
        record(RawSocketActivity(socket: socket, content: .event(event), date: Date()))
    }

    func install() {
        let installed = Self.current.withLock { current -> Bool in
            guard current == nil else { return false }
            current = self
            return true
        }
        if installed {
            WebSocketTaskHooks.install()
        }
    }

    func uninstall() {
        let removed = Self.current.withLock { current -> Bool in
            guard current === self else { return false }
            current = nil
            return true
        }
        if removed {
            WebSocketTaskHooks.uninstall()
        }
    }

    private func capped(_ payload: SocketPayload) -> (SocketFrame.Kind, RawBody) {
        switch payload {
        case .text(let text):
            let bytes = text.utf8
            return (.text, RawBody(data: Data(bytes.prefix(bodyLimit)), limit: bodyLimit, isTruncatedFrom: bytes.count))
        case .binary(let data):
            return (.binary, RawBody(data: data, limit: bodyLimit))
        }
    }
}
