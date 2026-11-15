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
            case .apple: return "Written on this iPhone. Nothing you type leaves it."
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
        The request may be a dish's name, an idea, or a list of ingredients they have; with ingredients, \
        build a good dish around them\(request.onlyListed ? ", using only those plus water, salt, pepper, sugar, cooking oil and basic sauces such as soy sauce" : ""). \
        Write in the language of the request: a Chinese request gets a recipe in Chinese, using the same \
        simplified or traditional characters. Give every ingredient a realistic amount with a unit (grams and \
        millilitres, or spoons; in Chinese use units such as 克, 毫升, 勺, 个, 根, 瓣, and 适量 only for seasoning to taste). \
        Each step is one clear instruction, with the heat level and how long. If the request isn't about food \
        or drink, return empty lists.
        """
    }

    /// A draft of a new recipe for the review screen.
    static func create(_ request: Request, with engine: Engine) async throws -> RecipeDraft {
        let idea = request.idea.trimmingCharacters(in: .whitespacesAndNewlines)
        var answer: ImportedRecipe?
        if fake {
            try await Task.sleep(for: .milliseconds(300))
            answer = ImportedRecipe(title: "番茄炒蛋", servings: request.servings, totalMinutes: 15,
                                    ingredients: [.init(amount: "3", unit: "个", name: "鸡蛋"),
                                                  .init(amount: "2", unit: "个", name: "番茄"),
                                                  .init(amount: "", unit: "适量", name: "盐")],
                                    steps: ["鸡蛋打散，大火炒至凝固后盛出。", "番茄切块，中火炒2分钟出汁。", "倒回鸡蛋，加盐翻炒均匀即可。"],
                                    siteName: "", cuisine: "Chinese", category: "food")
        } else {
            switch engine {
            case .gemini: answer = try await gemini(idea, request)
            case .apple: answer = try await apple(idea, request)
            }
        }
        guard var recipe = answer, !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else { throw Failure.nothing }
        if recipe.title.isEmpty { recipe.title = String(idea.prefix(40)) }
        if recipe.servings == nil { recipe.servings = request.servings }
        var draft = RecipeDraft(imported: recipe, sourceURL: nil, sourceName: "Created with \(engine.rawValue)")
        draft.createdBy = engine.rawValue
        // There is no source to compare with, so the "not in the source" line doesn't apply.
        draft.notInSource = []
        return draft
    }

    // MARK: Gemini

    private static let schemaPrompt = """
    Answer with JSON only, in this shape:
    {"title": "", "servings": 0, "totalMinutes": 0, "category": "food | drinks | desserts", "cuisine": "", \
    "ingredients": [{"amount": "", "unit": "", "name": ""}], "steps": [""]}
    cuisine is one English word such as Chinese, Italian or French.
    """

    private static func gemini(_ idea: String, _ request: Request) async throws -> ImportedRecipe? {
        guard let key = OnlineVideoReader.savedKey else { throw Failure.noEngine }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instructions(request) + "\n" + schemaPrompt]]],
            "contents": [["role": "user", "parts": [["text": idea]]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.7],
        ]
        var lastError: Error = Failure.nothing
        for model in OnlineVideoReader.models {
            for attempt in 0..<3 {
                if attempt > 0 { try await Task.sleep(for: .seconds(2 * attempt)) }
                var call = URLRequest(url: URL(string: "\(OnlineVideoReader.api)/v1beta/models/\(model):generateContent")!,
                                      timeoutInterval: 120)
                call.httpMethod = "POST"
                call.setValue("application/json", forHTTPHeaderField: "Content-Type")
                call.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                call.httpBody = try JSONSerialization.data(withJSONObject: body)
                let data: Data, response: URLResponse
                do {
                    (data, response) = try await URLSession.shared.data(for: call)
                } catch let error as URLError where error.code != .cancelled {
                    lastError = Failure.refused("Couldn't reach Gemini. Check the internet connection and try again.")
                    continue
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let text = ((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
                        .flatMap { $0 as? [[String: Any]] }?.compactMap { $0["text"] as? String }.joined() ?? ""
                    return try OnlineVideoReader.parse(text)
                }
                do { try OnlineVideoReader.check(response, data) } catch { lastError = error }
                if [429, 500, 503, 504].contains(status) { continue }
                break
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

    // MARK: Apple Intelligence

    private static func apple(_ idea: String, _ request: Request) async throws -> ImportedRecipe? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), RecipeAssistant.isAvailable {
            let session = LanguageModelSession(instructions: instructions(request))
            do {
                let answer = try await session.respond(to: idea, generating: CreatedRecipe.self).content
                let ingredients = answer.ingredients.compactMap { item -> ImportedRecipe.Ingredient? in
                    let name = item.name.trimmingCharacters(in: .whitespaces)
                    return name.isEmpty ? nil : .init(amount: item.amount.trimmingCharacters(in: .whitespaces),
                                                      unit: item.unit.trimmingCharacters(in: .whitespaces), name: name)
                }
                let steps = answer.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return ImportedRecipe(title: answer.title.trimmingCharacters(in: .whitespaces),
                                      servings: answer.servings > 0 ? answer.servings : nil,
                                      totalMinutes: answer.totalMinutes > 0 ? answer.totalMinutes : nil,
                                      ingredients: ingredients, steps: steps, siteName: "",
                                      cuisine: answer.cuisine.isEmpty ? nil : answer.cuisine, category: answer.category)
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
    @Guide(description: "How many people it serves.")
    var servings: Int
    @Guide(description: "About how many minutes it takes in all, preparation included.")
    var totalMinutes: Int
    @Guide(description: "One of: food, drinks, desserts.")
    var category: String
    @Guide(description: "The cuisine as one English word, such as Chinese, Italian or French.")
    var cuisine: String
    @Guide(description: "Every ingredient, in the order it is used.")
    var ingredients: [CreatedIngredient]
    @Guide(description: "The cooking steps in order, each one short instruction with heat and time, in the request's language.")
    var steps: [String]
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
