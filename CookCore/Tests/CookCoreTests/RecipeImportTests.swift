import Foundation
import Testing
@testable import CookCore

/// The same pages the UI test imports over HTTP (ci/fixtures).
private func fixture(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ci/fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct RecipeImportTests {
    @Test func fixturePage() throws {
        let recipe = try RecipeImporter.parse(html: try fixture("recipe.html"),
                                              url: URL(string: "http://127.0.0.1:8765/recipe.html"))
        #expect(recipe.title == "Weeknight Lemon Rice")
        #expect(recipe.servings == 4)
        #expect(recipe.totalMinutes == 25)
        #expect(recipe.siteName == "Test Kitchen")
        #expect(recipe.ingredients == [
            .init(amount: "1 1/2", unit: "cup", name: "long-grain rice"),
            .init(amount: "2", unit: "tbsp", name: "butter"),
            .init(amount: "1", unit: "", name: "lemon, zested and juiced"),
            .init(amount: "500", unit: "ml", name: "vegetable stock"),
            .init(amount: "½", unit: "tsp", name: "salt"),
            .init(amount: "", unit: "", name: "Fresh parsley, to serve"),
        ])
        #expect(recipe.steps == [
            "Rinse the rice until the water runs clear.",
            "Melt the butter in a pot and toast the rice for 2 minutes.",
            "Add the stock, lemon zest and salt. Cover and simmer for 15 minutes.",
            "Stir in the lemon juice, top with parsley & serve.",
        ])
        // Only recipe fields: no description or story text.
        let everything = ([recipe.title] + recipe.steps + recipe.ingredients.map(\.name)).joined(separator: " ")
        #expect(!everything.contains("MUST NOT BE IMPORTED"))
    }

    @Test func cuisineComesFromRecipeCuisine() throws {
        let html = """
        <html><head><script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Ratatouille","recipeCuisine":["French","Provençal"],
         "recipeIngredient":["1 aubergine"],"recipeInstructions":[{"@type":"HowToStep","text":"Slice."}]}
        </script></head><body></body></html>
        """
        let recipe = try RecipeImporter.parse(html: html, url: URL(string: "https://example.com/r"))
        #expect(recipe.cuisine == "French")
        let fixtureRecipe = try RecipeImporter.parse(html: try fixture("recipe.html"), url: nil)
        #expect(fixtureRecipe.cuisine == nil)
    }

    @Test func pageWithoutRecipeIsAnError() throws {
        #expect(throws: RecipeImportError.noRecipeData) {
            try RecipeImporter.parse(html: try fixture("no-recipe.html"), url: nil)
        }
        #expect(throws: RecipeImportError.noRecipeData) {
            try RecipeImporter.parse(html: "<html><body>2 cups flour. Mix. Bake.</body></html>", url: nil)
        }
    }

    @Test func recipeWithoutStepsIsAnError() {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"Toast","recipeIngredient":["1 slice bread"]}</script>
        """
        #expect(throws: RecipeImportError.missing("steps")) { try RecipeImporter.parse(html: html, url: nil) }
    }

    @Test func plainInstructionsAndFallbacks() throws {
        let html = """
        <html><head><script type='application/ld+json'>
        [{"@type":"Organization","name":"Org"},
         {"@context":"http://schema.org","@type":"http://schema.org/Recipe","name":"Tea &amp; Toast",
          "recipeYield":2,"cookTime":"PT1H","prepTime":"PT10M",
          "recipeIngredient":"2 slices bread",
          "recipeInstructions":"<p>Toast the bread.</p><p>Brew the tea.</p>",
          "publisher":{"@type":"Organization","name":"Breakfast Co"}}]
        </script></head></html>
        """
        let recipe = try RecipeImporter.parse(html: html, url: URL(string: "https://www.example.com/tea"))
        #expect(recipe.title == "Tea & Toast")
        #expect(recipe.servings == 2)
        #expect(recipe.totalMinutes == 70)
        #expect(recipe.steps == ["Toast the bread.", "Brew the tea."])
        #expect(recipe.ingredients == [.init(amount: "2", unit: "slices", name: "bread")])
        #expect(recipe.siteName == "Breakfast Co")
    }

    @Test func hostIsTheLastFallbackForSiteName() throws {
        let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"A","recipeIngredient":["salt"],"recipeInstructions":["Do it."]}</script>"#
        let recipe = try RecipeImporter.parse(html: html, url: URL(string: "https://www.example.org/a"))
        #expect(recipe.siteName == "example.org")
        #expect(recipe.servings == nil)
        #expect(recipe.totalMinutes == nil)
    }

    @Test func durations() {
        #expect(RecipeImporter.minutes(isoDuration: "PT25M") == 25)
        #expect(RecipeImporter.minutes(isoDuration: "PT1H30M") == 90)
        #expect(RecipeImporter.minutes(isoDuration: "P1DT2H") == 1560)
        #expect(RecipeImporter.minutes(isoDuration: "PT90S") == 2)
        #expect(RecipeImporter.minutes(isoDuration: "20 minutes") == nil)
        #expect(RecipeImporter.minutes(isoDuration: nil) == nil)
    }

    @Test func ingredientLines() {
        #expect(RecipeImporter.splitIngredient("200g spaghetti") == .init(amount: "200", unit: "g", name: "spaghetti"))
        #expect(RecipeImporter.splitIngredient("1½ cups of milk") == .init(amount: "1½", unit: "cup", name: "milk"))
        #expect(RecipeImporter.splitIngredient("2-3 cloves garlic") == .init(amount: "2-3", unit: "cloves", name: "garlic"))
        #expect(RecipeImporter.splitIngredient("8 fl oz cream") == .init(amount: "8", unit: "fl oz", name: "cream"))
        #expect(RecipeImporter.splitIngredient("3 eggs") == .init(amount: "3", unit: "", name: "eggs"))
        #expect(RecipeImporter.splitIngredient("salt and pepper") == .init(amount: "", unit: "", name: "salt and pepper"))
    }
}
