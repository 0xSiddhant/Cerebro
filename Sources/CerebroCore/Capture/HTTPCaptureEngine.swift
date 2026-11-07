import Foundation
import os

/// Owns the sessions behind capture. URLProtocol instances are created by the system, so they reach
/// this through `active`, the one shared reference, which `install` sets and `uninstall` clears.
final class HTTPCaptureEngine: Sendable {
    private static let current = OSAllocatedUnfairLock<HTTPCaptureEngine?>(initialState: nil)

    static var active: HTTPCaptureEngine? {
        current.withLock { $0 }
    }

    let bodyLimit: Int
    private let standardSession: CaptureSession
    private let ephemeralSession: CaptureSession
    private let record: @Sendable (RawExchange) -> Void

    /// Must run before `install`, because the sessions need configurations with nothing injected.
    init(bodyLimit: Int, record: @escaping @Sendable (RawExchange) -> Void) {
        self.bodyLimit = bodyLimit
        self.record = record
        standardSession = CaptureSession(configuration: .default)
        ephemeralSession = CaptureSession(configuration: .ephemeral)
    }

    func session(for kind: CustomURLProtocol.SessionKind) -> CaptureSession {
        kind == .ephemeral ? ephemeralSession : standardSession
    }

    func submit(_ exchange: RawExchange) {
        record(exchange)
    }

    func install() {
        let installed = Self.current.withLock { current -> Bool in
            guard current == nil else { return false }
            current = self
            return true
        }
        guard installed else { return }
        SessionConfigurationInjector.exchangeGetters()
        // The getters never reach URLSession.shared, but this does.
        URLProtocol.registerClass(CustomURLProtocol.self)
    }

    func uninstall() {
        let removed = Self.current.withLock { current -> Bool in
            guard current === self else { return false }
            current = nil
            return true
        }
        guard removed else { return }
        URLProtocol.unregisterClass(CustomURLProtocol.self)
        SessionConfigurationInjector.exchangeGetters()
        standardSession.invalidate()
        ephemeralSession.invalidate()
    }
}
