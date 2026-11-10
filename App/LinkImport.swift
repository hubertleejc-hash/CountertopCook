import Foundation
import SwiftData
import CookCore

/// Imports a recipe from a pasted link: fetches the page and reads only its schema.org Recipe
/// JSON-LD (title, servings, ingredients, steps, times). Pages without it are refused, never guessed.
enum LinkImport {
    enum Failure: LocalizedError {
        case badLink
        case network(String)
        case notFound(Int)

        var errorDescription: String? {
            switch self {
            case .badLink: return "That doesn't look like a web link. Paste the full address of a recipe page."
            case .network(let reason): return "Couldn't load the page: \(reason)"
            case .notFound(let status): return "Couldn't load the page (HTTP \(status))."
            }
        }
    }

    /// Fetches, parses and saves the recipe; returns it for showing.
    @MainActor
    static func importRecipe(from text: String, into context: ModelContext) async throws -> Recipe {
        let url = try link(from: text)
        var request = URLRequest(url: url, timeoutInterval: 20)
        // Some recipe sites refuse requests that don't look like a browser.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.notFound(http.statusCode)
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let page = response.url ?? url
        let imported = try RecipeImporter.parse(html: html, url: page)
        return save(imported, from: page, into: context)
    }

    static func link(from text: String) throws -> URL {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty
        else { throw Failure.badLink }
        return url
    }

    @MainActor
    private static func save(_ imported: ImportedRecipe, from url: URL, into context: ModelContext) -> Recipe {
        // Servings and time aren't always published; fall back to the editor's defaults.
        let recipe = Recipe(title: imported.title, servings: imported.servings ?? RecipeDraft().servings,
                            totalMinutes: imported.totalMinutes ?? 0)
        recipe.sourceURL = url.absoluteString
        recipe.sourceName = imported.siteName
        context.insert(recipe)
        recipe.ingredients = imported.ingredients.enumerated().map { index, item in
            Ingredient(amountText: item.amount, unit: item.unit, name: item.name, order: index)
        }
        recipe.steps = imported.steps.enumerated().map { index, text in
            RecipeStep(text: text, timerMinutes: nil, order: index)
        }
        try? context.save()
        return recipe
    }
}
