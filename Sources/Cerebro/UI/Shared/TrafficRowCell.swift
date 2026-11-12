import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// What marks a row as something other than an ordinary request.
enum TrafficRowMarker: Equatable {
    /// A Server-Sent Events stream, and whether it's still open.
    case eventStream(isLive: Bool)
}

/// A row of the HTTP or Sockets list: a tinted tag for what it is, and a colour-coded status badge.
final class TrafficRowCell: UITableViewCell {
    static let reuseIdentifier = "TrafficRowCell"

    private static let liveTint = UIColor.systemTeal

    private let method = TrafficTagLabel()
    private let marker = TrafficTagLabel()
    private let path = UILabel()
    private let detail = UILabel()
    private let status = StatusBadgeLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        path.font = .preferredFont(forTextStyle: .subheadline)
        path.lineBreakMode = .byTruncatingMiddle
        detail.font = .preferredFont(forTextStyle: .caption1)
        detail.textColor = .secondaryLabel

        let top = UIStackView(arrangedSubviews: [method, marker, path])
        top.spacing = 6
        top.alignment = .center
        // Wide enough for the common methods, so paths line up down the list.
        method.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        let text = UIStackView(arrangedSubviews: [top, detail])
        text.axis = .vertical
        text.spacing = 3
        let line = UIStackView(arrangedSubviews: [text, status])
        line.spacing = 10
        line.alignment = .center
        line.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            line.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TrafficRowCell is built in code")
    }

    /// `tagTint` colours the tag, and `marker` adds a second one beside it.
    func show(
        tag: String,
        tagTint: UIColor = .systemGray,
        marker: TrafficRowMarker? = nil,
        title: String,
        detail: String,
        status: String,
        outcome: TransactionOutcome
    ) {
        method.show(tag, tint: tagTint)
        switch marker {
        case .eventStream(let isLive):
            // The dot and the colour both say it's still arriving, so colour isn't the only sign.
            self.marker.show(isLive ? "● SSE" : "SSE", tint: isLive ? Self.liveTint : .systemGray)
        case nil:
            break
        }
        self.marker.isHidden = marker == nil
        path.text = title
        self.detail.text = detail
        self.status.show(status, outcome: outcome)
    }
}
