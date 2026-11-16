import Foundation
import CookCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Create with AI: writes a new recipe from what the cook asks for (a dish's name, an idea,
/// or the ingredients they have), in the language they ask in. Unlike every import, this one
/// is invented, so the review screen says so and asks the cook to check it before saving.
/// Uses the cook's own Gemini key when one is saved, else the on-device Apple Intelligence
/// model, where nothing leaves the phone.
enum RecipeCreator {
    enum Engine: String, CaseIterable, Identifiable {
        case gemini = "Gemini"
        case apple = "Apple Intelligence"
        var id: String { rawValue }

        var privacyNote: String {
            switch self {
            case .gemini: return "Your request goes to Google's Gemini with your own key. On the free tier, Google may use it to improve its products."
            case .apple: return "Written on this iPhone, so nothing you type leaves it. The phone's own model is small: it knows fewer dishes than Gemini and its recipes are simpler."
            }
        }
    }

    struct Request: Equatable {
        var idea = ""
        var servings = 2
        /// Use only the ingredients listed, plus basic seasonings.
        var onlyListed = false
    }

    enum Failure: LocalizedError {
        case noEngine
        case nothing
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .noEngine: return "Add a Gemini key, or turn on Apple Intelligence, to create recipes."
            case .nothing: return "No recipe came back for this. Try naming a dish, or listing a few ingredients."
            case .refused(let why): return why
            }
        }
    }

    /// For UI tests: a canned answer instead of a real model.
    static var fake: Bool { ProcessInfo.processInfo.environment["COOK_FAKE_AI"] == "1" }

    /// What can write a recipe on this phone right now, best first.
    static var engines: [Engine] {
        if fake { return [.gemini, .apple] }
        return (OnlineVideoReader.hasKey ? [.gemini] : []) + (RecipeAssistant.isAvailable ? [.apple] : [])
    }

    static func instructions(_ request: Request) -> String {
        """
        You are an experienced home cook writing a recipe for another home cook. Write one complete, \
        practical recipe for what the cook asks for, for \(request.servings) \(request.servings == 1 ? "person" : "people"). \
        When the request names a known dish, write the classic home-style version that most families make, \
        with its usual ingredients and seasonings, not a fusion twist. The request may also be an idea or a \
        list of ingredients they have; then build a good, well-known style of dish around them\(request.onlyListed ? ", using only those plus water, salt, pepper, sugar, cooking oil and basic sauces such as soy sauce" : ""). \
        Write in the language of the request: a Chinese request gets a recipe in Chinese, using the same \
        simplified or traditional characters. Give every ingredient a realistic amount with a unit (grams and \
        millilitres, or spoons; in Chinese use units such as 克, 毫升, 勺, 个, 根, 瓣, and 适量 only for seasoning to taste). \
        Write 4 to 8 steps. Each is one clear instruction with the heat level and how long, including \
        preparation such as cutting, marinating or soaking. If the request isn't about food or drink, return empty lists.
        """
    }

    /// Progress while a recipe is written: what has arrived so far, so the wait never looks stuck.
    typealias Progress = @Sendable (String) -> Void

    static func progressLine(title: String, ingredients: Int, steps: Int, seconds: Int) -> String {
        var line = title.isEmpty ? "Thinking about the recipe…" : "Writing \(title)…"
        if steps > 0 { line += " \(ingredients) ingredients, \(steps) steps" }
        else if ingredients > 0 { line += " \(ingredients) ingredients" }
        if seconds >= 3 { line += " · \(seconds)s" }
        return line
    }

    /// A draft of a new recipe for the review screen.
    static func create(_ request: Request, with engine: Engine, progress: @escaping Progress = { _ in }) async throws -> RecipeDraft {
        let idea = request.idea.trimmingCharacters(in: .whitespacesAndNewlines)
        var answer: ImportedRecipe?
        if fake {
            progress(progressLine(title: "番茄炒蛋", ingredients: 3, steps: 0, seconds: 0))
            try await Task.sleep(for: .milliseconds(300))
            answer = ImportedRecipe(title: "番茄炒蛋", servings: request.servings, totalMinutes: 15,
                                    ingredients: [.init(amount: "3", unit: "个", name: "鸡蛋"),
                                                  .init(amount: "2", unit: "个", name: "番茄"),
                                                  .init(amount: "", unit: "适量", name: "盐")],
                                    steps: ["鸡蛋打散，大火炒至凝固后盛出。", "番茄切块，中火炒2分钟出汁。", "倒回鸡蛋，加盐翻炒均匀即可。"],
                                    siteName: "", cuisine: "Chinese", category: "food")
        } else {
            switch engine {
            case .gemini: answer = try await gemini(idea, request, progress)
            case .apple: answer = try await apple(idea, request, progress)
            }
        }
        guard var recipe = answer, !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else { throw Failure.nothing }
        if recipe.title.isEmpty { recipe.title = String(idea.prefix(40)) }
        recipe.servings = request.servings
        var draft = RecipeDraft(imported: recipe, sourceURL: nil, sourceName: "Created with \(engine.rawValue)")
        draft.createdBy = engine.rawValue
        // There is no source to compare with, so the "not in the source" line doesn't apply.
        draft.notInSource = []
        return draft
    }

    // MARK: Gemini

    /// The answer's shape, enforced by Gemini (structured output), so it can't drift or wrap the JSON.
    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "ingredients": ["type": "array", "items": [
                "type": "object",
                "properties": ["amount": ["type": "string"], "unit": ["type": "string"], "name": ["type": "string"]],
                "required": ["amount", "unit", "name"],
            ]],
            "steps": ["type": "array", "items": ["type": "string"]],
            "totalMinutes": ["type": "integer"],
            "category": ["type": "string", "enum": ["food", "drinks", "desserts"]],
            "cuisine": ["type": "string", "description": "One English word, such as Chinese, Italian or French."],
        ],
        "required": ["title", "ingredients", "steps", "totalMinutes", "category", "cuisine"],
        "propertyOrdering": ["title", "ingredients", "steps", "totalMinutes", "category", "cuisine"],
    ]

    private static func gemini(_ idea: String, _ request: Request, _ progress: @escaping Progress) async throws -> ImportedRecipe? {
        guard let key = OnlineVideoReader.savedKey else { throw Failure.noEngine }
        var config: [String: Any] = ["responseMimeType": "application/json", "responseSchema": schema,
                                     // A recipe needs knowledge, not long reasoning: low thinking answers in seconds.
                                     "thinkingConfig": ["thinkingLevel": "low"]]
        let started = Date()
        var lastError: Error = Failure.nothing
        for model in OnlineVideoReader.models {
            for attempt in 0..<3 {
                if attempt > 0 { try await Task.sleep(for: .seconds(2 * attempt)) }
                let body: [String: Any] = [
                    "systemInstruction": ["parts": [["text": instructions(request)]]],
                    "contents": [["role": "user", "parts": [["text": idea]]]],
                    "generationConfig": config,
                ]
                // Streamed, so the recipe shows up as it is written.
                var call = URLRequest(url: URL(string: "\(OnlineVideoReader.api)/v1beta/models/\(model):streamGenerateContent?alt=sse")!,
                                      timeoutInterval: 90)
                call.httpMethod = "POST"
                call.setValue("application/json", forHTTPHeaderField: "Content-Type")
                call.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                call.httpBody = try JSONSerialization.data(withJSONObject: body)
                let ticker = Task {
                    while !Task.isCancelled {
                        progress(progressLine(title: "", ingredients: 0, steps: 0, seconds: Int(Date().timeIntervalSince(started))))
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: call)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 200 {
                        var text = ""
                        for try await line in bytes.lines where line.hasPrefix("data:") {
                            let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                            if let error = json?["error"] as? [String: Any] {
                                ticker.cancel()
                                throw Failure.refused("Gemini stopped answering: \(error["message"] as? String ?? "")")
                            }
                            text += ((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
                                .flatMap { $0 as? [[String: Any]] }?
                                .filter { ($0["thought"] as? Bool) != true }
                                .compactMap { $0["text"] as? String }.joined() ?? ""
                            if !text.isEmpty {
                                ticker.cancel()
                                progress(partialProgress(text, seconds: Int(Date().timeIntervalSince(started))))
                            }
                        }
                        ticker.cancel()
                        return try OnlineVideoReader.parse(text)
                    }
                    ticker.cancel()
                    var data = Data()
                    for try await byte in bytes { data.append(byte) }
                    do { try OnlineVideoReader.check(response, data) } catch { lastError = error }
                    // An older model that doesn't know a setting: try again without the extras.
                    if status == 400, case OnlineVideoReader.Failure.refused(let message) = lastError,
                       message.localizedCaseInsensitiveContains("thinking") || message.localizedCaseInsensitiveContains("schema") {
                        config = ["responseMimeType": "application/json"]
                        continue
                    }
                    if [429, 500, 503, 504].contains(status) { continue }
                    break
                } catch let error as URLError where error.code != .cancelled {
                    ticker.cancel()
                    lastError = Failure.refused("Couldn't reach Gemini. Check the internet connection and try again.")
                    continue
                }
            }
            // Only a model Google no longer offers moves on to the next one.
            guard case OnlineVideoReader.Failure.refused(let message) = lastError,
                  message.contains("not found") || message.contains("is not supported") || message.contains("HTTP 404")
            else { break }
        }
        if let failure = lastError as? OnlineVideoReader.Failure, case .refused(let message) = failure {
            throw Failure.refused("Gemini couldn't write this recipe: \(message)")
        }
        throw lastError
    }

    /// What a half-written JSON answer has so far: its title and how many ingredients and steps.
    static func partialProgress(_ text: String, seconds: Int) -> String {
        var title = ""
        if let range = text.range(of: #""title"\s*:\s*"([^"]*)""#, options: .regularExpression) {
            title = String(text[range]).components(separatedBy: "\"").dropLast().last ?? ""
        }
        let ingredients = text.components(separatedBy: "\"name\"").count - 1
        var steps = 0
        if let open = text.range(of: "\"steps\"") {
            // Each step is a string: count the ones started so far.
            let list = text[open.upperBound...].prefix { $0 != "]" }
            let quotes = list.filter { $0 == "\"" }.count
            steps = (quotes + 1) / 2
        }
        return progressLine(title: title, ingredients: ingredients, steps: steps, seconds: seconds)
    }

    // MARK: Apple Intelligence

    /// A session loaded while the cook types, so the first words come sooner; kept with the
    /// instructions it was made for (a LanguageModelSession, typed loosely for older iOS).
    private static var warm: (instructions: String, session: AnyObject)?

    static func prewarm(_ request: Request) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), RecipeAssistant.isAvailable, !fake {
            let text = instructions(request)
            guard warm?.instructions != text else { return }
            let session = LanguageModelSession(instructions: text)
            session.prewarm()
            warm = (text, session)
        }
        #endif
    }

    private static func apple(_ idea: String, _ request: Request, _ progress: @escaping Progress) async throws -> ImportedRecipe? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), RecipeAssistant.isAvailable {
            // The warmed session only if its instructions still match (servings or the switch may have changed).
            let text = instructions(request)
            let session = (warm?.instructions == text ? warm?.session as? LanguageModelSession : nil)
                ?? LanguageModelSession(instructions: text)
            warm = nil
            let started = Date()
            do {
                let stream = session.streamResponse(to: idea, generating: CreatedRecipe.self,
                                                    options: GenerationOptions(temperature: 0.5))
                var last: GeneratedContent?
                for try await snapshot in stream {
                    let partial = snapshot.content
                    progress(progressLine(title: partial.title ?? "", ingredients: partial.ingredients?.count ?? 0,
                                          steps: partial.steps?.count ?? 0, seconds: Int(Date().timeIntervalSince(started))))
                    last = snapshot.rawContent
                }
                guard let last else { return nil }
                let answer = try CreatedRecipe(last)
                let ingredients = answer.ingredients.compactMap { item -> ImportedRecipe.Ingredient? in
                    let name = item.name.trimmingCharacters(in: .whitespaces)
                    return name.isEmpty ? nil : .init(amount: item.amount.trimmingCharacters(in: .whitespaces),
                                                      unit: item.unit.trimmingCharacters(in: .whitespaces), name: name)
                }
                let steps = answer.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return ImportedRecipe(title: answer.title.trimmingCharacters(in: .whitespaces), servings: nil,
                                      totalMinutes: answer.totalMinutes > 0 ? answer.totalMinutes : nil,
                                      ingredients: ingredients, steps: steps, siteName: "", cuisine: nil)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal:
                    throw Failure.refused("Apple Intelligence wouldn't write a recipe for this. Try wording it differently.")
                case .unsupportedLanguageOrLocale:
                    throw Failure.refused("Apple Intelligence doesn't write in this language on this iPhone yet. Add a Gemini key, or ask in English.")
                default:
                    throw Failure.refused("Apple Intelligence couldn't write this recipe. Try again, or with a shorter request.")
                }
            }
        }
        #endif
        throw Failure.noEngine
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct CreatedRecipe {
    @Guide(description: "The dish's name, in the request's language.")
    var title: String
    @Guide(description: "Every ingredient with its amount, in the order it is used.", .maximumCount(16))
    var ingredients: [CreatedIngredient]
    @Guide(description: "4 to 8 cooking steps in order, each one short instruction with heat and time, in the request's language.", .maximumCount(10))
    var steps: [String]
    @Guide(description: "About how many minutes it takes in all, preparation included.")
    var totalMinutes: Int
}

@available(iOS 26.0, *)
@Generable
struct CreatedIngredient {
    @Guide(description: "The amount as a number or fraction, such as 2, 300 or 1/2. Empty only for seasoning to taste.")
    var amount: String
    @Guide(description: "The unit, such as g, ml, tbsp, tsp, 克, 毫升, 勺, 个, 根, 瓣, 适量. Empty for a whole item counted in English, such as 2 eggs.")
    var unit: String
    @Guide(description: "The ingredient's name, in the request's language.")
    var name: String
}
#endif
