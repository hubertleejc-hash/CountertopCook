import Foundation
import SwiftData

/// The three starter recipes. They're ordinary recipes, so they can be edited or deleted.
enum SeedData {
    private static let seededKey = "didSeedStarterRecipes"

    static func seedIfNeeded(_ context: ModelContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        guard force || !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        insert(into: context, title: "Pan-Seared Steak", servings: 2, minutes: 25, createdAt: base,
               ingredients: [
                   ("2", "", "ribeye steaks, 1 inch thick"),
                   ("1", "tbsp", "neutral oil"),
                   ("2", "tbsp", "butter"),
                   ("3", "cloves", "garlic, smashed"),
                   ("2", "sprigs", "thyme"),
                   ("1 1/2", "tsp", "kosher salt"),
                   ("1/2", "tsp", "black pepper")
               ],
               steps: [
                   ("Pat the steaks dry and season both sides with salt and pepper.", nil),
                   ("Heat the oil in a cast-iron pan over high heat until it just smokes.", 3),
                   ("Lay the steaks in the pan and sear without moving them.", 3),
                   ("Flip. Add butter, garlic and thyme, and baste with the foaming butter.", 3),
                   ("Move the steaks to a board and let them rest.", 5),
                   ("Slice against the grain and serve.", nil)
               ])

        insert(into: context, title: "Garlic Butter Pasta", servings: 2, minutes: 20, createdAt: base.addingTimeInterval(1),
               ingredients: [
                   ("200", "g", "spaghetti"),
                   ("1 1/2", "cup", "grated parmesan"),
                   ("3", "tbsp", "butter"),
                   ("4", "cloves", "garlic, sliced"),
                   ("1/4", "cup", "chopped parsley"),
                   ("", "", "salt, to taste")
               ],
               steps: [
                   ("Bring a large pot of salted water to a boil.", 8),
                   ("Cook the spaghetti until al dente. Save a cup of pasta water.", 10),
                   ("Melt the butter in a pan and gently cook the garlic until golden.", 2),
                   ("Toss the pasta in the pan with a splash of pasta water.", nil),
                   ("Stir in parmesan and parsley, season, and serve right away.", nil)
               ])

        insert(into: context, title: "Simple No-Knead Bread", servings: 8, minutes: 1200, createdAt: base.addingTimeInterval(2),
               ingredients: [
                   ("3", "cup", "all-purpose flour"),
                   ("1 1/2", "tsp", "salt"),
                   ("1/2", "tsp", "instant yeast"),
                   ("1 1/2", "cup", "warm water")
               ],
               steps: [
                   ("Mix flour, salt and yeast in a big bowl.", nil),
                   ("Add the water and stir into a shaggy, sticky dough.", nil),
                   ("Cover and let rise at room temperature for 12–18 hours.", nil),
                   ("Shape into a ball on a floured surface and rest while the oven heats.", 30),
                   ("Preheat the oven with a Dutch oven inside to 230°C / 450°F.", 30),
                   ("Bake covered.", 30),
                   ("Uncover and bake until deep brown.", 15),
                   ("Cool on a rack before slicing.", 60)
               ])
        try? context.save()
    }

    private static func insert(into context: ModelContext, title: String, servings: Int, minutes: Int, createdAt: Date,
                               ingredients: [(String, String, String)], steps: [(String, Int?)]) {
        let recipe = Recipe(title: title, servings: servings, totalMinutes: minutes, createdAt: createdAt)
        context.insert(recipe)
        recipe.ingredients = ingredients.enumerated().map { i, item in
            Ingredient(amountText: item.0, unit: item.1, name: item.2, order: i)
        }
        recipe.steps = steps.enumerated().map { i, item in
            RecipeStep(text: item.0, timerMinutes: item.1, order: i)
        }
    }
}
