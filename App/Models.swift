import Foundation
import SwiftData

@Model
final class Recipe {
    var title: String
    var servings: Int
    var totalMinutes: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe) var ingredients: [Ingredient] = []
    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe) var steps: [RecipeStep] = []

    init(title: String, servings: Int, totalMinutes: Int, createdAt: Date = Date()) {
        self.title = title
        self.servings = servings
        self.totalMinutes = totalMinutes
        self.createdAt = createdAt
    }

    var sortedIngredients: [Ingredient] { ingredients.sorted { $0.order < $1.order } }
    var sortedSteps: [RecipeStep] { steps.sorted { $0.order < $1.order } }
}

@Model
final class Ingredient {
    /// Free text so fractions like "1 1/2" stay exactly as typed.
    var amountText: String
    var unit: String
    var name: String
    var order: Int
    var recipe: Recipe?

    init(amountText: String, unit: String, name: String, order: Int) {
        self.amountText = amountText
        self.unit = unit
        self.name = name
        self.order = order
    }
}

@Model
final class RecipeStep {
    var text: String
    /// Optional per-step timer in minutes; nil or 0 means no timer.
    var timerMinutes: Int?
    var order: Int
    var recipe: Recipe?

    init(text: String, timerMinutes: Int? = nil, order: Int) {
        self.text = text
        self.timerMinutes = timerMinutes
        self.order = order
    }
}

// MARK: - Editing drafts

struct IngredientDraft: Identifiable, Equatable {
    var id = UUID()
    var amount = ""
    var unit = ""
    var name = ""
}

struct StepDraft: Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var timerMinutes = 0
}

/// Plain value copy of a recipe, edited in the form and written back on Save.
struct RecipeDraft: Equatable {
    var title = ""
    var servings = 2
    var totalMinutes = 30
    var ingredients: [IngredientDraft] = [IngredientDraft()]
    var steps: [StepDraft] = [StepDraft()]

    init() {}

    init(recipe: Recipe) {
        title = recipe.title
        servings = recipe.servings
        totalMinutes = recipe.totalMinutes
        ingredients = recipe.sortedIngredients.map {
            IngredientDraft(amount: $0.amountText, unit: $0.unit, name: $0.name)
        }
        steps = recipe.sortedSteps.map { StepDraft(text: $0.text, timerMinutes: $0.timerMinutes ?? 0) }
    }

    private var cleanSteps: [StepDraft] {
        steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !cleanSteps.isEmpty
    }

    /// Writes the draft into `recipe` (or a new one), replacing its ingredients and steps.
    @discardableResult
    func save(into recipe: Recipe?, context: ModelContext) -> Recipe {
        let target: Recipe
        if let recipe {
            target = recipe
            target.ingredients.forEach { context.delete($0) }
            target.steps.forEach { context.delete($0) }
            target.ingredients = []
            target.steps = []
        } else {
            target = Recipe(title: "", servings: servings, totalMinutes: totalMinutes)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.servings = max(1, servings)
        target.totalMinutes = max(0, totalMinutes)

        let cleanIngredients = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        target.ingredients = cleanIngredients.enumerated().map { index, item in
            Ingredient(amountText: item.amount.trimmingCharacters(in: .whitespaces),
                       unit: item.unit.trimmingCharacters(in: .whitespaces),
                       name: item.name.trimmingCharacters(in: .whitespaces),
                       order: index)
        }
        target.steps = cleanSteps.enumerated().map { index, item in
            RecipeStep(text: item.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       timerMinutes: item.timerMinutes > 0 ? item.timerMinutes : nil,
                       order: index)
        }
        try? context.save()
        return target
    }
}
