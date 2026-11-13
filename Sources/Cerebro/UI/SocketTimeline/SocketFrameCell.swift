import UIKit

/// One frame as a chat bubble: sent on the right in blue, received on the left in gray, failed in red.
final class SocketFrameCell: UITableViewCell {
    static let reuseIdentifier = "SocketFrameCell"

    private static let previewLines = 8

    private let bubble = UIView()
    private let message = UILabel()
    private let detail = UILabel()
    private lazy var sentConstraint = bubble.trailingAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.trailingAnchor
    )
    private lazy var receivedConstraint = bubble.leadingAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.leadingAnchor
    )

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        message.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = Self.previewLines
        detail.font = .preferredFont(forTextStyle: .caption2)
        detail.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [message, detail])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = 14
        bubble.layer.cornerCurve = .continuous
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(stack)
        contentView.addSubview(bubble)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubble.widthAnchor.constraint(
                lessThanOrEqualTo: contentView.layoutMarginsGuide.widthAnchor,
                multiplier: 0.85
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SocketFrameCell is built in code")
    }

    func show(_ row: SocketFrameRow) {
        message.text = row.text
        detail.text = row.detail
        sentConstraint.isActive = row.isSent
        receivedConstraint.isActive = !row.isSent
        bubble.backgroundColor =
            row.didFail
            ? DashboardTheme.failure : row.isSent ? DashboardTheme.accentFill : DashboardTheme.raised
        message.textColor = row.isSent ? DashboardTheme.onFill : DashboardTheme.primaryText
        detail.textColor = row.isSent ? DashboardTheme.onFill.withAlphaComponent(0.8) : DashboardTheme.secondaryText
    }
}
