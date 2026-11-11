import Foundation

// Importing from plain text: a pasted recipe, or a YouTube video's description. Everything here
// only reads what the text says. Nothing is filled in when the text doesn't give it.

// MARK: - Step times (auto-timers)

public enum StepTime {
    private static let pattern =
        #"(?<![\w.,/])(\d+(?:[.,]\d+)?)(?:\s*(?:-|–|—|to)\s*(\d+(?:[.,]\d+)?))?[\s-]*(hours?|hrs?|hr|minutes?|mins?|min)\b"#
    private static let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    private static let trailingMinutes = try? NSRegularExpression(
        pattern: #"^\s*(?:and\s+)?(\d+)[\s-]*(?:minutes?|mins?|min)\b"#, options: .caseInsensitive)

    /// The first time a step states, in whole minutes: "simmer for 15 minutes" → 15,
    /// "bake 1 hour 30 minutes" → 90, "rest 8-10 min" → 8 (the earlier end of a range, so the
    /// timer never runs long). Nil when the step gives no time in minutes or hours; seconds and
    /// vague wording ("a few minutes") are left alone rather than rounded or guessed.
    public static func minutes(in step: String) -> Int? {
        guard let regex,
              let match = regex.firstMatch(in: step, range: NSRange(step.startIndex..., in: step)),
              let numberRange = Range(match.range(at: 1), in: step),
              let unitRange = Range(match.range(at: 3), in: step),
              let number = Double(step[numberRange].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        let unit = step[unitRange].lowercased()
        var total = unit.hasPrefix("h") ? number * 60 : number
        if unit.hasPrefix("h"), let trailingMinutes, let whole = Range(match.range, in: step) {
            let rest = String(step[whole.upperBound...])
            if let extra = trailingMinutes.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
               let extraRange = Range(extra.range(at: 1), in: rest), let minutes = Double(rest[extraRange]) {
                total += minutes
            }
        }
        let rounded = Int(total.rounded())
        return (1...1440).contains(rounded) ? rounded : nil
    }

    /// Adds up every hours / minutes amount in a short label such as "1 hr 15 min" or "45 minutes".
    public static func duration(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d+(?:[.,]\d+)?)\s*(hours?|hrs?|hr|h|minutes?|mins?|min|m)\b"#, options: .caseInsensitive)
        else { return nil }
        var total = 0.0
        var found = false
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let numberRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
                  let number = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) else { continue }
            total += text[unitRange].lowercased().hasPrefix("h") ? number * 60 : number
            found = true
        }
        let rounded = Int(total.rounded())
        return found && rounded > 0 ? rounded : nil
    }
}

// MARK: - Pasted text

public enum TextRecipeParser {
    private enum Section { case preamble, ingredients, method, other }

    private static let ingredientHeadings = ["ingredients", "ingredient list", "what you need", "what you'll need",
                                             "what you’ll need", "you will need", "you'll need", "you’ll need",
                                             "shopping list"]
    private static let methodHeadings = ["method", "instructions", "directions", "steps", "preparation",
                                         "how to make it", "how to make", "procedure", "recipe steps"]
    private static let otherHeadings = ["notes", "note", "tips", "tip", "nutrition", "nutrition facts", "equipment",
                                        "storage", "faq", "video", "chapters", "timestamps", "follow me", "music",
                                        "links", "subscribe", "social", "credits"]

