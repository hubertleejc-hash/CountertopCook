import Foundation
import SwiftData
import CookCore

/// The three shelves of the library.
enum RecipeCategory: String, CaseIterable, Identifiable {
    case food = "Food", drinks = "Drinks", desserts = "Desserts"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .drinks: return "cup.and.saucer"
        case .desserts: return "birthday.cake"
        }
    }

    /// From a category a recipe page publishes ("Dessert", "Cocktails", "Main course"). Only
    /// drinks and desserts are recognised; everything else is Food.
    static func from(published text: String?) -> RecipeCategory {
        guard let text = text?.lowercased() else { return .food }
        if ["dessert", "cake", "cookie", "sweet", "pudding", "ice cream", "pastry", "baking"].contains(where: text.contains) {
            return .desserts
        }
        if ["drink", "beverage", "cocktail", "smoothie", "juice", "coffee", "tea"].contains(where: text.contains) {
            return .drinks
        }
        return .food
    }
}

@Model
final class Recipe {
    var title: String
    var servings: Int
    var totalMinutes: Int
    var createdAt: Date
    /// Where an imported recipe came from (the page's URL and the site's name); nil for recipes
    /// typed in or shipped with the app.
    var sourceURL: String?
    var sourceName: String?
    /// "french" or "italian" for a recipe with that accent; nil for none.
    var cuisine: String?
    /// A `RecipeCategory` raw value: "Food", "Drinks" or "Desserts".
    var category: String = "Food"
    var isFavorite: Bool = false
    /// The cook's own notes: what they changed, who they made it for.
    var notes: String = ""
    @Relationship(deleteRule: .cascade, inverse: \RecipePhoto.recipe) var photos: [RecipePhoto] = []
    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe) var ingredients: [Ingredient] = []
    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe) var steps: [RecipeStep] = []

    init(title: String, servings: Int, totalMinutes: Int, createdAt: Date = Date()) {
        self.title = title
        self.servings = servings
        self.totalMinutes = totalMinutes
        self.createdAt = createdAt
    }

    var cuisineKind: Cuisine? { Cuisine.from(tag: cuisine) }
    var categoryKind: RecipeCategory { RecipeCategory(rawValue: category) ?? .food }
    var sortedIngredients: [Ingredient] { ingredients.sorted { $0.order < $1.order } }
    var sortedSteps: [RecipeStep] { steps.sorted { $0.order < $1.order } }
    /// In the order they were added; the first is the cover of the recipe's book.
    var sortedPhotos: [RecipePhoto] { photos.sorted { $0.order < $1.order } }
}

/// One photo of a recipe, stored as a JPEG no larger than `PhotoStore.maxPixel` on its long side.
@Model
final class RecipePhoto {
    @Attribute(.externalStorage) var data: Data
    var order: Int
    var recipe: Recipe?

    init(data: Data, order: Int) {
        self.data = data
        self.order = order
    }
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

/// One line of the to-buy list. Amounts are free text, like ingredients, so fractions stay exact.
@Model
final class ShoppingItem {
    var name: String
    var amountText: String
    var unit: String
    var isBought: Bool = false
    /// Titles of the recipes this is for, separated by " · ".
    var recipes: String = ""
    var createdAt: Date = Date()

    init(name: String, amountText: String, unit: String, recipes: String) {
        self.name = name
        self.amountText = amountText
        self.unit = unit
        self.recipes = recipes
    }

    var line: ShoppingLine { ShoppingLine(amount: amountText, unit: unit, name: name) }
}

enum ToBuy {
    /// Adds a recipe's needed ingredients to the list. An item already waiting on the list in
    /// the same unit gets the amounts added together (2 tbsp butter + 3 tbsp butter = 5 tbsp).
    static func add(_ lines: [ShoppingLine], from recipeTitle: String, context: ModelContext) {
        var waiting = ((try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? []).filter { !$0.isBought }
        for line in ShoppingMerge.combine(lines) {
            if let item = waiting.first(where: { ShoppingMerge.canCombine($0.line, line) }) {
                let sum = ShoppingMerge.sum(item.line, line)
                item.amountText = sum.amount
                item.name = sum.name
                var titles = item.recipes.components(separatedBy: " · ").filter { !$0.isEmpty }
                if !titles.contains(recipeTitle) { titles.append(recipeTitle) }
                item.recipes = titles.joined(separator: " · ")
            } else {
                let item = ShoppingItem(name: line.name, amountText: line.amount, unit: line.unit, recipes: recipeTitle)
                context.insert(item)
                waiting.append(item)
            }
        }
        try? context.save()
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
    var category = RecipeCategory.food
    var sourceURL: String?
    var sourceName: String?
    var cuisine: String?
    /// Import review only: what the source didn't say ("servings", "total time"), so the review
    /// screen can point at the blanks instead of filling them in.
    var notInSource: [String] = []
    /// Import review only: the source's own text, shown when no recipe list could be read from it.
    var referenceText: String?
    /// Import review only: the source's own photo of the dish (a JPEG), and whether to keep it as
    /// the cover of the recipe's book.
    var coverImage: Data?
    var useCoverImage = true
    /// Import review only: who wrote the recipe out when the source only said it in prose
    /// ("Apple Intelligence, from what the video says"), so the review screen can say so.
    var readBy: String?
    /// Import only: why no recipe could be found, for the "couldn't find it" screen.
    var emptyReason: String?

    /// An import that found neither ingredients nor steps.
    var foundNothing: Bool { notInSource.contains("ingredients") && notInSource.contains("steps") }

    init() {}

    /// A draft from an import, for the review screen. Only what the source gave: unknown
    /// servings become 1 (amounts as written), unknown total time stays 0 ("not given"), and a
    /// step gets a timer only when its own text states a time.
    init(imported: ImportedRecipe, sourceURL: String?, sourceName: String?, referenceText: String? = nil) {
        title = imported.title
        servings = imported.servings ?? 1
        totalMinutes = imported.totalMinutes ?? 0
        if imported.servings == nil { notInSource.append("servings") }
        if imported.totalMinutes == nil { notInSource.append("total time") }
        ingredients = imported.ingredients.map { IngredientDraft(amount: $0.amount, unit: $0.unit, name: $0.name) }
        steps = imported.steps.map { StepDraft(text: $0, timerMinutes: StepTime.minutes(in: $0) ?? 0) }
        if ingredients.isEmpty { ingredients = [IngredientDraft()]; notInSource.append("ingredients") }
        if steps.isEmpty { steps = [StepDraft()]; notInSource.append("steps") }
        category = RecipeCategory.from(published: imported.category)
        cuisine = Cuisine.from(tag: imported.cuisine)?.rawValue
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.referenceText = referenceText
    }

    init(recipe: Recipe) {
        title = recipe.title
        servings = recipe.servings
        totalMinutes = recipe.totalMinutes
        category = recipe.categoryKind
        sourceURL = recipe.sourceURL
        sourceName = recipe.sourceName
        cuisine = recipe.cuisine
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
        target.category = category.rawValue
        target.sourceURL = sourceURL
        target.sourceName = sourceName
        target.cuisine = cuisine

        if recipe == nil, useCoverImage, let coverImage {
            let photo = RecipePhoto(data: coverImage, order: 0)
            context.insert(photo)
            photo.recipe = target
        }

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
