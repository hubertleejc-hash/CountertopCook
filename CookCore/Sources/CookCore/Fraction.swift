import Foundation

/// An exact, always-reduced fraction used for ingredient amounts ("1 1/2", "3/4", "200").
public struct Fraction: Equatable, Hashable, Comparable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator != 0, "Fraction denominator cannot be zero")
        var n = numerator
        var d = denominator
        if d < 0 { n = -n; d = -d }
        let g = Fraction.gcd(abs(n), d)
        self.numerator = n / g
        self.denominator = d / g
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? max(a, 1) : gcd(b, a % b)
    }

    public var doubleValue: Double { Double(numerator) / Double(denominator) }

    public static func * (lhs: Fraction, rhs: Fraction) -> Fraction {
        // Cross-reduce first to keep the intermediate products small.
        let g1 = gcd(abs(lhs.numerator), rhs.denominator)
        let g2 = gcd(abs(rhs.numerator), lhs.denominator)
        return Fraction((lhs.numerator / g1) * (rhs.numerator / g2),
                        (lhs.denominator / g2) * (rhs.denominator / g1))
    }

    public static func + (lhs: Fraction, rhs: Fraction) -> Fraction {
        Fraction(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
                 lhs.denominator * rhs.denominator)
    }

    public static func < (lhs: Fraction, rhs: Fraction) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    public var description: String { displayString }

    // MARK: Parsing

    private static let unicodeFractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
        "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6",
        "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
    ]

    /// Parses "2", "1/2", "1 1/2", "1½", "0.75" or "0,75". Returns nil for text like "pinch".
    public init?(parsing text: String) {
        var expanded = ""
        for ch in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let replacement = Fraction.unicodeFractions[ch] {
                expanded += " \(replacement)"
            } else if ch == "," {
                expanded += "."
            } else {
                expanded.append(ch)
            }
        }
        let tokens = expanded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        switch tokens.count {
        case 1:
            guard let f = Fraction.parseToken(tokens[0]) else { return nil }
            self = f
        case 2:
            guard let whole = Int(tokens[0]), whole >= 0,
                  tokens[1].contains("/"),
                  let part = Fraction.parseToken(tokens[1]) else { return nil }
            self = Fraction(whole) + part
        default:
            return nil
        }
    }

    private static func parseToken(_ token: String) -> Fraction? {
        if token.contains("/") {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]), d > 0, n >= 0 else { return nil }
            return Fraction(n, d)
        }
        if token.contains(".") {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].count <= 6, parts[1].allSatisfy(\.isNumber) else { return nil }
            let whole = parts[0].isEmpty ? 0 : Int(parts[0])
            guard let whole, whole >= 0 else { return nil }
            if parts[1].isEmpty { return Fraction(whole) }
            guard let frac = Int(parts[1]) else { return nil }
            var scale = 1
            for _ in 0..<parts[1].count { scale *= 10 }
            return Fraction(whole * scale + frac, scale)
        }
        guard let n = Int(token), n >= 0 else { return nil }
        return Fraction(n)
    }

    // MARK: Display

    /// Kitchen-friendly text: whole numbers, mixed numbers with halves/thirds/quarters/eighths,
    /// and awkward fractions rounded to the nearest eighth (or whole number above 10).
    public var displayString: String {
        if denominator == 1 { return "\(numerator)" }
        var f = self
        if ![2, 3, 4, 8].contains(denominator) {
            let value = doubleValue
            if value >= 10 { return "\(Int(value.rounded()))" }
            let eighths = Int((value * 8).rounded())
            if eighths == 0 { return String(format: "%.2f", value) }
            f = Fraction(eighths, 8)
            if f.denominator == 1 { return "\(f.numerator)" }
        }
        let whole = f.numerator / f.denominator
        let remainder = f.numerator % f.denominator
        return whole == 0 ? "\(remainder)/\(f.denominator)" : "\(whole) \(remainder)/\(f.denominator)"
    }
}

public enum Scaler {
    /// Rescales a free-text amount from one serving count to another.
    /// Text that isn't a number ("pinch", "to taste") is returned unchanged.
    public static func scale(_ amountText: String, from baseServings: Int, to servings: Int) -> String {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseServings > 0, servings > 0, let amount = Fraction(parsing: trimmed) else { return trimmed }
        if baseServings == servings { return amount.displayString }
        return (amount * Fraction(servings, baseServings)).displayString
    }
}
