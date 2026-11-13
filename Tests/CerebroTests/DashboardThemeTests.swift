import Testing
import UIKit
@testable import Cerebro

private func hex(_ color: UIColor, in style: UIUserInterfaceStyle = .light) -> UInt32? {
    var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
    let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
    return [red, green, blue].reduce(0) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
}

/// The RGB of a colour as it resolves with traits.
private func rgb(_ color: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
    var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
    color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue, alpha]
}

@Test @MainActor func increaseContrastUsesTheSystemSurfaces() {
    for style in [UIUserInterfaceStyle.light, .dark] {
        let increased = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: .high),
        ])
        #expect(rgb(DashboardTheme.separator, increased) == rgb(.separator, increased))
        #expect(rgb(DashboardTheme.card, increased) == rgb(.secondarySystemGroupedBackground, increased))
        #expect(rgb(DashboardTheme.background, increased) == rgb(.systemGroupedBackground, increased))
    }
    #expect(hex(DashboardTheme.card, in: .dark) == 0x170D_26)
}

@Test func theGlyphFillsItsSquareAndStaysInside() {
    let bounds = CerebroIcon.glyph().boundingBoxOfPath

    #expect(CGRect(x: 0, y: 0, width: 100, height: 100).contains(bounds))
    #expect(bounds.width > 70)
    #expect(bounds.height > 70)
}

@Test @MainActor func theButtonAndTheAccentUseTheIconsPalette() {
    #expect(hex(DashboardTheme.triggerGlyph) == CerebroIcon.Palette.glyph)
    #expect(
        DashboardTheme.triggerBackground.compactMap { hex($0) }
            == [CerebroIcon.Palette.backgroundTop, CerebroIcon.Palette.backgroundBottom])
    #expect(hex(DashboardTheme.accent, in: .dark) == CerebroIcon.Palette.glyph)
    // Deeper in light mode, so it reads on white.
    #expect(hex(DashboardTheme.accent, in: .light) == 0x7C3A_ED)
}

@Test @MainActor func methodsAndStatusesKeepTheirColours() {
    #expect(DashboardTheme.method("get") == .systemBlue)
    #expect(DashboardTheme.method("POST") == .systemGreen)
    #expect(DashboardTheme.method("DELETE") == .systemRed)
    #expect(DashboardTheme.method("OPTIONS") == DashboardTheme.neutral)
    #expect(DashboardTheme.status(.success) == .systemGreen)
    #expect(DashboardTheme.status(.failed) == DashboardTheme.failure)
    #expect(DashboardTheme.tone(.unknown) == DashboardTheme.secondaryText)
}
