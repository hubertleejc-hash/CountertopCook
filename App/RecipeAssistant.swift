import Foundation
import CookCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes out a recipe from text that says it in prose: a video's captions or speech, a long
/// description, or a photo whose layout the plain reader couldn't follow. Uses the on-device
/// Apple Intelligence model (iOS 26 and later, on phones that have it): nothing leaves the
/// phone, and no account is needed. What it writes is a draft for the review screen, told to
/// use only what the text says; the cook checks it before saving.
enum RecipeAssistant {
    enum Status: Equatable {
        case available
        /// Apple Intelligence is off, still downloading, or not on this phone.
        case unavailable(String)
    }

    static var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in Settings so Hearth can write out recipes that are only spoken.")
            case .unavailable(.modelNotReady):
                return .unavailable("Apple Intelligence is still getting ready on this iPhone. Try again in a while.")
            case .unavailable:
                return .unavailable("This iPhone doesn't have Apple Intelligence, which Hearth needs to write out a spoken recipe.")
            }
        }
        #endif
        return .unavailable("Writing out a spoken recipe needs Apple Intelligence (iOS 26 or later).")
    }

    static var isAvailable: Bool { status == .available }

    /// The recipe in `text`, or nil when the model isn't available or finds none.
    static func recipe(from text: String, title: String? = nil) async -> ImportedRecipe? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            return await generate(from: text, title: title)
        }
        #endif
        return nil
    }

    /// The text in pieces the model can take at once (its context is about 4,000 tokens, and a
    /// Chinese character is about a token).
    static func chunks(_ text: String, size: Int = 1600, limit: Int = 4) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            if current.count + line.count > size, !current.isEmpty {
                pieces.append(current)
                current = ""
                if pieces.count == limit { break }
            }
            current += (current.isEmpty ? "" : "\n") + String(line.prefix(size))
        }
        if !current.isEmpty, pieces.count < limit { pieces.append(current) }
        return pieces
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedRecipe {
    @Guide(description: "The dish's name as the text gives it, in the text's language. Empty if the text doesn't name it.")
    var title: String
    @Guide(description: "How many people it serves, only if the text says. 0 if it doesn't.")
    var servings: Int
    @Guide(description: "Every ingredient the text says to use, in the order it comes up. Empty if there are none.")
    var ingredients: [GeneratedIngredient]
    @Guide(description: "The cooking steps in order. Each is one short instruction in the text's own language, keeping any time or temperature it states. Empty if the text gives none.")
    var steps: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedIngredient {
    @Guide(description: "The amount exactly as stated, as a number or fraction such as 2, 300 or 1/2. Empty when the text gives no amount.")
    var amount: String
    @Guide(description: "The unit as stated, such as g, ml, tbsp, cup, 克, 勺, 个, 根, 适量, 少许. Empty when there is none.")
    var unit: String
    @Guide(description: "The ingredient's name, in the text's language.")
    var name: String
}

@available(iOS 26.0, *)
extension RecipeAssistant {
    static let instructions = """
    You read cooking text: what a cooking video says, its description, or text read from a photo of a recipe. \
    Write out the recipe it describes. Use only what the text says. Never add an ingredient, amount, time, \
    temperature or step the text doesn't give; leave an amount empty when it isn't stated. Keep the text's \
    own language (Chinese stays Chinese). Leave out greetings, stories, ads and requests to like or subscribe.
    """

    fileprivate static func generate(from text: String, title: String?) async -> ImportedRecipe? {
        var name = ""
        var servings: Int?
        var ingredients: [ImportedRecipe.Ingredient] = []
        var steps: [String] = []
        let pieces = chunks(text)
        for (index, piece) in pieces.enumerated() {
            let session = LanguageModelSession(instructions: instructions)
            var prompt = ""
            if let title, !title.isEmpty { prompt += "Title: \(title)\n" }
            if pieces.count > 1 { prompt += "This is part \(index + 1) of \(pieces.count) of the text.\n" }
            prompt += "Text:\n" + piece
            guard let response = try? await session.respond(to: prompt, generating: GeneratedRecipe.self) else { continue }
            let part = response.content
            if name.isEmpty { name = part.title.trimmingCharacters(in: .whitespaces) }
            if servings == nil, part.servings > 0 { servings = part.servings }
            for item in part.ingredients {
                let itemName = item.name.trimmingCharacters(in: .whitespaces)
                guard !itemName.isEmpty,
                      !ingredients.contains(where: { $0.name.caseInsensitiveCompare(itemName) == .orderedSame }) else { continue }
                ingredients.append(.init(amount: item.amount.trimmingCharacters(in: .whitespaces),
                                         unit: item.unit.trimmingCharacters(in: .whitespaces), name: itemName))
            }
            steps += part.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }
        return ImportedRecipe(title: title?.isEmpty == false ? title! : name, servings: servings, totalMinutes: nil,
                              ingredients: ingredients, steps: steps, siteName: "", cuisine: nil)
    }
}
#endif
