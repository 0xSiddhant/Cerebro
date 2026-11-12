import UIKit

/// A small tinted tag, such as a request's method. It's a soft tint behind coloured text, so it never
/// reads as a status, which is a solid badge.
final class TrafficTagLabel: UILabel {
    private static let inset = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        textAlignment = .center
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TrafficTagLabel is built in code")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + Self.inset.left + Self.inset.right,
            height: size.height + Self.inset.top + Self.inset.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: Self.inset))
    }

    func show(_ text: String, tint: UIColor) {
        self.text = text
        textColor = Self.readable(tint)
        backgroundColor = tint.withAlphaComponent(0.16)
    }

    /// The colour a method is known by, so a list can be scanned for one. Anything else is grey.
    static func tint(forMethod method: String) -> UIColor {
        switch method.uppercased() {
        case "GET": return .systemBlue
        case "POST": return .systemGreen
        case "PUT": return .systemOrange
        case "PATCH": return .systemPurple
        case "DELETE": return .systemRed
        default: return .systemGray
        }
    }

    /// System tints such as green and orange are too pale to read as text on a light background, so
    /// they're darkened there. In the dark they're bright enough as they are.
    private static func readable(_ tint: UIColor) -> UIColor {
        UIColor { traits in
            let resolved = tint.resolvedColor(with: traits)
            var (hue, saturation, brightness, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            guard traits.userInterfaceStyle != .dark,
                resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            else { return resolved }
            return UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.6, alpha: alpha)
        }
    }
}
