import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// A row of the HTTP list, with a colour-coded status badge.
final class HTTPTransactionCell: UITableViewCell {
    static let reuseIdentifier = "HTTPTransactionCell"

    private let method = UILabel()
    private let path = UILabel()
    private let detail = UILabel()
    private let status = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        method.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        method.textColor = .secondaryLabel
        path.font = .preferredFont(forTextStyle: .subheadline)
        path.lineBreakMode = .byTruncatingMiddle
        detail.font = .preferredFont(forTextStyle: .caption1)
        detail.textColor = .secondaryLabel
        status.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        status.textColor = .white
        status.textAlignment = .center
        status.layer.cornerRadius = 6
        status.clipsToBounds = true
        status.translatesAutoresizingMaskIntoConstraints = false
        status.setContentHuggingPriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.required, for: .horizontal)

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
            status.heightAnchor.constraint(equalToConstant: 22),
            status.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
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
        status.text = "  \(row.status)  "
        status.backgroundColor = Self.color(for: row.outcome)
    }

    private static func color(for outcome: TransactionOutcome) -> UIColor {
        switch outcome {
        case .success: return .systemGreen
        case .redirection: return .systemBlue
        case .clientError: return .systemOrange
        case .serverError, .failed: return .systemRed
        case .cancelled: return .systemGray
        }
    }
}
