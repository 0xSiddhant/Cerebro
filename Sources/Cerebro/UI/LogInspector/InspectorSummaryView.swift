import UIKit

/// The top of the Log Inspector: what the request was and how it went, at a glance.
final class InspectorSummaryView: UIView {
    private let status = StatusBadgeLabel()

    /// The error and the figures, which are what change while an event stream is open.
    private let details = UIStackView()

    /// `actions` sit on the title line, so they stay in view without adding height to the page.
    init(summary: InspectorSummary, actions: [UIView]) {
        super.init(frame: .zero)
        let method = UILabel()
        method.text = summary.method
        method.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        let title = UIStackView(arrangedSubviews: [method, UIView()] + actions + [status])
        title.alignment = .center
        title.spacing = 8
        details.axis = .vertical
        details.spacing = 12
        let stack = UIStackView(arrangedSubviews: [title, Self.urlLabel(summary.url), details])
        stack.axis = .vertical
        stack.spacing = 6
        show(summary)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // A table gives its header a height of zero until it has been measured, and a required bottom
        // constraint can't hold at that height, so this one gives way without a warning.
        let bottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        bottom.priority = .required - 1
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            bottom,
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSummaryView is built in code")
    }

    /// Shows how the request is going now. The title line and its buttons stay where they are, so a
    /// menu open on one of them isn't disturbed. The method and URL never change.
    func show(_ summary: InspectorSummary) {
        status.show(summary.status, outcome: summary.outcome)
        details.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let error = summary.error {
            details.addArrangedSubview(Self.errorLabel(error))
        }
        if !summary.stats.isEmpty {
            details.addArrangedSubview(Self.statsCard(summary.stats))
        }
        details.isHidden = details.arrangedSubviews.isEmpty
    }

    private static func urlLabel(_ url: String) -> UILabel {
        let label = UILabel()
        label.text = url
        label.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 3
        return label
    }

    private static func errorLabel(_ error: String) -> UILabel {
        let label = UILabel()
        label.text = error
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .systemRed
        label.numberOfLines = 3
        return label
    }

    private static func statsCard(_ stats: [InspectorStat]) -> UIView {
        let row = UIStackView(arrangedSubviews: stats.map(statView))
        row.distribution = .fillEqually
        row.spacing = 4
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        row.backgroundColor = .secondarySystemGroupedBackground
        row.layer.cornerRadius = 14
        row.layer.cornerCurve = .continuous
        return row
    }

    private static func statView(_ stat: InspectorStat) -> UIView {
        let title = UILabel()
        title.text = stat.title
        title.font = .preferredFont(forTextStyle: .caption2)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .secondaryLabel
        title.textAlignment = .center
        let value = UILabel()
        value.text = stat.value
        value.font = .systemFont(ofSize: 14, weight: .semibold)
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        value.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [title, value])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }
}
