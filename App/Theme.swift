import SwiftUI
import UIKit

/// Hearth's warm palette and type, from reference-design.png and the Evening Hearth design.
/// Every colour has a daytime value (dark-brown ink on cream) and an Evening Hearth value
/// (warm cream on espresso brown, never pure black or cold grey). Which one shows follows the
/// phone, or the Light / Dark / System switch in the library (`Appearance`).
enum Theme {
    /// The one page colour behind everything, across both halves and the hinge.
    static let backgroundUI = UIColor(light: 0xFDF6E9, dark: 0x1C1712)
    static let background = Color(backgroundUI)
    /// Unfolded Duo, open flat: the recipe half is paler, the timers half warmer. Daytime values
    /// sampled from reference-design.png (Display P3 converted to sRGB). They meet at the
    /// hinge's centre line with no line between them.
    static let recipeSideUI = UIColor(light: 0xFAF8F3, dark: 0x211B15)
    static let timersSideUI = UIColor(light: 0xF4EFE4, dark: 0x2A2118)
    /// Cards: library controls, timers, convert, the pages of a recipe's book.
    static let card = Color(light: 0xFFFFFF, dark: 0x2E2720)
    static let paper = Color(light: 0xFFFDF8, dark: 0x2E2720)
    /// Soft fills: unselected chips, Back, the progress track.
    static let beige = Color(light: 0xEFE7D6, dark: 0x3D332A)
    /// Main text: dark brown by day, warm cream at night.
    static let inkUI = UIColor(light: 0x221C15, dark: 0xF5EDE3)
    static let ink = Color(inkUI)
    /// Secondary text only (counts, captions); never the step or ingredients.
    static let muted = Color(light: 0x78716C, dark: 0xC9BBA8)
    /// Next step, progress bar, step timer: burnt orange, brighter at night.
    static let accent = Color(light: 0xD96A2B, dark: 0xF08A3C)
    /// Text and icons on an `accent` fill.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x1C1712)
    /// Small section labels: COOK MODE, TIMERS.
    static let label = Color(light: 0xB45309, dark: 0xE39A55)
    /// Selected chips and timer preset pills, and the text on them.
    static let pill = Color(light: 0x1C1917, dark: 0xF5EDE3)
    static let onPill = Color(light: 0xFFFFFF, dark: 0x1C1712)
    /// Secondary actions and links: bistro navy by day, a soft blue that reads on espresso at night.
    /// (Primary buttons are `accent`, burnt orange.)
    static let navy = Color(light: 0x1F3A5F, dark: 0xA9BEDB)
    /// Lines between rows.
    static let line = Color(light: 0xE8DFCE, dark: 0x3D332A)

    static let cardRadius: CGFloat = 24

    /// Recipe titles only: Lora Bold.
    static func title(_ size: CGFloat) -> Font { .custom("Lora-Bold", fixedSize: size) }
    /// Everything else: Lato. Fixed sizes in Cook Mode, where the layout is measured to the point.
    static func text(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Lato-Bold" : "Lato-Regular", fixedSize: size)
    }
    /// Lato that follows the reader's text size, for the library, forms and lists.
    static func body(_ size: CGFloat = 17, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "Lato-Bold" : "Lato-Regular", size: size, relativeTo: style)
    }
    /// Current step: large Lato, readable from across the counter.
    static func step(compact: Bool) -> Font { text(compact ? 26 : 38) }
    /// Extra space between the lines of the step, so a long step doesn't read as a block.
    static func stepLineSpacing(compact: Bool) -> CGFloat { compact ? 3 : 4 }
    /// Timer numbers and amounts: Lato Bold with lining, fixed-width figures, so 1, 7 and 0 are
    /// full height and a countdown doesn't jiggle as it ticks.
    static func timer(_ size: CGFloat) -> Font { text(size, bold: true).monospacedDigit() }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
    /// A colour with a daytime and an Evening Hearth value.
    init(light: UInt32, dark: UInt32) { self.init(UIColor(light: light, dark: dark)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Resolves to `light` or `dark` from the trait collection of whatever draws it, so UIKit
    /// views and SwiftUI views follow the same switch.
    convenience init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) }
        #else
        self.init(hex: light)
        #endif
    }
}

/// A small, letter-spaced uppercase label: COOK MODE, TIMERS, QUICK TIMER, INGREDIENTS.
struct SectionLabel: View {
    let text: String
    var color = Theme.label
    var font: Font = Theme.text(14, bold: true)

    var body: some View {
        Text(text.uppercased())
            .tracking(2)
            .font(font)
            .foregroundStyle(color)
    }
}

/// The app's look outside Cook Mode: warm cream behind lists and forms, white rows, burnt
/// orange for primary buttons and the accent colour, bistro navy for links. No system blue.
struct WarmListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .tint(Theme.accent)
    }
}

/// Rows of a warm list or form: a card colour by day and by night, never the system's grey.
struct WarmRows: ViewModifier {
    func body(content: Content) -> some View {
        content.listRowBackground(Theme.card)
    }
}

extension View {
    func warmList() -> some View { modifier(WarmListStyle()) }
    /// On each Section of a warm list: its rows on `Theme.card`.
    func warmRows() -> some View { modifier(WarmRows()) }
}

/// A filled button in a capsule or circle. Disabled, it fades to beige with muted text.
struct SoftButtonStyle: ButtonStyle {
    var fill = Theme.beige
    var foreground = Theme.ink
    var circle = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = circle ? AnyShape(Circle()) : AnyShape(Capsule())
        configuration.label
            .foregroundStyle(isEnabled ? foreground : Theme.muted)
            .background { shape.fill(isEnabled ? fill : Theme.beige.opacity(0.6)) }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
