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
    private let reportDownload: @Sendable (DownloadEvent) -> Void

    /// Must run before `install`, because the sessions need configurations with nothing injected.
    init(
        bodyLimit: Int,
        reportDownload: @escaping @Sendable (DownloadEvent) -> Void = { _ in },
        record: @escaping @Sendable (RawExchange) -> Void
    ) {
        self.bodyLimit = bodyLimit
        self.reportDownload = reportDownload
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

    func report(_ event: DownloadEvent) {
        reportDownload(event)
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
        BackgroundSessionHooks.install()
    }

    func uninstall() {
        let removed = Self.current.withLock { current -> Bool in
            guard current === self else { return false }
            current = nil
            return true
        }
        guard removed else { return }
        BackgroundSessionHooks.uninstall()
        URLProtocol.unregisterClass(CustomURLProtocol.self)
        SessionConfigurationInjector.exchangeGetters()
    }
}
