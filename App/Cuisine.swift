import SwiftUI

/// A light French or Italian accent on a recipe: a tricolore strip, a café / trattoria serif for
/// its headings, an accent colour, a label and a small motif. English stays the app's language;
/// these only decorate recipes tagged with a cuisine.
enum Cuisine: String, CaseIterable {
    case french, italian

    /// "Recette française" / "Ricetta italiana".
    var label: String {
        switch self {
        case .french: return "Recette française"
        case .italian: return "Ricetta italiana"
        }
    }

    /// Bistro navy / basil green.
    var accent: Color {
        switch self {
        case .french: return Color(hex: 0x1F3A5F)
        case .italian: return Color(hex: 0x3E7C3A)
        }
    }

    /// Flag colours, left to right.
    var tricolore: [Color] {
        switch self {
        case .french: return [Color(hex: 0x0055A4), .white, Color(hex: 0xEF4135)]
        case .italian: return [Color(hex: 0x009246), .white, Color(hex: 0xCE2B37)]
        }
    }

    /// Headings: an elegant high-contrast café serif for French (Didot, in place of Playfair
    /// Display, which iOS doesn't ship) and a warmer serif for Italian (Georgia, in place of Lora).
    func heading(_ size: CGFloat) -> Font {
        switch self {
        case .french: return .custom("Didot-Bold", size: size)
        case .italian: return .custom("Georgia-Bold", size: size)
        }
    }

    func text(_ size: CGFloat) -> Font {
        switch self {
        case .french: return .custom("Didot", size: size)
        case .italian: return .custom("Georgia", size: size)
        }
    }

    static func from(tag: String?) -> Cuisine? {
        guard let tag = tag?.lowercased() else { return nil }
        if tag.contains("french") || tag.contains("français") || tag.contains("francais") { return .french }
        if tag.contains("italian") || tag.contains("italia") { return .italian }
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

/// Strip, label and motif in one line: "▬ Recette française 🗼".
struct CuisineBadge: View {
    let cuisine: Cuisine
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            TricoloreStrip(cuisine: cuisine, width: size * 2.2, height: size * 0.3)
            Text(cuisine.label)
                .font(cuisine.text(size))
                .foregroundStyle(cuisine.accent)
                .lineLimit(1)
                .fixedSize()
            CuisineMotif(cuisine: cuisine, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cuisine.label)
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
