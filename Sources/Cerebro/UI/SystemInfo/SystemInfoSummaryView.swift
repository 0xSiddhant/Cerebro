import UIKit

/// The top of the System Info tab: whether the device is online, and over what, at a glance.
final class SystemInfoSummaryView: UIView {
    private let icon = UIImageView()
    private let title = UILabel()
    private let detail = UILabel()
    private let badges = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title1)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        title.font = .preferredFont(forTextStyle: .title3).withWeight(.semibold)
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        badges.font = .preferredFont(forTextStyle: .footnote)
        badges.textColor = .systemOrange
        for label in [title, detail, badges] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }

        let text = UIStackView(arrangedSubviews: [title, detail, badges])
        text.axis = .vertical
        text.spacing = 2
        let card = UIStackView(arrangedSubviews: [icon, text])
        card.alignment = .center
        card.spacing = 14
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SystemInfoSummaryView is built in code")
    }

    func show(_ summary: SystemInfoSummary) {
        icon.image = UIImage(systemName: summary.symbol)
        switch summary.tone {
        case .good: icon.tintColor = .systemGreen
        case .warning: icon.tintColor = .systemOrange
        case .bad: icon.tintColor = .systemRed
        case .unknown: icon.tintColor = .secondaryLabel
        }
        title.text = summary.title
        detail.text = summary.detail
        badges.text = summary.badges.joined(separator: " · ")
        badges.isHidden = summary.badges.isEmpty
        accessibilityLabel = ([summary.title, summary.detail] + summary.badges).joined(separator: ", ")
        isAccessibilityElement = true
    }
}

extension UIFont {
    fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let traits = [UIFontDescriptor.TraitKey.weight: weight]
        return UIFont(descriptor: fontDescriptor.addingAttributes([.traits: traits]), size: 0)
    }
}
