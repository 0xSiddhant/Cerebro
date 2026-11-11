import UserNotifications

/// A notification that opens the dashboard when tapped. Cerebro posts it but never asks for permission,
/// and the app forwards the tap, because the app owns both the permission and the notification delegate.
enum NotificationTrigger {
    static let identifier = "io.github.0xsiddhant.cerebro.open-dashboard"

    /// Whether a tap on the notification with this identifier should open the dashboard.
    static func opensDashboard(identifier: String, isEnabled: Bool) -> Bool {
        isEnabled && identifier == Self.identifier
    }

    /// Posts the notification if the app is already allowed to. Posting again replaces the earlier one.
    static func post() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional, .ephemeral]
            guard allowed.contains(settings.authorizationStatus) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Cerebro is capturing"
            content.body = "Tap to open the network inspector."
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func remove() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
