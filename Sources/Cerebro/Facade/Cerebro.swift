import UserNotifications
import os

#if SWIFT_PACKAGE
@_exported import CerebroCore
#endif

/// The host app's one entry point.
public enum Cerebro {
    private static let runtime = OSAllocatedUnfairLock<CaptureRuntime?>(initialState: nil)
    private static let postsNotification = OSAllocatedUnfairLock(initialState: false)

    @MainActor private static var dashboard: DashboardWindowManager?

    /// Starts capture. Call it as early as you can, because sessions created before it aren't captured.
    ///
    /// Capture runs on simulators and in development-signed builds. Distribution-signed builds stay off
    /// unless `allowsDistributionBuilds` is set. Calling this again while Cerebro runs does nothing.
    public static func start(_ configuration: CerebroConfiguration = CerebroConfiguration()) {
        let started = runtime.withLock { current -> CaptureRuntime? in
            guard current == nil, let runtime = CaptureRuntime(configuration: configuration) else { return nil }
            runtime.start()
            current = runtime
            return runtime
        }
        guard let started else { return }
        postsNotification.withLock { $0 = configuration.isNotificationTriggerEnabled }
        if configuration.isNotificationTriggerEnabled {
            NotificationTrigger.post()
        }
        Task { @MainActor in
            dashboard = DashboardWindowManager(
                sources: DashboardSources(
                    store: started.store,
                    socketStore: started.socketStore,
                    decoders: configuration.decoders,
                    systemInfo: started.systemInfo,
                    downloads: started.downloads,
                    archive: started.archive
                ),
                isShakeGestureEnabled: configuration.isShakeGestureEnabled
            )
        }
    }

    /// Stops capture and removes the dashboard.
    public static func stop() {
        let stopped = runtime.withLock { current -> CaptureRuntime? in
            defer { current = nil }
            return current
        }
        stopped?.stop()
        if postsNotification.withLock({ wasPosting -> Bool in
            defer { wasPosting = false }
            return wasPosting
        }) {
            NotificationTrigger.remove()
        }
        Task { @MainActor in
            dashboard?.remove()
            dashboard = nil
        }
    }

    /// Opens the dashboard if a notification tap was on Cerebro's own notification, and returns whether
    /// it was. Call it from `userNotificationCenter(_:didReceive:withCompletionHandler:)`, because your
    /// app owns the notification delegate.
    ///
    /// It does nothing unless `isNotificationTriggerEnabled` is set and Cerebro is running.
    @discardableResult
    public static func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        let identifier = response.notification.request.identifier
        let isEnabled = postsNotification.withLock { $0 }
        guard NotificationTrigger.opensDashboard(identifier: identifier, isEnabled: isEnabled) else { return false }
        present()
        return true
    }

    /// Opens the dashboard, for example from the app's own debug menu.
    public static func present() {
        Task { @MainActor in
            dashboard?.present()
        }
    }
}
