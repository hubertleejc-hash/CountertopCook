import SwiftUI

/// The Hearth mark: a bistro-navy pot on warm cream, golden steam curling up into a soft heart,
/// one basil leaf, and a thin tricolore line underneath. No text. The app icon is this same view
/// rendered at 1024 pt (see ci/render-icon.swift), so the two never drift apart.
struct HearthLogo: View {
    /// The app icon is a full square (iOS rounds it); in the app the mark rounds its own corners.
    var rounded = true

    static let cream = Color(red: 0xFB / 255, green: 0xF3 / 255, blue: 0xE4 / 255)
    static let navy = Color(red: 0x1F / 255, green: 0x3A / 255, blue: 0x5F / 255)
    static let gold = Color(red: 0xE2 / 255, green: 0xA3 / 255, blue: 0x2B / 255)
    static let basil = Color(red: 0x3E / 255, green: 0x7C / 255, blue: 0x3A / 255)
    static let flagBlue = Color(red: 0x00 / 255, green: 0x55 / 255, blue: 0xA4 / 255)
    static let flagRed = Color(red: 0xEF / 255, green: 0x41 / 255, blue: 0x35 / 255)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Self.cream
                HearthSteam()
                    .stroke(Self.gold, style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round, lineJoin: .round))
                HearthPot().fill(Self.navy)
                HearthLeaf().fill(Self.basil)
                // Thin tricolore line: blue, white, red, with the basil leaf standing in for green.
                HStack(spacing: 0) {
                    Self.flagBlue
                    Color.white
                    Self.flagRed
                }
                .frame(width: s * 0.44, height: s * 0.026)
                .clipShape(Capsule())
                .position(x: s * 0.5, y: s * 0.865)
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: rounded ? s * 0.225 : 0, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Hearth")
        .accessibilityIdentifier("hearthLogo")
    }
}

/// A round-bottomed pot: a wide rim with two small handles, a deep bowl and a short foot.
struct HearthPot: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        // Rim.
        path.addRoundedRect(in: CGRect(origin: p(0.215, 0.515), size: CGSize(width: 0.57 * s, height: 0.058 * s)),
                            cornerSize: CGSize(width: 0.029 * s, height: 0.029 * s))
        // Handles.
        path.addRoundedRect(in: CGRect(origin: p(0.15, 0.555), size: CGSize(width: 0.10 * s, height: 0.045 * s)),
                            cornerSize: CGSize(width: 0.022 * s, height: 0.022 * s))
        path.addRoundedRect(in: CGRect(origin: p(0.75, 0.555), size: CGSize(width: 0.10 * s, height: 0.045 * s)),
                            cornerSize: CGSize(width: 0.022 * s, height: 0.022 * s))
        // Bowl.
        path.move(to: p(0.25, 0.585))
        path.addLine(to: p(0.75, 0.585))
        path.addCurve(to: p(0.60, 0.775), control1: p(0.75, 0.70), control2: p(0.69, 0.775))
        path.addLine(to: p(0.40, 0.775))
        path.addCurve(to: p(0.25, 0.585), control1: p(0.31, 0.775), control2: p(0.25, 0.70))
        path.closeSubpath()
        // Foot.
        path.addRoundedRect(in: CGRect(origin: p(0.39, 0.775), size: CGSize(width: 0.22 * s, height: 0.03 * s)),
                            cornerSize: CGSize(width: 0.012 * s, height: 0.012 * s))
        return path
    }
}

/// Two wisps of steam that rise from the pot and curl into the two halves of a heart.
struct HearthSteam: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        for side in [CGFloat(-1), 1] {
            func q(_ dx: CGFloat, _ y: CGFloat) -> CGPoint { p(0.5 + side * dx, y) }
            // From the pot, up the outside of the heart, over the lobe and down into the dip.
            path.move(to: q(0.0, 0.47))
            path.addCurve(to: q(0.175, 0.265), control1: q(0.06, 0.41), control2: q(0.175, 0.36))
            path.addCurve(to: q(0.085, 0.165), control1: q(0.175, 0.20), control2: q(0.13, 0.165))
            path.addCurve(to: q(0.0, 0.245), control1: q(0.04, 0.165), control2: q(0.0, 0.20))
        }
        return path
    }
}

/// One basil leaf resting on the rim.
struct HearthLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(0.635, 0.515))
        path.addQuadCurve(to: p(0.775, 0.405), control: p(0.66, 0.40))
        path.addQuadCurve(to: p(0.635, 0.515), control: p(0.765, 0.515))
        path.closeSubpath()
        return path
    }
}
