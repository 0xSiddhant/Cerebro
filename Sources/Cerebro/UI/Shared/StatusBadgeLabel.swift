import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// A colour-coded status, the same on every screen.
final class StatusBadgeLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        textColor = .white
        textAlignment = .center
        layer.cornerRadius = 6
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusBadgeLabel is built in code")
    }

    func show(_ status: String, outcome: TransactionOutcome) {
        text = "  \(status)  "
        backgroundColor = Self.color(for: outcome)
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
