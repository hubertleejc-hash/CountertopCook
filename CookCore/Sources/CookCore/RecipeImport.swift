import Foundation

/// A recipe read from a web page's schema.org Recipe JSON-LD. Only the recipe fields: no story,
/// description, reviews or images.
public struct ImportedRecipe: Equatable {
    public struct Ingredient: Equatable {
        public var amount: String
        public var unit: String
        public var name: String
        public init(amount: String, unit: String, name: String) {
            self.amount = amount; self.unit = unit; self.name = name
        }
    }

    public var title: String
    /// From recipeYield; nil when the page gives none.
    public var servings: Int?
    /// totalTime, or prepTime + cookTime; nil when the page gives none.
    public var totalMinutes: Int?
    public var ingredients: [Ingredient]
    public var steps: [String]
    /// The site's own name (og:site_name, the WebSite or publisher name), else the host name.
    public var siteName: String
}

public enum RecipeImportError: Error, Equatable, LocalizedError {
    /// The page has no schema.org Recipe JSON-LD. Nothing is guessed from the page text.
    case noRecipeData
    /// The Recipe JSON-LD is there but lacks a field Cook Mode needs.
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .noRecipeData:
            return "No recipe data found on this page. Only pages that publish a standard recipe card (schema.org Recipe) can be imported."
        case .missing(let field):
            return "The recipe on this page has no \(field), so it can't be imported."
        }
    }
}

public enum RecipeImporter {
    /// Reads the first schema.org Recipe in the page's JSON-LD blocks.
    public static func parse(html: String, url: URL?) throws -> ImportedRecipe {
        let blocks = jsonLDBlocks(in: html).compactMap(decodeJSON)
        guard let recipe = blocks.lazy.compactMap({ find(type: "Recipe", in: $0) }).first else {
            throw RecipeImportError.noRecipeData
        }
        let title = clean(recipe["name"] as? String ?? "")
        guard !title.isEmpty else { throw RecipeImportError.missing("title") }
        let ingredients = strings(recipe["recipeIngredient"] ?? recipe["ingredients"])
            .map(clean).filter { !$0.isEmpty }.map(splitIngredient)
        guard !ingredients.isEmpty else { throw RecipeImportError.missing("ingredients") }
        let steps = instructions(recipe["recipeInstructions"])
        guard !steps.isEmpty else { throw RecipeImportError.missing("steps") }

        let total = minutes(isoDuration: recipe["totalTime"] as? String)
        let parts = ["prepTime", "cookTime", "performTime"].compactMap { minutes(isoDuration: recipe[$0] as? String) }
        return ImportedRecipe(
            title: title,
            servings: servings(recipe["recipeYield"]),
            totalMinutes: total ?? (parts.isEmpty ? nil : parts.reduce(0, +)),
            ingredients: ingredients,
            steps: steps,
            siteName: siteName(html: html, blocks: blocks, recipe: recipe, url: url))
    }

    // MARK: JSON-LD

