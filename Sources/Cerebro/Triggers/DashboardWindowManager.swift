import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Owns Cerebro's window and everything in it. The dashboard is presented there, so it never touches
/// the app's own view hierarchy or navigation stack.
@MainActor
final class DashboardWindowManager: NSObject {
    private let sources: DashboardSources
    private let overlay = OverlayViewController()
    private var window: PassthroughWindow?
    private weak var previousKeyWindow: UIWindow?
    private var wantsDashboard = false
    private var badgeUpdates: Task<Void, Never>?
    private var unseenRequests = UnseenRequestCounter()

    init(sources: DashboardSources, isShakeGestureEnabled: Bool) {
        self.sources = sources
        super.init()
        DashboardTheme.register()
        overlay.trigger.onTap = { [weak self] in self?.present() }
        if isShakeGestureEnabled {
            ShakeDetector.install { [weak self] in self?.toggleTrigger() }
        }
        badgeUpdates = Task { [weak self, store = sources.store] in
            // Only requests being added or removed, so an open event stream never wakes the badge.
            for await transactions in await store.requestUpdates() {
                self?.updateBadge(with: transactions)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate),
            name: UIScene.didActivateNotification,
            object: nil
        )
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            attach(to: active)
        }
    }

    func present() {
        guard let window else {
            wantsDashboard = true
            return
        }
        guard overlay.presentedViewController == nil else { return }
        unseenRequests.markAllSeen()
        overlay.trigger.badgeCount = 0
        // Text fields need a key window. The app gets it back when the dashboard closes.
        previousKeyWindow = window.windowScene?.keyWindow
        window.makeKey()
        let dashboard = DashboardTabBarController(
            sources: sources,
            onClose: { [weak self] in self?.previousKeyWindow?.makeKey() }
        )
        dashboard.modalPresentationStyle = .fullScreen
        overlay.present(dashboard, animated: true)
    }

    func remove() {
        ShakeDetector.uninstall()
        badgeUpdates?.cancel()
        overlay.presentedViewController?.dismiss(animated: false)
        previousKeyWindow?.makeKey()
        window?.isHidden = true
        window = nil
    }

    private func updateBadge(with transactions: [HTTPTransaction]) {
        unseenRequests.update(with: transactions)
        // Anything that arrives while the dashboard is open is already on screen.
        if overlay.presentedViewController != nil {
            unseenRequests.markAllSeen()
        }
        overlay.trigger.badgeCount = unseenRequests.unseenCount
    }

    private func toggleTrigger() {
        overlay.trigger.isHidden.toggle()
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        if let scene = notification.object as? UIWindowScene {
            attach(to: scene)
        }
    }

    private func attach(to scene: UIWindowScene) {
        if let window {
            window.windowScene = scene
        } else {
            let window = PassthroughWindow(windowScene: scene)
            window.windowLevel = .statusBar + 1
            // Cerebro's own window, so the accent reaches every screen and alert without touching the app.
            window.tintColor = DashboardTheme.accent
            window.rootViewController = overlay
            window.isHidden = false
            self.window = window
        }
        if wantsDashboard {
            wantsDashboard = false
            present()
        }
    }
}
