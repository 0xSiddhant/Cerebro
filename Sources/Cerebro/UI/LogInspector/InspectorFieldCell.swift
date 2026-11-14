import UIKit

/// A compact name and value on one line, in columns that line up down the list.
final class InspectorFieldCell: UITableViewCell {
    static let reuseIdentifier = "InspectorFieldCell"

    private static let collapsedLines = 3

    private let name = UILabel()
    private let value = UILabel()
    private let timeline = InspectorTimelineView()
    private let columns: UIStackView
    private let nameWidth: NSLayoutConstraint

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        columns = UIStackView(arrangedSubviews: [name, value])
        nameWidth = name.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: 0.38)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        name.font = .preferredFont(forTextStyle: .caption1)
        name.adjustsFontForContentSizeCategory = true
        name.textColor = DashboardTheme.secondaryText
        name.numberOfLines = 2
        name.lineBreakMode = .byTruncatingMiddle
        value.font = .preferredFont(forTextStyle: .footnote)
        value.adjustsFontForContentSizeCategory = true
        columns.spacing = 10
        columns.alignment = .firstBaseline

        let stack = UIStackView(arrangedSubviews: [columns, timeline])
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            nameWidth,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorFieldCell is built in code")
    }

    func show(_ row: InspectorRow, isExpanded: Bool) {
        name.text = row.title
        value.text = row.value
        value.numberOfLines = isExpanded ? 0 : Self.collapsedLines
        timeline.span = row.span
        timeline.isHidden = row.span == nil

        // At the largest text sizes, two columns leave too little room for either.
        let isStacked = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        columns.axis = isStacked ? .vertical : .horizontal
        columns.alignment = isStacked ? .leading : .firstBaseline
        nameWidth.isActive = !isStacked
    }
}

/// A thin bar showing where one stage falls within a whole request.
private final class InspectorTimelineView: UIView {
    private let fill = UIView()

    var span: InspectorSpan? {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DashboardTheme.track
        layer.cornerRadius = 1.5
        clipsToBounds = true
        fill.backgroundColor = DashboardTheme.accent
        addSubview(fill)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 3).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTimelineView is built in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let span else { return }
        fill.frame = CGRect(
            x: bounds.width * span.start,
            y: 0,
            width: max(bounds.width * span.length, 2),
            height: bounds.height
        )
    }
}
