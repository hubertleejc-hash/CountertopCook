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
        /// Gemini only: look for a real published recipe first, instead of writing one.
        var searchOnline = true
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
        var line = title.isEmpty ? "Writing the recipe…" : "Writing \(title)…"
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
        } else if engine == .gemini, request.searchOnline, let key = OnlineVideoReader.savedKey {
            do {
                return try await findOnline(idea, request, key: key, progress)
            } catch let failure as Failure {
                if case .nothing = failure {} else { throw failure }
            } catch {
                // Search not possible right now: write one instead, and say so on review.
            }
            var draft = try await create(Request(idea: request.idea, servings: request.servings, onlyListed: request.onlyListed,
                                                 searchOnline: false), with: engine, progress: progress)
            draft.aiNote = "Gemini couldn't find a recipe online for this, so it wrote one from what it knows. Check the amounts, times and anything you're allergic to."
            return draft
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
        let shape = "\n" + #"Answer with JSON only, in this shape: {"title": "", "ingredients": [{"amount": "", "unit": "", "name": ""}], "steps": [""], "totalMinutes": 0, "category": "food, drinks or desserts", "cuisine": "one English word"}"#
        let ask = GeminiJob.Ask(prompt: idea, system: instructions(request) + shape, video: nil, schema: schema, seconds: 90)
        do {
            let text = try await GeminiJob.answer(ask, key: key) { seconds in
                progress(progressLine(title: "", ingredients: 0, steps: 0, seconds: seconds))
            }
            return try OnlineVideoReader.parse(text)
        } catch GeminiJob.Failure.refused(let reason) {
            throw Failure.refused("Gemini couldn't write this recipe: \(reason)")
        }
    }

    // MARK: Gemini, from a real recipe online

    static func searchInstructions(_ request: Request) -> String {
        """
        Search the web for real, published recipes for what the cook asks for. Choose one well-liked recipe from \
        a recipe site or a known cook; for a Chinese dish, prefer Chinese recipe sites such as 下厨房 (xiachufang.com) \
        or 美食天下 (meishichina.com) and well-known Chinese cooks\(request.onlyListed ? ". It should use only the ingredients the cook lists, plus water, salt, pepper, sugar, oil and basic sauces" : ""). \
        Copy that one recipe faithfully: its own ingredients, amounts, servings and steps. Never invent, change or \
        mix in anything from other recipes. Keep the recipe's language if it is the request's language, else \
        translate it into the request's language (a Chinese request gets Chinese). sourceURL is the address of the \
        page you copied it from, and sourceName that site's or cook's name. Answer with JSON only, in this shape:
        {"title": "", "sourceName": "", "sourceURL": "", "servings": 0, "ingredients": [{"amount": "", "unit": "", "name": ""}], \
        "steps": [""], "totalMinutes": 0, "category": "food, drinks or desserts", "cuisine": "one English word"}
        If you find no real recipe for it, answer with empty lists.
        """
    }

    /// Finds a published recipe with Gemini's Google Search. When the page it cites carries a
    /// recipe card, that card is imported as it stands (nothing rewritten); otherwise Gemini's
    /// copy of the page is used, with the page as its source.
    private static func findOnline(_ idea: String, _ request: Request, key: String, _ progress: @escaping Progress) async throws -> RecipeDraft {
        let ask = GeminiJob.Ask(prompt: idea, system: searchInstructions(request), video: nil, schema: schema, seconds: 75,
                                search: true, models: GeminiJob.searchModels)
        let reply: GeminiJob.Reply
        do {
            reply = try await GeminiJob.reply(ask, key: key) { seconds in
                progress("Searching recipes online…" + (seconds >= 3 ? " · \(seconds)s" : ""))
            }
        } catch GeminiJob.Failure.refused(let reason) where reason.localizedCaseInsensitiveContains("key") {
            throw Failure.refused("Gemini didn't accept the key: \(reason)")
        }
        let object = (try? JSONSerialization.jsonObject(with: Data(jsonBody(reply.text).utf8))) as? [String: Any] ?? [:]
        let claimedURL = (object["sourceURL"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let claimedName = (object["sourceName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        // Only pages Google's search actually returned count; an address the model wrote is
        // trusted only when its site is one of them.
        let citedHosts = Set(reply.sources.flatMap { [host($0.url), $0.title.lowercased()] }.filter { !$0.isEmpty })
        var candidates: [URL] = []
        if let url = URL(string: claimedURL), let h = url.host?.lowercased(),
           citedHosts.contains(where: { h == $0 || h.hasSuffix("." + $0) || $0.hasSuffix("." + h) }) {
            candidates.append(url)
        }
        candidates += reply.sources.compactMap { URL(string: $0.url) }
        candidates = Array(candidates.prefix(3))

        // 1. A recipe card on one of the pages: the page's own recipe, word for word.
        if !candidates.isEmpty {
            progress("Opening the recipe it found…")
            let cards = await withTaskGroup(of: (Int, RecipeDraft?).self, returning: [Int: RecipeDraft].self) { group in
                for (index, url) in candidates.enumerated() {
                    group.addTask { (index, await LinkImport.recipeCard(at: url)) }
                }
                var found: [Int: RecipeDraft] = [:]
                for await (index, draft) in group { if let draft { found[index] = draft } }
                return found
            }
            if let best = cards.keys.sorted().first, var draft = cards[best] {
                let site = draft.sourceName?.isEmpty == false ? draft.sourceName! : host(draft.sourceURL ?? "")
                draft.aiNote = "Gemini found this recipe on \(site). Hearth copied it from the page's own recipe card, so the amounts and steps are the page's, unchanged."
                return draft
            }
        }

        // 2. Gemini's copy of the page it read.
        guard !reply.sources.isEmpty, var recipe = try? OnlineVideoReader.parse(reply.text),
              !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else { throw Failure.nothing }
        if recipe.title.isEmpty { recipe.title = String(idea.prefix(40)) }
        let sourceURL = candidates.first?.absoluteString ?? reply.sources[0].url
        let site = !claimedName.isEmpty ? claimedName : (reply.sources[0].title.isEmpty ? host(sourceURL) : reply.sources[0].title)
        var draft = RecipeDraft(imported: recipe, sourceURL: sourceURL, sourceName: site)
        draft.createdBy = "Gemini"
        draft.notInSource.removeAll { $0 == "ingredients" || $0 == "steps" }
        draft.aiNote = "Gemini read this recipe on \(site) and wrote it out here, translating it if needed. Check it against the original page before saving: Gemini can misread an amount."
        return draft
    }

    private static func host(_ address: String) -> String {
        (URL(string: address)?.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
    }

    /// The JSON object in an answer that may wrap it in prose or a code fence.
    private static func jsonBody(_ text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return "{}" }
        return String(text[start...end])
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