    static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script\b[^>]*\btype\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    private static func decodeJSON(_ text: String) -> Any? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("<!--") { body = String(body.dropFirst(4)) }
        if body.hasSuffix("-->") { body = String(body.dropLast(3)) }
        if let value = try? JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed]) {
            return value
        }
        // Some sites leave raw line breaks inside strings, which strict JSON rejects.
        let flattened = body.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return try? JSONSerialization.jsonObject(with: Data(flattened.utf8), options: [.fragmentsAllowed])
    }

    /// Depth-first search for an object whose @type is `type` (also inside @graph and arrays).
    static func find(type: String, in value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if isType(type, object["@type"]) { return object }
            for key in object.keys.sorted() {
                if let found = find(type: type, in: object[key]!) { return found }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let found = find(type: type, in: item) { return found }
            }
        }
        return nil
    }

    private static func isType(_ type: String, _ value: Any?) -> Bool {
        let names: [String] = (value as? String).map { [$0] } ?? (value as? [Any])?.compactMap { $0 as? String } ?? []
        return names.contains { name in
            name == type || name.hasSuffix("/" + type) || name.hasSuffix(":" + type)
        }
    }

    // MARK: Fields

    private static func strings(_ value: Any?) -> [String] {
        if let text = value as? String { return [text] }
        if let array = value as? [Any] { return array.flatMap { strings($0) } }
        return []
    }

    /// recipeInstructions: text, a list of texts, HowToStep objects, or HowToSection groups.
    static func instructions(_ value: Any?) -> [String] {
        if let text = value as? String {
            return lines(fromHTML: text)
        }
        if let array = value as? [Any] {
            return array.flatMap { instructions($0) }
        }
        if let object = value as? [String: Any] {
            if let items = object["itemListElement"] {
                return instructions(items)
            }
            if let text = object["text"] as? String {
                return lines(fromHTML: text)
            }
            if let name = object["name"] as? String {
                return lines(fromHTML: name)
            }
        }
        return []
    }

    private static func lines(fromHTML text: String) -> [String] {
        let broken = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</p\s*>|</li\s*>"#, with: "\n",
                                               options: .regularExpression)
        return broken.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
    }

    static func servings(_ value: Any?) -> Int? {
        if let number = value as? Int { return number > 0 ? number : nil }
        if let number = value as? Double { return number >= 1 ? Int(number) : nil }
        if let text = value as? String {
            guard let range = text.range(of: #"\d+"#, options: .regularExpression), let number = Int(text[range]),
                  number > 0 else { return nil }
            return number
        }
        if let array = value as? [Any] { return array.lazy.compactMap { servings($0) }.first }
        return nil
    }

    /// ISO 8601 duration ("PT1H30M", "P1DT2H") to whole minutes, rounding seconds up.
    public static func minutes(isoDuration: String?) -> Int? {
        guard let text = isoDuration?.trimmingCharacters(in: .whitespaces).uppercased(), text.hasPrefix("P"),
              let regex = try? NSRegularExpression(
                  pattern: #"^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func part(_ i: Int) -> Double {
            Range(match.range(at: i), in: text).flatMap { Double(text[$0]) } ?? 0
        }
        let total = part(1) * 1440 + part(2) * 60 + part(3) + part(4) / 60
        return text.count > 2 || total > 0 ? Int(total.rounded(.up)) : nil
    }

    private static func siteName(html: String, blocks: [Any], recipe: [String: Any], url: URL?) -> String {
        for property in ["og:site_name", "application-name"] {
            if let name = metaContent(property, in: html).map(clean), !name.isEmpty { return name }
        }
        if let site = blocks.lazy.compactMap({ find(type: "WebSite", in: $0) }).first,
           let name = (site["name"] as? String).map(clean), !name.isEmpty { return name }
        if let publisher = recipe["publisher"] as? [String: Any], isType("Organization", publisher["@type"]),
           let name = (publisher["name"] as? String).map(clean), !name.isEmpty { return name }
        var host = url?.host ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func metaContent(_ property: String, in html: String) -> String? {
        let p = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta\b[^>]*\b(?:property|name)\s*=\s*["']"# + p + #"["'][^>]*\bcontent\s*=\s*["']([^"']*)["']"#,
            #"<meta\b[^>]*\bcontent\s*=\s*["']([^"']*)["'][^>]*\b(?:property|name)\s*=\s*["']"# + p + #"["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }

    // MARK: Text

    /// Strips tags, decodes HTML entities and collapses whitespace.
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for _ in 0..<2 where result.contains("&") { result = decodeEntities(result) }
        return result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "hellip": "…", "deg": "°", "frac12": "½",
        "frac14": "¼", "frac34": "¾", "frac13": "⅓", "frac23": "⅔", "times": "×", "eacute": "é", "egrave": "è",
    ]

    private static func decodeEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);"#)
        else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let body = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let name = String(text[body])
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = namedEntities[name.lowercased()]
            }
            result += replacement ?? String(text[whole])
            last = whole.upperBound
        }
        result += text[last...]
        return result
    }

    // MARK: Ingredients

    private static let units: [String: String] = [
        "cup": "cup", "cups": "cup", "c": "cup",
        "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp", "tbs": "tbsp", "tbl": "tbsp",
        "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp",
        "g": "g", "gram": "g", "grams": "g", "gr": "g", "kg": "kg", "kilogram": "kg", "kilograms": "kg",
        "mg": "mg", "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l", "dl": "dl", "cl": "cl",
        "oz": "oz", "ounce": "oz", "ounces": "oz", "fl oz": "fl oz",
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "pint": "pint", "pints": "pint", "quart": "quart", "quarts": "quart", "qt": "quart",
        "clove": "clove", "cloves": "cloves", "slice": "slice", "slices": "slices",
        "can": "can", "cans": "cans", "stick": "stick", "sticks": "sticks",
        "pinch": "pinch", "pinches": "pinches", "dash": "dash", "dashes": "dashes",
        "sprig": "sprig", "sprigs": "sprigs", "bunch": "bunch", "bunches": "bunches",
        "package": "package", "packages": "packages", "pkg": "package", "piece": "piece", "pieces": "pieces",
        "handful": "handful", "handfuls": "handfuls",
    ]

    /// "1 1/2 cups flour" → ("1 1/2", "cup", "flour"); "salt, to taste" → ("", "", "salt, to taste").
    public static func splitIngredient(_ line: String) -> ImportedRecipe.Ingredient {
        var tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var amount = ""
        // "200g" written as one word.
        if let first = tokens.first,
           let match = first.range(of: #"^\d+(?:[.,]\d+)?(?=[a-zA-Z]+$)"#, options: .regularExpression),
           units[first[match.upperBound...].lowercased()] != nil {
            amount = String(first[match])
            tokens[0] = String(first[match.upperBound...])
        } else if tokens.count >= 2, Fraction(parsing: tokens[0] + " " + tokens[1]) != nil, tokens[1].contains("/") {
            amount = tokens[0] + " " + tokens[1]
            tokens.removeFirst(2)
        } else if let first = tokens.first,
                  Fraction(parsing: first) != nil || first.range(of: #"^\d+(?:[.,]\d+)?[-–]\d+(?:[.,]\d+)?$"#, options: .regularExpression) != nil {
            amount = first
            tokens.removeFirst()
        }
        var unit = ""
        if !amount.isEmpty, let next = tokens.first {
            let word = next.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if tokens.count >= 2, word == "fl", tokens[1].lowercased().hasPrefix("oz") {
                unit = "fl oz"; tokens.removeFirst(2)
            } else if let known = units[word] {
                unit = known; tokens.removeFirst()
            }
        }
        if !unit.isEmpty, tokens.first?.lowercased() == "of" { tokens.removeFirst() }
        let name = tokens.joined(separator: " ")
        return name.isEmpty && !amount.isEmpty && unit.isEmpty
            ? ImportedRecipe.Ingredient(amount: "", unit: "", name: line)
            : ImportedRecipe.Ingredient(amount: amount, unit: unit, name: name)
    }
}
