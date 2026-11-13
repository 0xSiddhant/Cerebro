import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Every colour the dashboard uses, in one place, so the whole of it changes together. The brand colours
/// come from `CerebroIcon`, so the icon, the floating button and the screens always agree. Surfaces are
/// Ultraviolet in dark mode and a soft lavender in light mode, and text uses the system's own colours,
/// which read on both.
enum DashboardTheme {
    // MARK: - Brand

    /// The Ultraviolet accent, for buttons, tabs, selection and progress. It's deeper in light mode, so it
    /// reads on white, and the glyph's own violet in dark mode.
    static let accent = dynamic(light: 0x7C3A_ED, dark: CerebroIcon.Palette.glyph)

    /// The accent as a solid fill behind white text, such as a sent frame or a swipe action. It stays deep
    /// in dark mode too, because white text on the light violet wouldn't read.
    static let accentFill = dynamic(light: 0x7C3A_ED, dark: 0x6D28_D9)

    /// The floating button's background, from top left to bottom right.
    static let triggerBackground = [CerebroIcon.Palette.backgroundTop, CerebroIcon.Palette.backgroundBottom]
        .map { UIColor(cgColor: CerebroIcon.color($0)) }

    /// The floating button's glyph and its glow.
    static let triggerGlyph = UIColor(cgColor: CerebroIcon.color(CerebroIcon.Palette.glyph))

    /// The floating button's rim, which keeps it visible over a dark app.
    static let triggerRim = UIColor(
        cgColor: CerebroIcon.color(CerebroIcon.Palette.glyph, alpha: CerebroIcon.rimOpacity))

    /// The count of new requests on the floating button.
    static let badge = UIColor.systemRed

    // MARK: - Surfaces

    /// The page behind everything, and the bars above it, so a screen reads as one surface.
    static let background = dynamic(light: 0xF5F1_FC, dark: 0x0B06_14)

    /// A card on the page, such as a list's row or a frame the other side sent.
    static let card = dynamic(light: 0xFFFF_FF, dark: 0x170D_26)

    /// Something that floats above the page, such as a toast.
    static let raised = dynamic(light: 0xEDE6_F8, dark: 0x2416_40)

    /// A search field or another place to type.
    static let field = dynamic(light: 0xECE5_F8, dark: 0x1F12_33)

    /// The lines between rows and under bars.
    static let separator = dynamic(light: 0xE1D7_F1, dark: 0x2C1D_47)

    /// The empty part of a bar.
    static let track = dynamic(light: 0xE4DB_F3, dark: 0x2C1D_47)

    // MARK: - Text

    /// Text that leads, such as a value.
    static let primaryText = UIColor.label

    /// Text that explains, such as a row's detail or a field's name.
    static let secondaryText = UIColor.secondaryLabel

    /// Marks that stay out of the way, such as a fold arrow.
    static let tertiaryText = UIColor.tertiaryLabel

    /// Text on a solid fill, such as a status badge or a sent frame.
    static let onFill = UIColor.white

    /// What floats over the app casts this shadow.
    static let shadow = UIColor.black

    // MARK: - Meaning

    /// Neither good nor bad, such as a cancelled request or an action that only shows something.
    static let neutral = UIColor.systemGray

    /// Something that went wrong.
    static let failure = UIColor.systemRed

    /// Something worth a second look.
    static let warning = UIColor.systemOrange

    /// Something still happening, such as an open event stream.
    static let live = UIColor.systemTeal

    /// A status badge's colour, the same on every screen.
    static func status(_ outcome: TransactionOutcome) -> UIColor {
        switch outcome {
        case .success: return .systemGreen
        case .redirection: return .systemBlue
        case .clientError: return warning
        case .serverError, .failed: return failure
        case .cancelled: return neutral
        }
    }

    /// The colour a method is known by, so a list can be scanned for one. Anything else is neutral.
    static func method(_ method: String) -> UIColor {
        switch method.uppercased() {
        case "GET": return .systemBlue
        case "POST": return .systemGreen
        case "PUT": return .systemOrange
        case "PATCH": return .systemPurple
        case "DELETE": return .systemRed
        default: return neutral
        }
    }

    /// How the System Info card colours the network's state.
    static func tone(_ tone: SystemInfoSummary.Tone) -> UIColor {
        switch tone {
        case .good: return .systemGreen
        case .warning: return warning
        case .bad: return failure
        case .unknown: return secondaryText
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        let (light, dark) = (UIColor(cgColor: CerebroIcon.color(light)), UIColor(cgColor: CerebroIcon.color(dark)))
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}
