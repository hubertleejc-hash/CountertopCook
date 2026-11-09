import Foundation

public enum ConversionCategory: String, CaseIterable, Identifiable {
    case volume = "Volume"
    case weight = "Weight"
    case temperature = "Temp"

    public var id: String { rawValue }

    public var units: [CookingUnit] {
        CookingUnit.allCases.filter { $0.category == self }
    }
}

public enum CookingUnit: String, CaseIterable, Identifiable {
    case teaspoon = "tsp"
    case tablespoon = "tbsp"
    case cup = "cup"
    case fluidOunce = "fl oz"
    case milliliter = "ml"
    case liter = "L"
    case gram = "g"
    case kilogram = "kg"
    case ounce = "oz"
    case pound = "lb"
    case celsius = "°C"
    case fahrenheit = "°F"

    public var id: String { rawValue }

    public var category: ConversionCategory {
        switch self {
        case .teaspoon, .tablespoon, .cup, .fluidOunce, .milliliter, .liter: return .volume
        case .gram, .kilogram, .ounce, .pound: return .weight
        case .celsius, .fahrenheit: return .temperature
        }
    }

    /// Size in the category's base unit (ml for volume, g for weight). US customary measures.
    var baseFactor: Double {
        switch self {
        case .teaspoon: return 4.92892
        case .tablespoon: return 14.7868
        case .cup: return 236.588
        case .fluidOunce: return 29.5735
        case .milliliter: return 1
        case .liter: return 1000
        case .gram: return 1
        case .kilogram: return 1000
        case .ounce: return 28.3495
        case .pound: return 453.592
        case .celsius, .fahrenheit: return 1
        }
    }
}

public enum Converter {
    public static func convert(_ value: Double, from: CookingUnit, to: CookingUnit) -> Double? {
        guard from.category == to.category else { return nil }
        if from.category == .temperature {
            switch (from, to) {
            case (.celsius, .fahrenheit): return value * 9 / 5 + 32
            case (.fahrenheit, .celsius): return (value - 32) * 5 / 9
            default: return value
            }
        }
        return value * from.baseFactor / to.baseFactor
    }

    /// Converts typed text such as "1 1/2" or "350". Temperatures may be negative.
    public static func convert(text: String, from: CookingUnit, to: CookingUnit) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Double
        if from.category == .temperature, trimmed.hasPrefix("-"), let f = Fraction(parsing: String(trimmed.dropFirst())) {
            value = -f.doubleValue
        } else if let f = Fraction(parsing: trimmed) {
            value = f.doubleValue
        } else {
            return nil
        }
        return convert(value, from: from, to: to)
    }

    /// Up to two decimals, trailing zeros trimmed ("2.5", "236.59", "350").
    public static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
