import Foundation
import SwiftData

/// The ten starter recipes, written for this app. They're ordinary recipes, so they can be
/// edited or deleted, and a deleted starter never comes back.
enum SeedData {
    /// Set by the first version, which shipped three starters.
    private static let seededKey = "didSeedStarterRecipes"
    /// How many starter batches this install has been given (1: the first three, 2: seven more).
    private static let versionKey = "starterRecipesVersion"
    static let titles = ["Pan-Seared Steak", "Garlic Butter Pasta", "Simple No-Knead Bread",
                         "Fluffy Scrambled Eggs", "Easy Tomato Soup", "Chicken and Veg Stir-Fry",
                         "Weekend Pancakes", "Sheet-Pan Roast Vegetables", "One-Pot Bean Chili",
                         "Lemon Herb Chicken Thighs"]

    static func seedIfNeeded(_ context: ModelContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        var version = defaults.integer(forKey: versionKey)
        if version == 0 && defaults.bool(forKey: seededKey) { version = 1 }
        if force { version = 0 }
        guard version < 2 else { return }
        defaults.set(true, forKey: seededKey)
        defaults.set(2, forKey: versionKey)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        if version < 1 { seedFirstThree(context, base: base) }
        if version < 2 { seedSevenMore(context, base: base) }
        try? context.save()
    }

    private static func seedFirstThree(_ context: ModelContext, base: Date) {
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
    }

