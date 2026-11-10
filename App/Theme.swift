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

    static let cardRadius: CGFloat = 24

    /// Recipe title: New York Bold.
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    /// Current step: large SF Pro, readable from across the counter.
    static func step(compact: Bool) -> Font { .system(size: compact ? 26 : 38, weight: .regular) }
    /// Timer numbers: SF Pro Rounded with tabular figures.
    static func timer(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }
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
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        Text(text.uppercased())
            .tracking(2)
            .font(font)
            .foregroundStyle(color)
    }
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
