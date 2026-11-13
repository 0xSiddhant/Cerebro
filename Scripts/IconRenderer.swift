import AppKit
import CoreGraphics

/// Renders Cerebro's icon from `CerebroIcon`, the code the floating button draws with, so every copy
/// matches. `render-icon.sh` builds and runs it.
@main
enum IconRenderer {
    /// Sizes for documents and the web, with rounded corners. Larger ones come from `icon.svg`, because
    /// SPM downloads the repository's whole history and a large glow barely compresses.
    static let iconSizes = [16, 32, 64, 128, 256]

    /// The pixel sizes an iOS app icon comes in, square, because iOS rounds the corners itself. The
    /// 1024 one for the App Store is the Example's `AppIcon.png`, so it isn't kept twice.
    static let appIconSizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180]

    /// The space around the glyph, as a share of the icon's width.
    static let glyphInset: CGFloat = 0.17

    /// The corner radius of the rounded icon, as a share of its width.
    static let cornerRadius: CGFloat = 0.2237

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            print("usage: render-icon <brand folder> <app icon set folder>")
            exit(1)
        }
        let brand = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let appIconSet = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let manager = FileManager.default
        // Not "icon": a common global gitignore entry for macOS's hidden Icon files matches it.
        for folder in [brand.appendingPathComponent("rounded"), brand.appendingPathComponent("app-icon"), appIconSet] {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for size in iconSizes {
            try write(icon(size: size, rounded: true), to: brand.appendingPathComponent("rounded/icon-\(size).png"))
        }
        for size in appIconSizes {
            try write(icon(size: size, rounded: false), to: brand.appendingPathComponent("app-icon/app-icon-\(size).png"))
        }
        try write(icon(size: 1024, rounded: false), to: appIconSet.appendingPathComponent("AppIcon.png"))
        try write(socialPreview(), to: brand.appendingPathComponent("social-preview.jpg"), as: "public.jpeg")
        try iconSVG().write(to: brand.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)
        try glyphSVG().write(to: brand.appendingPathComponent("glyph.svg"), atomically: true, encoding: .utf8)
        print("Rendered Cerebro's icon into \(brand.path) and \(appIconSet.path)")
    }

    // MARK: - PNG

    /// A square canvas with y pointing down. An app icon has no transparency, which the App Store requires.
    static func canvas(width: Int, height: Int, opaque: Bool) -> CGContext? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
        )
        context?.translateBy(x: 0, y: CGFloat(height))
        context?.scaleBy(x: 1, y: -1)
        return context
    }

    static func icon(size: Int, rounded: Bool) -> CGImage? {
        let side = CGFloat(size)
        guard let context = canvas(width: size, height: size, opaque: !rounded) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let shape = rounded
            ? CGPath(roundedRect: bounds, cornerWidth: side * cornerRadius, cornerHeight: side * cornerRadius, transform: nil)
            : CGPath(rect: bounds, transform: nil)
        context.addPath(shape)
        context.clip()
        drawBackground(in: context, rect: bounds)
        drawGlyph(in: context, rect: bounds.insetBy(dx: side * glyphInset, dy: side * glyphInset), glow: side)
        return context.makeImage()
    }

    static func drawBackground(in context: CGContext, rect: CGRect) {
        let colors = [CerebroIcon.Palette.backgroundTop, CerebroIcon.Palette.backgroundBottom].map { CerebroIcon.color($0) }
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) else { return }
        context.drawLinearGradient(
            gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    }

    /// `glow` is the width the glow is measured against: the whole icon, not just the glyph.
    static func drawGlyph(in context: CGContext, rect: CGRect, glow: CGFloat) {
        let color = CerebroIcon.color(CerebroIcon.Palette.glyph)
        context.saveGState()
        context.setShadow(offset: .zero, blur: glow * CerebroIcon.glowRadius, color: color.copy(alpha: 0.85))
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 100, y: rect.height / 100)
        context.addPath(CerebroIcon.glyph())
        context.setFillColor(color)
        context.fillPath()
        context.restoreGState()
    }

    /// The image GitHub shows when the repository is linked, at the 1280 by 640 it asks for.
    static func socialPreview() -> CGImage? {
        let (width, height) = (1280, 640)
        guard let context = canvas(width: width, height: height, opaque: true) else { return nil }
        drawBackground(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height))
        let iconRect = CGRect(x: 120, y: 150, width: 340, height: 340)
        context.saveGState()
        context.addPath(CGPath(roundedRect: iconRect, cornerWidth: 340 * cornerRadius, cornerHeight: 340 * cornerRadius, transform: nil))
        context.setStrokeColor(CerebroIcon.color(CerebroIcon.Palette.glyph, alpha: CerebroIcon.rimOpacity))
        context.setLineWidth(3)
        context.strokePath()
        context.restoreGState()
        drawGlyph(in: context, rect: iconRect.insetBy(dx: 340 * glyphInset, dy: 340 * glyphInset), glow: 340)
        let glyph = NSColor(cgColor: CerebroIcon.color(CerebroIcon.Palette.glyph)) ?? .white
        draw("Cerebro", in: context, at: CGPoint(x: 540, y: 205), size: 112, weight: .bold, color: .white)
        draw("A network inspector inside your iOS app", in: context, at: CGPoint(x: 545, y: 345), size: 34, weight: .medium, color: glyph)
        draw(
            "HTTP · WebSockets · Server-Sent Events · Protobuf · Files", in: context, at: CGPoint(x: 545, y: 405),
            size: 24, weight: .regular, color: NSColor.white.withAlphaComponent(0.7))
        return context.makeImage()
    }

    /// Draws a line of text with its top left at `point`, in the canvas's y-down space.
    static func draw(_ text: String, in context: CGContext, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]
        let line = NSAttributedString(string: text, attributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        context.saveGState()
        context.translateBy(x: point.x, y: point.y + line.size().height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        line.draw(at: .zero)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A JPEG is for the social preview, which has no transparency and is far smaller that way.
    static func write(_ image: CGImage?, to url: URL, as type: String = "public.png") throws {
        guard let image, let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, image, type == "public.jpeg" ? options : nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: - SVG

    static func hex(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }

    /// The glyph as SVG path data, in its 100 by 100 square.
    static func pathData() -> String {
        var commands: [String] = []
        func point(_ p: CGPoint) -> String {
            String(format: "%.2f %.2f", p.x, p.y)
        }
        CerebroIcon.glyph().applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: commands.append("M" + point(points[0]))
            case .addLineToPoint: commands.append("L" + point(points[0]))
            case .addQuadCurveToPoint: commands.append("Q" + point(points[0]) + " " + point(points[1]))
            case .addCurveToPoint:
                commands.append("C" + point(points[0]) + " " + point(points[1]) + " " + point(points[2]))
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined()
    }

    /// The rounded icon, sharp at any size, for the README.
    static func iconSVG() -> String {
        let inset = 1024 * glyphInset
        let scale = (1024 - 2 * inset) / 100
        let radius = 1024 * cornerRadius
        // CoreGraphics blurs a shadow by about twice the standard deviation SVG takes.
        let deviation = 1024 * CerebroIcon.glowRadius / 2
        let palette = CerebroIcon.Palette.self
        return """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
              <title>Cerebro</title>
              <defs>
                <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0" stop-color="\(hex(palette.backgroundTop))"/>
                  <stop offset="1" stop-color="\(hex(palette.backgroundBottom))"/>
                </linearGradient>
                <clipPath id="shape"><rect width="1024" height="1024" rx="\(radius)"/></clipPath>
                <filter id="glow" x="-25%" y="-25%" width="150%" height="150%">
                  <feGaussianBlur in="SourceGraphic" stdDeviation="\(deviation)" result="blur"/>
                  <feComponentTransfer in="blur" result="soft"><feFuncA type="linear" slope="0.85"/></feComponentTransfer>
                  <feMerge><feMergeNode in="soft"/><feMergeNode in="SourceGraphic"/></feMerge>
                </filter>
              </defs>
              <g clip-path="url(#shape)">
                <rect width="1024" height="1024" fill="url(#background)"/>
                <g filter="url(#glow)">
                  <path transform="translate(\(inset) \(inset)) scale(\(scale))" fill="\(hex(palette.glyph))" d="\(pathData())"/>
                </g>
              </g>
            </svg>

            """
    }

    /// The glyph alone, in the brand violet, for places that bring their own background.
    static func glyphSVG() -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
          <title>Cerebro</title>
          <path fill="\(hex(CerebroIcon.Palette.glyph))" d="\(pathData())"/>
        </svg>

        """
    }
}
