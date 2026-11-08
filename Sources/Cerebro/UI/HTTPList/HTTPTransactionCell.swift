import UIKit

/// A row of the HTTP list, with a colour-coded status badge.
final class HTTPTransactionCell: UITableViewCell {
    static let reuseIdentifier = "HTTPTransactionCell"

    private let method = UILabel()
    private let path = UILabel()
    private let detail = UILabel()
    private let status = StatusBadgeLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        method.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        method.textColor = .secondaryLabel
        path.font = .preferredFont(forTextStyle: .subheadline)
        path.lineBreakMode = .byTruncatingMiddle
        detail.font = .preferredFont(forTextStyle: .caption1)
        detail.textColor = .secondaryLabel

        let top = UIStackView(arrangedSubviews: [method, path])
        top.spacing = 6
        method.setContentHuggingPriority(.required, for: .horizontal)
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
        fatalError("HTTPTransactionCell is built in code")
    }

    func show(_ row: HTTPListRow) {
        method.text = row.method
        path.text = row.path
        detail.text = row.detail
        status.show(row.status, outcome: row.outcome)
    }
}
