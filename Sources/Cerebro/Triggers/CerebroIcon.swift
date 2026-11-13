import CoreGraphics

/// Cerebro's icon: a globe with every signal it has found, as the machine it's named after finds every
/// mind. It's drawn in code because the dashboard loads nothing from bundles, and this file uses only
/// CoreGraphics so `Scripts/render-icon.sh` can render the README logo and the Example's app icon from it.
enum CerebroIcon {
    /// The Ultraviolet palette, as sRGB hex. `DashboardTheme` takes its brand colours from here.
    enum Palette {
        /// The background at the top left.
        static let backgroundTop: UInt32 = 0x1A0B_2E

        /// The background at the bottom right.
        static let backgroundBottom: UInt32 = 0x0401_08

        /// The glyph, its glow, and the button's rim.
        static let glyph: UInt32 = 0xC084_FC
    }

    /// How strong the button's rim is, as a share of the glyph's colour. It keeps the dark button visible
    /// over a dark app.
    static let rimOpacity: CGFloat = 0.55

    /// The glow around the glyph, as a share of the icon's width.
    static let glowRadius: CGFloat = 0.05

    /// The glyph in a 100 by 100 square with y pointing down, as one path to fill.
    static func glyph() -> CGPath {
        let ping = CGPoint(x: 73, y: 27)
        let (pingRing, ringWidth): (CGFloat, CGFloat) = (12, 3.24)
        let globe = union([
            ring(radius: 36, width: 6),
            stroked(ellipse(radiusX: 15, radiusY: 36), width: 3.6),
            stroked(ellipse(radiusX: 36, radiusY: 12), width: 3.6),
        ])
        // A clear gap around the newest signal, so its ring never touches the globe.
        let gap = dot(at: ping, radius: pingRing + ringWidth / 2 + 4)
        let signals = [CGPoint(x: 28, y: 31), CGPoint(x: 70, y: 68), CGPoint(x: 32, y: 66), CGPoint(x: 58, y: 22)]
        return union(
            [
                globe.subtracting(gap, using: .winding),
                dot(at: ping, radius: 6.5),
                stroked(CGPath(ellipseIn: square(around: ping, radius: pingRing), transform: nil), width: ringWidth),
            ] + signals.map { dot(at: $0, radius: 4) }
        )
    }

    /// A colour from the palette.
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static let center = CGPoint(x: 50, y: 50)

    private static func square(around point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
    }

    private static func dot(at point: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: square(around: point, radius: radius), transform: nil)
    }

    private static func ellipse(radiusX: CGFloat, radiusY: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: center.x - radiusX, y: center.y - radiusY, width: 2 * radiusX, height: 2 * radiusY),
            transform: nil
        )
    }

    private static func ring(radius: CGFloat, width: CGFloat) -> CGPath {
        stroked(CGPath(ellipseIn: square(around: center, radius: radius), transform: nil), width: width)
    }

    private static func stroked(_ path: CGPath, width: CGFloat) -> CGPath {
        path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    /// Overlapping outlines would cancel each other where they cross, so they're merged into one shape.
    private static func union(_ paths: [CGPath]) -> CGPath {
        paths.dropFirst().reduce(paths.first ?? CGMutablePath()) { $0.union($1, using: .winding) }
    }
}
