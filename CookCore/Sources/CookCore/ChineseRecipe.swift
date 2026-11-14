import Foundation

/// Reading recipes written in Chinese: ingredient lines such as "鸡胸肉 2块", "花生碎 适量" or a
/// whole grid row read as one line ("鸡胸肉 2块 鲜面条 300g 黄瓜 1根"), and the sentence rules
/// that tell a step's text from an ingredient. Only what the text says is read.
enum ChineseRecipe {
    private static let units = "克|千克|公斤|斤|两|毫升|升|ml|mL|ML|kg|KG|Kg|g|G|汤匙|茶匙|小勺|大勺|小匙|大匙|勺|匙|杯|碗|块|根|个|片|瓣|颗|只|把|条|段|张|粒|滴|撮|包|袋|盒|罐|瓶|朵|棵|头|cm|厘米|小把|大把|小块|大块"
    private static let number = #"(?:约|大约)?(?:\d+(?:\.\d+)?(?:/\d+)?(?:\s*[-~～到至]\s*\d+(?:\.\d+)?)?|[一二两三四五六七八九十半]+)"#
    private static let vague = "各适量|各少许|一点点|适量|少许|若干|少量|一点|一小把|一把"
    /// An amount: a number and a unit ("2块", "300g", "半根"), a vague amount ("适量"), or a bare
    /// number at the end of an item ("鸡蛋 2").
    private static var quantity: String {
        "(?:" + number + #"\s*(?:"# + units + ")|" + vague + #"|\d+(?:\.\d+)?(?=\s|$))"#
    }

    private static let itemRegex = try? NSRegularExpression(
        pattern: #"([\p{Han}A-Za-z][\p{Han}A-Za-z（）()·]*?)\s*[:：]?\s*("# + quantity + ")")
    private static let quantityFirstRegex = try? NSRegularExpression(
        pattern: #"^((?:"# + number + #"\s*(?:"# + units + ")|" + vague + #"))\s*([\p{Han}A-Za-z].*)$"#)
    private static let amountRegex = try? NSRegularExpression(
        pattern: #"^(?:约|大约)?(\d+(?:\.\d+)?(?:/\d+)?(?:\s*[-~～到至]\s*\d+(?:\.\d+)?)?|[一二两三四五六七八九十半]+)?\s*(.*)$"#)

    static func hasHan(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    /// Has the punctuation of a sentence, so it is a step or a note, not an ingredient line.
    static func isSentence(_ text: String) -> Bool {
        text.contains { "，。；！？".contains($0) }
    }

    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return true }
        return "。！？；.!?".contains(last)
    }

    /// A step panel's short title ("煮鸡胸肉"), which its text follows.
    static func isShortTitle(_ text: String) -> Bool {
        hasHan(text) && text.count <= 10 && !text.contains { "，。；！？：:,.".contains($0) }
    }

    /// The ingredients in one line, in order; empty when the line holds no amount at all.
    static func ingredients(in line: String) -> [ImportedRecipe.Ingredient] {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let itemRegex, let quantityFirstRegex else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        let matches = itemRegex.matches(in: text, range: whole)
        if matches.isEmpty {
            // "2个鸡蛋", "少许盐": the amount first, one item.
            if let match = quantityFirstRegex.firstMatch(in: text, range: whole),
               let amount = Range(match.range(at: 1), in: text), let name = Range(match.range(at: 2), in: text) {
                return [item(name: String(text[name]), quantity: String(text[amount]))]
            }
            return []
        }
        var result: [ImportedRecipe.Ingredient] = []
        var cursor = text.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text),
                  let amount = Range(match.range(at: 2), in: text) else { continue }
            // Words between two items with no amount of their own ("葱花 鸡蛋 2个" → 葱花).
            result += bareItems(String(text[cursor..<whole.lowerBound]))
            result.append(item(name: String(text[name]), quantity: String(text[amount])))
            cursor = whole.upperBound
        }
        result += bareItems(String(text[cursor...]))
        return result
    }

    private static func bareItems(_ text: String) -> [ImportedRecipe.Ingredient] {
        text.split(whereSeparator: { $0.isWhitespace || "、,，".contains($0) })
            .map { String($0) }
            .filter { hasHan($0) }
            .map { token in
                // "2个鸡蛋": an item written amount first.
                if let quantityFirstRegex,
                   let match = quantityFirstRegex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
                   let amount = Range(match.range(at: 1), in: token), let name = Range(match.range(at: 2), in: token) {
                    return item(name: String(token[name]), quantity: String(token[amount]))
                }
                return ImportedRecipe.Ingredient(amount: "", unit: "", name: token)
            }
    }

    private static func item(name: String, quantity: String) -> ImportedRecipe.Ingredient {
        let name = name.trimmingCharacters(in: .whitespaces)
        let quantity = quantity.trimmingCharacters(in: .whitespaces)
        if quantity.range(of: "^(?:" + vague + ")$", options: .regularExpression) != nil {
            return .init(amount: "", unit: quantity, name: name)
        }
        guard let amountRegex,
              let match = amountRegex.firstMatch(in: quantity, range: NSRange(quantity.startIndex..., in: quantity)) else {
            return .init(amount: "", unit: quantity, name: name)
        }
        let numberText = Range(match.range(at: 1), in: quantity).map { String(quantity[$0]) } ?? ""
        let unit = Range(match.range(at: 2), in: quantity).map { String(quantity[$0]) }?
            .trimmingCharacters(in: .whitespaces) ?? ""
        var amount = ""
        if !numberText.isEmpty {
            if numberText.first?.isNumber == true, numberText.first?.isASCII == true {
                amount = numberText.replacingOccurrences(of: #"\s*[~～到至]\s*"#, with: "-", options: .regularExpression)
                    .replacingOccurrences(of: " ", with: "")
            } else if let value = chineseNumber(numberText) {
                amount = value
            } else {
                // Not a number after all (适量 caught by the number pattern can't happen, but be safe).
                return .init(amount: "", unit: numberText + unit, name: name)
            }
        }
        return .init(amount: amount, unit: unit, name: name)
    }

    /// 一 → "1", 两 → "2", 十二 → "12", 半 → "1/2", 两半 → "2 1/2"; nil when it isn't a number.
    static func chineseNumber(_ text: String) -> String? {
        let digits: [Character: Int] = ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var body = text
        var half = false
        if body.hasSuffix("半") { half = true; body.removeLast() }
        var value = 0
        if body.isEmpty {
            value = 0
        } else if let ten = body.firstIndex(of: "十") {
            let before = body[..<ten], after = body[body.index(after: ten)...]
            guard before.count <= 1, after.count <= 1 else { return nil }
            let tens = before.first.map { digits[$0] ?? -1 } ?? 1
            let ones = after.first.map { digits[$0] ?? -1 } ?? 0
            guard tens >= 0, ones >= 0 else { return nil }
            value = tens * 10 + ones
        } else if body.count == 1, let digit = digits[body.first!] {
            value = digit
        } else {
            return nil
        }
        if half { return value == 0 ? "1/2" : "\(value) 1/2" }
        return value > 0 ? "\(value)" : nil
    }
}
