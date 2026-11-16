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

    private static let ingredientHeadings = ["ingredients", "ingredient", "ingredient list", "ingredients list",
                                             "what you need", "what you'll need", "what you’ll need", "you will need",
                                             "you'll need", "you’ll need", "shopping list", "ingredients needed",
                                             "食材", "食材准备", "准备食材", "所需食材", "食材清单", "用料", "材料", "材料准备",
                                             "原料", "主料", "辅料", "配料", "调料", "调味料", "酱汁", "料汁", "凉拌汁",
                                             "腌料", "蘸料", "主料准备", "配菜"]
    private static let methodHeadings = ["method", "instructions", "instruction", "directions", "steps", "preparation",
                                         "how to make it", "how to make", "how to cook", "how to cook it", "procedure",
                                         "recipe steps", "cooking steps", "cooking instructions", "cooking method",
                                         "steps to make", "to make",
                                         "做法", "步骤", "制作步骤", "做法步骤", "制作方法", "烹饪步骤", "方法", "制作过程",
                                         "操作步骤", "烹饪方法", "具体做法", "做法如下", "制作"]
    private static let otherHeadings = ["notes", "note", "tips", "tip", "nutrition", "nutrition facts", "equipment",
                                        "storage", "faq", "video", "chapters", "timestamps", "follow me", "music",
                                        "links", "subscribe", "social", "credits",
                                        "小贴士", "贴士", "小窍门", "窍门", "注意", "注意事项", "温馨提示", "提示", "小技巧",
                                        "营养", "营养成分"]

    /// Reads a recipe out of pasted text. Looks for an "Ingredients" list and a "Method" /
    /// "Instructions" / "Directions" list; without those headings it takes numbered lines as
    /// steps and lines that start with an amount as ingredients. The title is the first plain
    /// line. Servings and total time come only from lines that state them ("Serves 4",
    /// "Total time: 45 min"). Anything the text doesn't give stays empty or nil.
    public static func parse(_ text: String) -> ImportedRecipe {
        let lines = normalisedLines(text)

        var title = ""
        var servings: Int?
        var total: Int?
        var prep: Int?
        var cook: Int?
        var ingredients: [ImportedRecipe.Ingredient] = []
        var steps: [String] = []
        var sawHeading = false
        var section = Section.preamble
        var loose: [String] = []
        // The method numbers its steps, so an unnumbered line carries on the step before it
        // (a step wrapped over several lines on a card or in a photo).
        var stepsNumbered = false
        // The last ingredient was a bare Chinese word with no amount: it may really be the title
        // of the step panel that follows ("煮鸡胸肉" above "鸡胸肉冷水下锅，…").
        var lastIngredientBare = false

        func addIngredient(_ line: String) {
            let item = stripBullet(line)
            lastIngredientBare = false
            guard !item.isEmpty, !item.hasSuffix(":"), !item.hasSuffix("：") else { return }
            if ChineseRecipe.hasHan(item) {
                let items = ChineseRecipe.ingredients(in: item)
                if items.isEmpty {
                    ingredients.append(.init(amount: "", unit: "", name: item))
                    lastIngredientBare = ChineseRecipe.isShortTitle(item)
                } else {
                    ingredients += items
                }
            } else {
                ingredients.append(RecipeImporter.splitIngredient(item))
            }
        }

        func addStep(_ line: String) {
            let raw = stripBullet(line)
            let numbered = stepNumber(raw) != nil
            let step = stripNumber(raw)
            guard !step.isEmpty else { return }
            if !numbered, (step.hasSuffix(":") || step.hasSuffix("：")), step.count < 40 { return }
            if numbered {
                stepsNumbered = true
            } else if let last = steps.last {
                if ChineseRecipe.hasHan(step), !ChineseRecipe.endsSentence(last) {
                    // A panel's title, then its text: "煮鸡胸肉：鸡胸肉冷水下锅…"; a wrapped line runs on.
                    steps[steps.count - 1] = last + (ChineseRecipe.isShortTitle(last) ? "：" : "") + step
                    return
                }
                if stepsNumbered, !ChineseRecipe.hasHan(step) {
                    steps[steps.count - 1] = last + " " + step
                    return
                }
            }
            steps.append(step)
        }

        /// A recipe card often goes straight from its ingredients to numbered steps, with no
        /// "Method" heading: step 1, or a Chinese sentence with no amount in it, starts the method.
        func startsMethod(_ line: String) -> Bool {
            let raw = stripBullet(line)
            if stepNumber(raw) == 1 {
                let rest = stripNumber(raw)
                return ChineseRecipe.hasHan(rest) ? ChineseRecipe.ingredients(in: rest).isEmpty
                                                  : RecipeImporter.splitIngredient(rest).amount.isEmpty
            }
            return ChineseRecipe.hasHan(raw) && ChineseRecipe.isSentence(raw) && !ingredients.isEmpty
                && (raw.contains("。") || ChineseRecipe.ingredients(in: raw).isEmpty)
        }

        for line in lines where !line.isEmpty {
            if let heading = heading(line) {
                section = heading
                lastIngredientBare = false
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
                if startsMethod(line) {
                    section = .method
                    if lastIngredientBare, stepNumber(stripBullet(line)) == nil, let bare = ingredients.popLast() {
                        steps.append(bare.name)
                    }
                    addStep(line)
                } else {
                    addIngredient(line)
                }
            case .method:
                addStep(line)
            case .other:
                break
            }
        }

        if !sawHeading {
            // No headings: numbered lines are steps (and, in Chinese, the sentences that carry
            // them on); lines that hold an amount are ingredients.
            var inSteps = false
            for line in loose {
                let raw = stripBullet(line)
                if stepNumber(raw) != nil {
                    inSteps = true
                    addStep(line)
                } else if ChineseRecipe.hasHan(raw) {
                    let items = ChineseRecipe.isSentence(raw) ? [] : ChineseRecipe.ingredients(in: raw)
                    if !items.isEmpty {
                        ingredients += items
                    } else if inSteps {
                        addStep(line)
                    }
                } else if !RecipeImporter.splitIngredient(raw).amount.isEmpty {
                    ingredients.append(RecipeImporter.splitIngredient(raw))
                }
            }
        }

        let sum = [prep, cook].compactMap { $0 }
        return ImportedRecipe(
            title: title,
            servings: servings,
            totalMinutes: total ?? (sum.isEmpty ? nil : sum.reduce(0, +)),
            ingredients: ingredients,
            steps: steps,
            siteName: "",
            cuisine: nil)
    }

    /// Lines, trimmed, with step markers written out as "1. ": keycap emoji (1️⃣), circled
    /// numbers (①, ❶), "第1步" / "步骤1", Chinese list numbers (一、), and full-width digits.
    static func normalisedLines(_ text: String) -> [String] {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            // Video captions number their steps with keycap emoji: "1️⃣ Boil the pasta" → "1. Boil the pasta".
            .replacingOccurrences(of: "([0-9])\u{FE0F}?\u{20E3}", with: "$1. ", options: .regularExpression)
        // Full-width digits (１２３) as ASCII.
        text = String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0xFF10...0xFF19).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0xFF10 + 0x30)! : scalar
        }))
        var circled: [Character: Int] = [:]
        for (first, count) in [(0x2460, 20), (0x2474, 20), (0x2776, 10), (0x2780, 10), (0x278A, 10), (0x24F5, 10)] {
            for i in 0..<count { circled[Character(Unicode.Scalar(UInt32(first + i))!)] = i + 1 }
        }
        let chineseOrdinals = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        return text.components(separatedBy: "\n").map { raw -> String in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let first = line.first, let n = circled[first] {
                line = "\(n). " + line.dropFirst().trimmingCharacters(in: .whitespaces)
            } else if let match = line.range(of: #"^(?:第\s*(\d{1,2})\s*步|步骤\s*(\d{1,2}))\s*[:：、.]?\s*"#, options: .regularExpression) {
                let digits = line[match].filter(\.isNumber)
                line = "\(digits). " + line[match.upperBound...]
            } else if line.count > 2, let n = chineseOrdinals[String(line.prefix(1))], line.dropFirst().first == "、" {
                line = "\(n). " + line.dropFirst(2)
            }
            return line
        }
        // Hashtag and @mention lines at the end of a caption are not part of the recipe.
        .filter { !isTagLine($0) }
    }

    private static let stepNumberRegex = try? NSRegularExpression(
        pattern: #"^(?:step\s*)?(\d{1,2})\s*(?:[.)：:、]|\s+(?=\p{Han}))"#, options: .caseInsensitive)

    /// The number a step line starts with: "1. …", "2) …", "Step 3: …", "4 煮面条", "5、…".
    static func stepNumber(_ line: String) -> Int? {
        guard let stepNumberRegex,
              let match = stepNumberRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line), let whole = Range(match.range, in: line) else { return nil }
        // "2.5 cups" is an amount and "0:00 Intro" a timestamp, not a step.
        if line[whole.upperBound...].first?.isNumber == true { return nil }
        return Int(line[range])
    }

    private static func heading(_ line: String) -> Section? {
        guard line.count <= 48 else { return nil }
        // Emoji and decoration around a heading ("📝 INGREDIENTS 👇", "~ Method ~") don't matter.
        var text = Substring(line.lowercased())
        text = text.drop { !$0.isLetter }
        // "Ingredients (serves 4)", "Method:" or "Ingredients - for 2" still count.
        if let cut = text.range(of: #"\s*(?:\(|:|：|\s[-–—]\s)"#, options: .regularExpression) {
            text = text[..<cut.lowerBound]
        }
        while let last = text.last, !last.isLetter { text = text.dropLast() }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        // "Ingredients for 4 people" or "Ingredients for the sauce" is the ingredients heading too.
        if let first = words.first, words.count > 1, words[1] == "for", ingredientHeadings.contains(String(first)) {
            return .ingredients
        }
        text = Substring(words.joined(separator: " "))
        let lower = String(text)
        guard !lower.isEmpty else { return nil }
        if lower.hasPrefix("for the ") || lower.hasPrefix("the ") { return nil }
        if ingredientHeadings.contains(lower) { return .ingredients }
        if methodHeadings.contains(lower) { return .method }
        if otherHeadings.contains(lower) { return .other }
        return nil
    }

    /// A line made only of hashtags and @mentions ("#pasta #dinner @hearth").
    static func isTagLine(_ line: String) -> Bool {
        let words = line.split(whereSeparator: { $0.isWhitespace })
        return !words.isEmpty && words.allSatisfy { $0.hasPrefix("#") || $0.hasPrefix("@") }
            && words.contains { $0.count > 1 }
    }

    private static func titleCandidate(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_= \t"))
        if let range = text.range(of: #"^recipe\s*[:\-–]\s*"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        guard !text.isEmpty, text.count <= 120, !text.lowercased().hasPrefix("http") else { return nil }
        return text
    }

    /// Takes off a list bullet, a checkbox, or the emoji many captions put in front of each item
    /// ("🧄 2 cloves garlic", "✅ Boil the pasta").
    private static func stripBullet(_ line: String) -> String {
        let text = line.replacingOccurrences(of: #"^(?:[-*•▢▪◦·–—]|\[\s?\]|□)\s*"#, with: "", options: .regularExpression)
        let rest = text.drop { character in
            !(character.isLetter || character.isNumber || "([\"'“‘".contains(character))
        }
        return String(rest).trimmingCharacters(in: .whitespaces)
    }

    private static func stripNumber(_ line: String) -> String {
        guard stepNumber(line) != nil || line.lowercased().hasPrefix("step") else { return line }
        return line.replacingOccurrences(of: #"^(?:step\s*)?\d+\s*(?:[.):：、]|(?=\s+\p{Han}))\s*|^step\s*\d+\s*[-–—]?\s*"#, with: "",
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

        public init(title: String? = nil, channel: String? = nil, description: String? = nil, captionURL: URL? = nil) {
            self.title = title; self.channel = channel; self.description = description; self.captionURL = captionURL
        }
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

    /// The spoken text from YouTube's JSON captions (`fmt=json3`): one line per caption.
    public static func transcript(json3 data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return "" }
        var lines: [String] = []
        for event in events {
            let text = (event["segs"] as? [[String: Any]] ?? []).compactMap { $0["utf8"] as? String }.joined()
                .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, text != lines.last { lines.append(text) }
        }
        return lines.joined(separator: "\n")
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

// MARK: - Video and post captions

/// The caption of a video or post on a page with no recipe card: TikTok, Instagram, Facebook,
/// Pinterest, Xiaohongshu and the like. Many recipe videos write the recipe there. Only the
/// caption is read (the page's own description of the post), never comments or other text.
public enum PageCaption {
    public struct Info: Equatable {
        public var title: String?
        /// The caption, line breaks kept so its lists can be read.
        public var text: String?
        public var siteName: String?
    }

    /// `page` is the address the page came from: TikTok's and Instagram's own page data is
    /// only looked at on their own sites.
    public static func extract(html: String, page: URL? = nil) -> Info {
        var candidates: [String] = []
        let host = page?.host?.lowercased() ?? ""
        if host.contains("tiktok.") || host.contains("instagram.") {
            // The page data carries the full caption; the meta description is often cut short.
            for key in [#""desc":""#, #""caption":\{"text":""#, #""edge_media_to_caption":\{"edges":\[\{"node":\{"text":""#] {
                if let value = jsonString(after: key, in: html) { candidates.append(value) }
            }
        }
        for property in ["og:description", "twitter:description", "description"] {
            if let value = meta(property, in: html) { candidates.append(value) }
        }
        let texts = candidates.map { withoutPostPreamble(keepingLines($0)) }.filter { !$0.isEmpty }
        // The longest is the fullest copy of the caption.
        let text = texts.max { $0.count < $1.count }
        let title = (meta("og:title", in: html) ?? meta("twitter:title", in: html))
            .map(RecipeImporter.clean).flatMap { $0.isEmpty ? nil : $0 }
        let site = meta("og:site_name", in: html).map(RecipeImporter.clean).flatMap { $0.isEmpty ? nil : $0 }
        return Info(title: title, text: text, siteName: site)
    }

    /// Tags stripped and entities decoded like `RecipeImporter.clean`, but line breaks kept.
    static func keepingLines(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</p\s*>|</li\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for _ in 0..<2 where result.contains("&") { result = RecipeImporter.decodeEntities(result) }
        return result.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }).joined(separator: " ") }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Instagram's description reads `123 likes, 4 comments - cook on May 1, 2025: "the caption"`;
    /// only the caption is kept.
    static func withoutPostPreamble(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"^[\d.,KkMm]+\s+likes?,\s*[\d.,KkMm]+\s+comments?\s*[-–]\s*.{1,80}?\s+on\s+[^:\n]{3,40}:\s*["“](.*?)["”]\.?\s*$"#,
            options: [.dotMatchesLineSeparators]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text) else { return text }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A meta tag's content, either attribute order, in double or single quotes; an apostrophe
    /// inside a double-quoted caption ("Let's cook") doesn't end it.
    static func meta(_ property: String, in html: String) -> String? {
        let p = NSRegularExpression.escapedPattern(for: property)
        let name = #"\b(?:property|name)\s*=\s*["']"# + p + #"["']"#
        let content = #"\bcontent\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        for pattern in [#"<meta\b[^>]*"# + name + #"[^>]*"# + content, #"<meta\b[^>]*"# + content + #"[^>]*"# + name] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { continue }
            for group in [1, 2] {
                if let range = Range(match.range(at: group), in: html) {
                    let value = String(html[range])
                    return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
                }
            }
        }
        return nil
    }

    private static func jsonString(after prefix: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: prefix + #"((?:[^"\\]|\\.)*)""#) else { return nil }
        var best: String?
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let literal = "\"" + text[range] + "\""
            if let value = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: [.fragmentsAllowed]) as? String,
               value.count > (best?.count ?? 0) {
                best = value
            }
        }
        return best
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