    private static func seedSevenMore(_ context: ModelContext, base: Date) {
        insert(into: context, title: "Fluffy Scrambled Eggs", servings: 2, minutes: 10, createdAt: base.addingTimeInterval(3),
               ingredients: [
                   ("4", "", "eggs"),
                   ("2", "tbsp", "milk"),
                   ("1", "tbsp", "butter"),
                   ("1/4", "tsp", "salt"),
                   ("", "", "chives, to serve")
               ],
               steps: [
                   ("Whisk the eggs, milk and salt until no streaks of white are left.", nil),
                   ("Melt the butter in a non-stick pan over low heat.", 1),
                   ("Pour in the eggs and stir slowly with a spatula, scraping the bottom.", 3),
                   ("Take the pan off the heat while the eggs still look a little wet.", nil),
                   ("Scatter over the chives and serve on toast.", nil)
               ])

        insert(into: context, title: "Easy Tomato Soup", servings: 4, minutes: 35, createdAt: base.addingTimeInterval(4),
               ingredients: [
                   ("2", "tbsp", "olive oil"),
                   ("1", "", "onion, chopped"),
                   ("2", "cloves", "garlic, sliced"),
                   ("800", "g", "canned chopped tomatoes"),
                   ("2", "cup", "vegetable stock"),
                   ("1", "tsp", "sugar"),
                   ("1/4", "cup", "cream"),
                   ("", "", "salt and pepper, to taste")
               ],
               steps: [
                   ("Warm the oil in a pot and soften the onion.", 6),
                   ("Add the garlic and cook until it smells sweet.", 1),
                   ("Add the tomatoes, stock and sugar and bring to a simmer.", nil),
                   ("Simmer gently, stirring now and then.", 20),
                   ("Blend until smooth, stir in the cream and season to taste.", nil)
               ])

        insert(into: context, title: "Chicken and Veg Stir-Fry", servings: 2, minutes: 25, createdAt: base.addingTimeInterval(5),
               ingredients: [
                   ("300", "g", "chicken breast, thinly sliced"),
                   ("1", "tbsp", "neutral oil"),
                   ("1", "", "red pepper, sliced"),
                   ("1", "", "head broccoli, in small florets"),
                   ("2", "cloves", "garlic, chopped"),
                   ("1", "tbsp", "grated ginger"),
                   ("3", "tbsp", "soy sauce"),
                   ("1", "tbsp", "honey"),
                   ("", "", "cooked rice, to serve")
               ],
               steps: [
                   ("Mix the soy sauce and honey in a cup.", nil),
                   ("Heat the oil in a wok over high heat and cook the chicken until browned.", 5),
                   ("Add the broccoli and pepper and keep everything moving.", 4),
                   ("Add the garlic and ginger and cook briefly.", 1),
                   ("Pour in the sauce and toss until glossy.", 1),
                   ("Serve over rice.", nil)
               ])

        insert(into: context, title: "Weekend Pancakes", servings: 4, minutes: 25, createdAt: base.addingTimeInterval(6),
               ingredients: [
                   ("1 1/2", "cup", "all-purpose flour"),
                   ("2", "tsp", "baking powder"),
                   ("1", "tbsp", "sugar"),
                   ("1/4", "tsp", "salt"),
                   ("1 1/4", "cup", "milk"),
                   ("1", "", "egg"),
                   ("2", "tbsp", "melted butter")
               ],
               steps: [
                   ("Whisk the flour, baking powder, sugar and salt in a bowl.", nil),
                   ("Beat the milk, egg and melted butter in a jug, then stir into the flour until just combined.", nil),
                   ("Let the batter rest while the pan heats over medium heat.", 5),
                   ("Pour in a ladle of batter and cook until bubbles cover the top.", 2),
                   ("Flip and cook the other side until golden.", 1),
                   ("Repeat with the rest of the batter and serve warm.", nil)
               ])

        insert(into: context, title: "Sheet-Pan Roast Vegetables", servings: 4, minutes: 45, createdAt: base.addingTimeInterval(7),
               ingredients: [
                   ("2", "", "carrots, in chunks"),
                   ("1", "", "sweet potato, in chunks"),
                   ("1", "", "red onion, in wedges"),
                   ("1", "", "zucchini, in chunks"),
                   ("3", "tbsp", "olive oil"),
                   ("1", "tsp", "dried thyme"),
                   ("1", "tsp", "salt")
               ],
               steps: [
                   ("Heat the oven to 220°C / 425°F.", 10),
                   ("Toss the vegetables with the oil, thyme and salt on a large tray.", nil),
                   ("Spread them out in one layer so they roast instead of steam.", nil),
                   ("Roast, then turn everything over.", 20),
                   ("Roast again until browned at the edges.", 15)
               ])

        insert(into: context, title: "One-Pot Bean Chili", servings: 4, minutes: 45, createdAt: base.addingTimeInterval(8),
               ingredients: [
                   ("1", "tbsp", "olive oil"),
                   ("1", "", "onion, chopped"),
                   ("1", "", "green pepper, chopped"),
                   ("2", "cloves", "garlic, chopped"),
                   ("2", "tsp", "chili powder"),
                   ("1", "tsp", "ground cumin"),
                   ("400", "g", "canned chopped tomatoes"),
                   ("800", "g", "canned kidney beans, drained"),
                   ("1", "cup", "water"),
                   ("", "", "salt, to taste")
               ],
               steps: [
                   ("Warm the oil in a large pot and soften the onion and pepper.", 6),
                   ("Stir in the garlic and spices and cook until fragrant.", 1),
                   ("Add the tomatoes, beans and water and bring to a simmer.", nil),
                   ("Simmer uncovered, stirring now and then, until thick.", 25),
                   ("Season with salt and serve with rice or bread.", nil)
               ])

        insert(into: context, title: "Lemon Herb Chicken Thighs", servings: 4, minutes: 45, createdAt: base.addingTimeInterval(9),
               ingredients: [
                   ("8", "", "bone-in chicken thighs"),
                   ("2", "tbsp", "olive oil"),
                   ("1", "", "lemon, zested and sliced"),
                   ("3", "cloves", "garlic, grated"),
                   ("1", "tsp", "dried oregano"),
                   ("1", "tsp", "salt"),
                   ("1/2", "tsp", "black pepper")
               ],
               steps: [
                   ("Heat the oven to 200°C / 400°F.", 10),
                   ("Rub the chicken with the oil, lemon zest, garlic, oregano, salt and pepper.", nil),
                   ("Lay the thighs skin side up in a roasting dish with the lemon slices.", nil),
                   ("Roast until the skin is crisp and the juices run clear.", 35),
                   ("Rest for a few minutes before serving.", 5)
               ])
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
