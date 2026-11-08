import UIKit

/// The top of the Log Inspector: what the request was and how it went, at a glance.
final class InspectorSummaryView: UIView {
    /// `actions` sit on the title line, so they stay in view without adding height to the page.
    init(summary: InspectorSummary, actions: [UIView]) {
        super.init(frame: .zero)
        let stack = UIStackView(
            arrangedSubviews: [Self.titleLine(for: summary, actions: actions), Self.urlLabel(summary.url)]
        )
        stack.axis = .vertical
        stack.spacing = 6
        if let error = summary.error {
            stack.addArrangedSubview(Self.errorLabel(error))
        }
        if !summary.stats.isEmpty {
            let stats = Self.statsCard(summary.stats)
            stack.addArrangedSubview(stats)
            stack.setCustomSpacing(12, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSummaryView is built in code")
    }

    private static func titleLine(for summary: InspectorSummary, actions: [UIView]) -> UIView {
        let method = UILabel()
        method.text = summary.method
        method.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        let status = StatusBadgeLabel()
        status.show(summary.status, outcome: summary.outcome)
        let line = UIStackView(arrangedSubviews: [method, UIView()] + actions + [status])
        line.alignment = .center
        line.spacing = 8
        return line
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