    /// Reads a recipe out of pasted text. Looks for an "Ingredients" list and a "Method" /
    /// "Instructions" / "Directions" list; without those headings it takes numbered lines as
    /// steps and lines that start with an amount as ingredients. The title is the first plain
    /// line. Servings and total time come only from lines that state them ("Serves 4",
    /// "Total time: 45 min"). Anything the text doesn't give stays empty or nil.
    public static func parse(_ text: String) -> ImportedRecipe {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var title = ""
        var servings: Int?
        var total: Int?
        var prep: Int?
        var cook: Int?
        var ingredients: [String] = []
        var steps: [String] = []
        var sawHeading = false
        var section = Section.preamble
        var loose: [String] = []

        for line in lines where !line.isEmpty {
            if let heading = heading(line) {
                section = heading
                if heading == .ingredients || heading == .method { sawHeading = true }
                continue
            }
            if section == .preamble || section == .other {
                var wasMeta = false
                for part in line.components(separatedBy: CharacterSet(charactersIn: "|•·")) {
                    let piece = part.trimmingCharacters(in: .whitespaces)
                    if let value = metaServings(piece) { servings = servings ?? value; wasMeta = true }
                    if let value = metaTime(piece, label: #"total(?:\s+time)?\s*:?\s+|ready\s+in\s*:?\s+|time\s*:\s*"#) { total = total ?? value; wasMeta = true }
                    if let value = metaTime(piece, label: #"prep(?:aration)?(?:\s+time)?\s*:\s*|prep(?:aration)?\s+time\s+"#) { prep = prep ?? value; wasMeta = true }
                    if let value = metaTime(piece, label: #"(?:cook(?:ing)?|bak(?:e|ing))(?:\s+time)?\s*:\s*|(?:cook(?:ing)?|bak(?:e|ing))\s+time\s+"#) { cook = cook ?? value; wasMeta = true }
                }
                if wasMeta { continue }
            }
            switch section {
            case .preamble:
                if title.isEmpty, let candidate = titleCandidate(line) { title = candidate } else { loose.append(line) }
            case .ingredients:
                let item = stripBullet(line)
                if !item.isEmpty, !item.hasSuffix(":") { ingredients.append(item) }
            case .method:
                let step = stripNumber(stripBullet(line))
                if !step.isEmpty, !(step.hasSuffix(":") && step.count < 40) { steps.append(step) }
            case .other:
                break
            }
        }

        if !sawHeading {
            // No headings: numbered lines are steps; lines that start with an amount are ingredients.
            for line in loose {
                if line.range(of: #"^(?:step\s*)?\d+\s*[.):]\s+\S"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    steps.append(stripNumber(line))
                } else {
                    let item = stripBullet(line)
                    if !RecipeImporter.splitIngredient(item).amount.isEmpty { ingredients.append(item) }
                }
            }
        }

        let sum = [prep, cook].compactMap { $0 }
        return ImportedRecipe(
            title: title,
            servings: servings,
            totalMinutes: total ?? (sum.isEmpty ? nil : sum.reduce(0, +)),
            ingredients: ingredients.map(RecipeImporter.splitIngredient),
            steps: steps,
            siteName: "",
            cuisine: nil)
    }

    private static func heading(_ line: String) -> Section? {
        guard line.count <= 48 else { return nil }
        var text = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#*_=-–—:•▢ \t"))
        // "Ingredients (serves 4)" or "Method:" still count.
        if let cut = text.firstIndex(where: { $0 == "(" || $0 == ":" }) { text = String(text[..<cut]) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("for the ") || text.hasPrefix("the ") { return nil }
        if ingredientHeadings.contains(text) { return .ingredients }
        if methodHeadings.contains(text) { return .method }
        if otherHeadings.contains(text) { return .other }
        return nil
    }

    private static func titleCandidate(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_= \t"))
        if let range = text.range(of: #"^recipe\s*[:\-–]\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        guard !text.isEmpty, text.count <= 120, !text.lowercased().hasPrefix("http") else { return nil }
        return text
    }

    private static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(?:[-*•▢▪◦·–—]|\[\s?\]|□)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func stripNumber(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(?:step\s*)?\d+\s*[.):]\s*|^step\s*\d+\s*[-–—]?\s*"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func metaServings(_ text: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(?:serves|servings?|yields?|makes|portions?)\s*:?\s*(?:about\s+|approx\.?\s+)?(\d+)"#,
            options: .caseInsensitive),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text), let value = Int(text[range]), value > 0
        else { return nil }
        return value
    }

    /// A labelled time such as "Total time: 45 min". `label` is a pattern for the label and its
    /// separator; a sentence that merely starts with "Cook" or "Time" is not a label.
    private static func metaTime(_ text: String, label: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "^(?:" + label + ")(.+)$", options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return StepTime.duration(in: String(text[range]))
    }
}

// MARK: - YouTube

public enum YouTubePage {
    public struct Info: Equatable {
        public var title: String?
        public var channel: String?
        public var description: String?
        /// Where the video's captions can be fetched, when the page lists a caption track.
        public var captionURL: URL?
    }

    /// The video id in a YouTube link: youtu.be/ID, youtube.com/watch?v=ID, /shorts/ID, /embed/ID, /live/ID.
    public static func videoID(from url: URL) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        let parts = url.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" {
            id = parts.first
        } else if host == "youtube.com" || host == "youtube-nocookie.com" {
            if parts.first == "watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            } else if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
                id = parts[1]
            }
        }
        guard let id, id.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    /// Reads the title, channel, description and caption-track address from a watch page's HTML.
    public static func extract(html: String) -> Info {
        var info = Info()
        info.description = jsonString(after: #""shortDescription":""#, in: html)
        info.title = jsonString(after: #""videoDetails":\{"videoId":"[^"]*","title":""#, in: html)
            ?? meta("og:title", in: html)
        info.channel = jsonString(after: #""ownerChannelName":""#, in: html) ?? jsonString(after: #""author":""#, in: html)
        if let tracks = html.range(of: #""captionTracks":\["#, options: .regularExpression) {
            let tail = String(html[tracks.upperBound...].prefix(20000))
            let english = jsonString(after: #"\{"baseUrl":""#, in: tail, requiringLater: #""languageCode":"en"#)
            if let address = english ?? jsonString(after: #"\{"baseUrl":""#, in: tail) {
                // The page gives the address relative to youtube.com.
                info.captionURL = URL(string: address.hasPrefix("/") ? "https://www.youtube.com" + address : address)
            }
        }
        return info
    }

    /// The spoken text from a captions file (YouTube's timed-text XML), as one paragraph.
    public static func transcript(xml: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<(text|p)\b[^>]*>(.*?)</\1>"#,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return "" }
        let pieces = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            Range(match.range(at: 2), in: xml).map { RecipeImporter.clean(RecipeImporter.clean(String(xml[$0]))) }
        }
        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The JSON string that starts right after `prefix` (a regular expression ending at the
    /// opening quote), decoded. With `requiringLater`, only a match whose own object also
    /// contains that text.
    private static func jsonString(after prefix: String, in text: String, requiringLater: String? = nil) -> String? {
        guard let regex = try? NSRegularExpression(pattern: prefix + #"((?:[^"\\]|\\.)*)""#) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            if let requiringLater {
                // The rest of this track's object: up to where the next track starts.
                var object = String(text[range.upperBound...].prefix(1500))
                if let next = object.range(of: "{\"baseUrl\"") { object = String(object[..<next.lowerBound]) }
                guard object.contains(requiringLater) else { continue }
            }
            let literal = "\"" + text[range] + "\""
            if let value = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: [.fragmentsAllowed]) as? String {
                return value
            }
        }
        return nil
    }

    private static func meta(_ property: String, in html: String) -> String? {
        let p = NSRegularExpression.escapedPattern(for: property)
        guard let regex = try? NSRegularExpression(
            pattern: #"<meta\b[^>]*\b(?:property|name)\s*=\s*["']"# + p + #"["'][^>]*\bcontent\s*=\s*"([^"]*)""#,
            options: .caseInsensitive),
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = RecipeImporter.clean(String(html[range]))
        return value.isEmpty ? nil : value
    }
}

// MARK: - To-buy list

public struct ShoppingLine: Equatable {
    public var amount: String
    public var unit: String
    public var name: String

    public init(amount: String, unit: String, name: String) {
        self.amount = amount; self.unit = unit; self.name = name
    }

    /// "5 tbsp butter", "garlic".
    public var text: String {
        [amount, unit, name].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public enum ShoppingMerge {
    private static let unitAliases: [String: String] = [
        "cups": "cup", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp", "teaspoon": "tsp",
        "teaspoons": "tsp", "grams": "g", "gram": "g", "kilograms": "kg", "kilogram": "kg",
        "milliliters": "ml", "millilitres": "ml", "liters": "l", "litres": "l", "liter": "l", "litre": "l",
        "ounces": "oz", "ounce": "oz", "pounds": "lb", "pound": "lb", "lbs": "lb",
        "cloves": "clove", "slices": "slice", "cans": "can", "sticks": "stick", "sprigs": "sprig",
        "bunches": "bunch", "pieces": "piece", "pinches": "pinch", "handfuls": "handful", "packages": "package",
    ]

    /// What to look for in the shop: the ingredient without its preparation notes.
    /// "garlic, smashed" → "garlic"; "ribeye steaks, 1 inch thick" → "ribeye steaks".
    public static func itemName(_ name: String) -> String {
        var text = name
        if let cut = text.firstIndex(where: { $0 == "," || $0 == "(" }) { text = String(text[..<cut]) }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func key(_ name: String) -> String { itemName(name).lowercased() }

    public static func unitKey(_ unit: String) -> String {
        let text = unit.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return unitAliases[text] ?? text
    }

    /// True when the two lines are the same item in the same unit and can be one line.
    public static func canCombine(_ a: ShoppingLine, _ b: ShoppingLine) -> Bool {
        guard key(a.name) == key(b.name), !key(a.name).isEmpty, unitKey(a.unit) == unitKey(b.unit) else { return false }
        let aAmount = a.amount.trimmingCharacters(in: .whitespaces), bAmount = b.amount.trimmingCharacters(in: .whitespaces)
        if aAmount.isEmpty && bAmount.isEmpty { return true }
        return Fraction(parsing: aAmount) != nil && Fraction(parsing: bAmount) != nil
    }

    /// The two lines as one: amounts added exactly ("2 tbsp" + "3 tbsp" = "5 tbsp").
    public static func sum(_ a: ShoppingLine, _ b: ShoppingLine) -> ShoppingLine {
        var result = ShoppingLine(amount: a.amount.trimmingCharacters(in: .whitespaces), unit: a.unit, name: itemName(a.name))
        if let x = Fraction(parsing: a.amount), let y = Fraction(parsing: b.amount) {
            result.amount = (x + y).displayString
        }
        return result
    }

    /// Merges duplicates, keeping the order items first appeared in. Items in different units
    /// (2 cloves garlic and 1 tbsp garlic) stay on separate lines: they can't be added.
    public static func combine(_ lines: [ShoppingLine]) -> [ShoppingLine] {
        var result: [ShoppingLine] = []
        for line in lines {
            let clean = ShoppingLine(amount: line.amount.trimmingCharacters(in: .whitespaces), unit: line.unit,
                                     name: itemName(line.name))
            guard !clean.name.isEmpty else { continue }
            if let index = result.firstIndex(where: { canCombine($0, clean) }) {
                result[index] = sum(result[index], clean)
            } else {
                result.append(clean)
            }
        }
        return result
    }
}
