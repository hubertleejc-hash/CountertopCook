import Foundation
import Security
import CookCore

/// Reads the recipe out of a public YouTube video from its link, online, with Google's Gemini
/// API: Google watches the video (picture and sound) on its own servers and Hearth gets back
/// the recipe as text. Hearth never downloads the video, which YouTube's terms don't allow.
/// Uses the cook's own free Gemini API key, kept in the iPhone's Keychain. Only the link and
/// the request go to Google.
enum OnlineVideoReader {
    enum Failure: LocalizedError {
        case noKey
        case refused(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noKey: return "Add a Gemini API key to read videos online."
            case .refused(let reason): return "Gemini couldn't read this video: \(reason)"
            case .unreadable: return "Gemini's answer couldn't be read."
            }
        }
    }

    /// Where to get a key, for the settings screen.
    static let keyPage = URL(string: "https://aistudio.google.com/apikey")!
    /// The model asked; a newer Flash model can be set here when Google retires this one.
    static let model = "gemini-3.8-flash"

    static var hasKey: Bool { !(Keychain.read() ?? "").isEmpty }

    static func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete() } else { Keychain.write(trimmed) }
    }

    static func removeKey() { Keychain.delete() }

    static let prompt = """
    Watch this cooking video, listening to what is said and reading any text shown on screen, \
    and write out its recipe. Use only what the video says or shows: never add an ingredient, \
    amount, time or step it doesn't give, and leave an amount or unit empty when it isn't stated. \
    Keep the video's own language (Chinese stays Chinese). Each step is one short instruction, \
    keeping any time or temperature stated. Answer with JSON only, in this shape:
    {"title": "", "servings": 0, "ingredients": [{"amount": "", "unit": "", "name": ""}], "steps": [""]}
    servings is 0 when the video doesn't say. If the video has no recipe, answer with empty lists.
    """

    /// The recipe in the YouTube video at `url`; nil when the video has none.
    static func recipe(youTube url: URL) async throws -> ImportedRecipe? {
        guard let key = Keychain.read(), !key.isEmpty else { throw Failure.noKey }
        var request = URLRequest(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
            timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt], ["file_data": ["file_uri": url.absoluteString]]]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw Failure.refused(message)
        }
        let text = ((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
            .flatMap { $0 as? [[String: Any]] }?.compactMap { $0["text"] as? String }.joined() ?? ""
        return try parse(text)
    }

    /// Gemini's JSON answer as a recipe; nil when it found none.
    static func parse(_ text: String) throws -> ImportedRecipe? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Tolerate a fenced answer.
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}") { body = String(body[start...end]) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else {
            throw Failure.unreadable
        }
        func string(_ value: Any?) -> String {
            if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let number = value as? NSNumber { return number.stringValue }
            return ""
        }
        let ingredients: [ImportedRecipe.Ingredient] = (object["ingredients"] as? [[String: Any]] ?? []).compactMap { item in
            let name = string(item["name"])
            return name.isEmpty ? nil : .init(amount: string(item["amount"]), unit: string(item["unit"]), name: name)
        }
        let steps = (object["steps"] as? [Any] ?? []).map(string).filter { !$0.isEmpty }
        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }
        let servings = (object["servings"] as? NSNumber)?.intValue ?? Int(string(object["servings"])) ?? 0
        return ImportedRecipe(title: string(object["title"]), servings: servings > 0 ? servings : nil, totalMinutes: nil,
                              ingredients: ingredients, steps: steps, siteName: "", cuisine: nil)
    }
}

/// The Gemini key in the Keychain, on this iPhone only.
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hubertlee.countertopcook.gemini",
        kSecAttrAccount as String: "api-key",
    ]

    static func read() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
