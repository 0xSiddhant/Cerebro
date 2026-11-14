import UIKit

/// The floating circle that opens the dashboard, showing Cerebro's icon. It drags, snaps to the nearest
/// edge and shows how many requests arrived since the dashboard was last opened.
final class FloatingTriggerView: UIView {
    private static let size: CGFloat = 44
    private static let margin: CGFloat = 12
    private static let glyphInset: CGFloat = 0.22
    private static let rimWidth: CGFloat = 1.5
    private static let badgeHeight: CGFloat = 16

    var onTap: (() -> Void)?

    /// How many new requests the badge shows. Zero hides it.
    var badgeCount = 0 {
        didSet { updateBadge() }
    }

    private let background = CAGradientLayer()
    private let rim = CAShapeLayer()
    private let glyph = CAShapeLayer()
    private let badge = UILabel()
    private var hasPosition = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        layer.shadowColor = DashboardTheme.shadow.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
        isAccessibilityElement = true
        accessibilityLabel = "Cerebro"
        accessibilityTraits = .button
        drawIcon()

        badge.backgroundColor = DashboardTheme.badge
        badge.textColor = DashboardTheme.onFill
        badge.textAlignment = .center
        badge.font = .boldSystemFont(ofSize: 10)
        badge.layer.cornerRadius = Self.badgeHeight / 2
        badge.clipsToBounds = true
        badge.isHidden = true
        addSubview(badge)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(didPan)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FloatingTriggerView is built in code")
    }

    /// Layers rather than an image, because the dashboard loads nothing from bundles.
    private func drawIcon() {
        background.frame = bounds
        background.cornerRadius = Self.size / 2
        background.colors = DashboardTheme.triggerBackground.map(\.cgColor)
        background.startPoint = .zero
        background.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(background)

        // A layer of its own rather than a border, which would be drawn over the badge.
        rim.path = UIBezierPath(ovalIn: bounds.insetBy(dx: Self.rimWidth / 2, dy: Self.rimWidth / 2)).cgPath
        rim.lineWidth = Self.rimWidth
        rim.strokeColor = DashboardTheme.triggerRim.cgColor
        rim.fillColor = nil
        layer.addSublayer(rim)

        let area = bounds.insetBy(dx: Self.size * Self.glyphInset, dy: Self.size * Self.glyphInset)
        var scale = CGAffineTransform(translationX: area.minX, y: area.minY)
            .scaledBy(x: area.width / 100, y: area.height / 100)
        let path = CerebroIcon.glyph().copy(using: &scale)
        glyph.path = path
        glyph.fillColor = DashboardTheme.triggerGlyph.cgColor
        glyph.shadowPath = path
        glyph.shadowColor = DashboardTheme.triggerGlyph.cgColor
        glyph.shadowOpacity = 0.85
        glyph.shadowRadius = Self.size * CerebroIcon.glowRadius
        glyph.shadowOffset = .zero
        layer.addSublayer(glyph)
    }

    /// Keeps the trigger inside `area`, starting at the lower right.
    func settle(in area: CGRect) {
        if !hasPosition {
            hasPosition = true
            center = CGPoint(x: area.maxX, y: area.maxY - area.height / 4)
        }
        center = snappedCenter(in: area)
    }

    private func snappedCenter(in area: CGRect) -> CGPoint {
        let inset = Self.size / 2 + Self.margin
        let left = area.minX + inset
        let right = area.maxX - inset
        return CGPoint(
            x: abs(center.x - left) < abs(center.x - right) ? left : right,
            y: min(max(center.y, area.minY + inset), area.maxY - inset)
        )
    }

    @objc private func didTap() {
        onTap?()
    }

    @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .changed:
            let movement = gesture.translation(in: superview)
            center = CGPoint(x: center.x + movement.x, y: center.y + movement.y)
            gesture.setTranslation(.zero, in: superview)
        case .ended, .cancelled:
            let area = superview.bounds.inset(by: superview.safeAreaInsets)
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.center = self.snappedCenter(in: area)
            }
        default:
            break
        }
    }

    private func updateBadge() {
        badge.isHidden = badgeCount == 0
        badge.text = badgeCount > 99 ? "99+" : String(badgeCount)
        accessibilityValue = badgeCount == 0 ? nil : "\(badge.text ?? "") new"
        let width = max(Self.badgeHeight, badge.intrinsicContentSize.width + 8)
        badge.frame = CGRect(x: bounds.maxX - width + 4, y: -4, width: width, height: Self.badgeHeight)
    }
}
