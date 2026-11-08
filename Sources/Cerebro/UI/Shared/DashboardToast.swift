import UIKit

/// A short message that appears over the dashboard and fades away.
@MainActor
enum DashboardToast {
    private static let visibleTime: Duration = .milliseconds(2_200)
    private static let tag = 0x0C_E8_EB_80

    static func show(_ message: String, in host: UIView) {
        host.viewWithTag(tag)?.removeFromSuperview()
        let label = UILabel()
        label.text = message
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        pill.tag = tag
        pill.layer.cornerRadius = 14
        pill.clipsToBounds = true
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(label)
        host.addSubview(pill)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            pill.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 24),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -24),
        ])

        UIAccessibility.post(notification: .announcement, argument: message)
        pill.alpha = 0
        UIView.animate(withDuration: 0.2) { pill.alpha = 1 }
        // A delayed animation would set alpha to 0 at once, which hides the message from VoiceOver.
        Task {
            try? await Task.sleep(for: visibleTime)
            UIView.animate(withDuration: 0.3) {
                pill.alpha = 0
            } completion: { _ in
                pill.removeFromSuperview()
            }
        }
    }
}
