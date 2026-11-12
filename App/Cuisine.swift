import SwiftUI

/// A light French or Italian accent on a recipe, visual only: a tricolore strip, an accent
/// colour (bistro navy or basil green) and a small motif (Eiffel Tower or basil leaf). There are
/// no French or Italian words anywhere in the app; all text is English.
enum Cuisine: String, CaseIterable {
    case french, italian

    /// For VoiceOver only; the accent itself has no words.
    var name: String {
        switch self {
        case .french: return "French"
        case .italian: return "Italian"
        }
    }

    /// Bistro navy / basil green; softer at night, so the motif doesn't glare on espresso.
    var accent: Color {
        switch self {
        case .french: return Color(light: 0x1F3A5F, dark: 0x8FA6C4)
        case .italian: return Color(light: 0x3E7C3A, dark: 0x86A97E)
        }
    }

    /// Flag colours, left to right. Muted at night: the same flag, turned down.
    var tricolore: [Color] {
        switch self {
        case .french: return [Color(light: 0x0055A4, dark: 0x5D7BA0), Color(light: 0xFFFFFF, dark: 0xD9CDBE),
                              Color(light: 0xEF4135, dark: 0xB4685D)]
        case .italian: return [Color(light: 0x009246, dark: 0x5E8F68), Color(light: 0xFFFFFF, dark: 0xD9CDBE),
                               Color(light: 0xCE2B37, dark: 0xAE5D61)]
        }
    }

    static func from(tag: String?) -> Cuisine? {
        guard let tag = tag?.lowercased() else { return nil }
        if tag.contains("french") { return .french }
        if tag.contains("italian") { return .italian }
        return Cuisine(rawValue: tag)
    }
}

/// Three flag colours in a short rounded bar.
struct TricoloreStrip: View {
    let cuisine: Cuisine
    var width: CGFloat = 28
    var height: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cuisine.tricolore.enumerated()), id: \.offset) { _, color in
                color
            }
        }
        .frame(width: width, height: height)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The accent in one line: a tricolore strip and the motif. No words.
struct CuisineBadge: View {
    let cuisine: Cuisine
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            TricoloreStrip(cuisine: cuisine, width: size * 2.6, height: size * 0.32)
            CuisineMotif(cuisine: cuisine, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cuisine.name)
        .accessibilityIdentifier("cuisineBadge")
    }
}

/// Eiffel outline for French, a basil leaf for Italian.
struct CuisineMotif: View {
    let cuisine: Cuisine
    var size: CGFloat = 13

    var body: some View {
        switch cuisine {
        case .french:
            EiffelShape()
                .stroke(cuisine.accent, style: StrokeStyle(lineWidth: max(1, size / 12), lineJoin: .round))
                .frame(width: size * 0.75, height: size)
        case .italian:
            Image(systemName: "leaf.fill")
                .font(.system(size: size))
                .foregroundStyle(cuisine.accent)
        }
    }
}

/// A small Eiffel tower: two legs, two decks and a spire.
struct EiffelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        // Left leg, spire, right leg.
        p.move(to: CGPoint(x: x, y: y + h))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.44, y: y), control: CGPoint(x: x + w * 0.42, y: y + h * 0.45))
        p.addLine(to: CGPoint(x: x + w * 0.56, y: y))
        p.addQuadCurve(to: CGPoint(x: x + w, y: y + h), control: CGPoint(x: x + w * 0.58, y: y + h * 0.45))
        // Lower deck and upper deck.
        p.move(to: CGPoint(x: x + w * 0.12, y: y + h * 0.62))
        p.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.62))
        p.move(to: CGPoint(x: x + w * 0.3, y: y + h * 0.34))
        p.addLine(to: CGPoint(x: x + w * 0.7, y: y + h * 0.34))
        // Arch under the lower deck.
        p.move(to: CGPoint(x: x + w * 0.22, y: y + h))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.78, y: y + h), control: CGPoint(x: x + w * 0.5, y: y + h * 0.66))
        return p
    }
}
