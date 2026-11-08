import Foundation
import os

/// Takes socket activity from every source. Hooks, wrappers and the bridge have no owner to hold
/// them, so they reach this through `active`, the one shared reference, set while capture runs.
final class SocketCaptureEngine: Sendable {
    private static let current = OSAllocatedUnfairLock<SocketCaptureEngine?>(initialState: nil)

    static var active: SocketCaptureEngine? {
        current.withLock { $0 }
    }

    private let redactor: Redactor
    private let record: @Sendable (RawSocketActivity) -> Void

    init(redactor: Redactor, record: @escaping @Sendable (RawSocketActivity) -> Void) {
        self.redactor = redactor
        self.record = record
    }

    /// Names a socket, redacting its URL so a secret in the query never reaches the store.
    func identity(id: UUID = UUID(), source: SocketSource, url: URL?, fallbackName: String) -> SocketIdentity {
        SocketIdentity(id: id, source: source, name: redactor.redact(url: url)?.absoluteString ?? fallbackName)
    }

    /// Hands activity to the background pipeline and returns.
    func submit(_ content: RawSocketActivity.Content, on socket: SocketIdentity) {
        record(RawSocketActivity(socket: socket, content: content, date: Date()))
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
}
