import SwiftUI
import UIKit

/// Cook Mode's warm palette and type, from reference-design.png. Fixed colours (no dark
/// variants): Cook Mode always shows dark-brown ink on cream, so it reads the same in any light.
enum Theme {
    /// The one page colour behind everything, across both halves and the hinge.
    static let backgroundUI = UIColor(hex: 0xFDF6E9)
    static let background = Color(backgroundUI)
    /// Unfolded Duo, open flat: the recipe half is paler, the timers half warmer, sampled from
    /// reference-design.png (Display P3 converted to sRGB). They meet at the hinge's centre line.
    static let recipeSideUI = UIColor(hex: 0xFAF8F3)
    static let timersSideUI = UIColor(hex: 0xF4EFE4)
    static let card = Color(hex: 0xFFFFFF)
    static let beige = Color(hex: 0xEFE7D6)
    /// Main text: dark brown.
    static let ink = Color(hex: 0x221C15)
    /// Secondary text only (counts, captions); never the step or ingredients.
    static let muted = Color(hex: 0x78716C)
    /// Next step, progress bar, step timer.
    static let accent = Color(hex: 0xD96A2B)
    /// Small section labels: COOK MODE, TIMERS.
    static let label = Color(hex: 0xB45309)
    /// Timer preset pills.
    static let pill = Color(hex: 0x1C1917)
    /// Secondary actions and links: bistro navy. (Primary buttons are `accent`, burnt orange.)
    static let navy = Color(hex: 0x1F3A5F)

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
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
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

extension View {
    func warmList() -> some View { modifier(WarmListStyle()) }
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
