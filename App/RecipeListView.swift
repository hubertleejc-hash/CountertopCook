import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @State private var showingNewRecipe = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(recipes) { recipe in
                    NavigationLink(value: recipe) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title).font(.headline)
                            Text("\(recipe.servings) servings · \(formatMinutes(recipe.totalMinutes)) · \(recipe.steps.count) steps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("recipeRow_\(recipe.title)")
                }
                .onDelete { offsets in
                    offsets.map { recipes[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
            .overlay {
                if recipes.isEmpty {
                    ContentUnavailableView("No recipes yet", systemImage: "fork.knife",
                                           description: Text("Tap + to add your first recipe."))
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewRecipe = true
                    } label: {
                        Label("Add Recipe", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addRecipe")
                }
            }
            .sheet(isPresented: $showingNewRecipe) {
                RecipeEditorView(recipe: nil)
            }
        }
    }
}

func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h) h" : "\(h) h \(m) min"
}

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @State private var editing = false
    @State private var cooking = false

    var body: some View {
        List {
            Section {
                Button {
                    cooking = true
                } label: {
                    Label("Start Cooking", systemImage: "frying.pan")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("startCooking")
            }
            Section {
                LabeledContent("Servings", value: "\(recipe.servings)")
                LabeledContent("Total time", value: formatMinutes(recipe.totalMinutes))
            }
            Section("Ingredients") {
                ForEach(recipe.sortedIngredients) { item in
                    Text(ingredientLine(item, servingsFrom: recipe.servings, to: recipe.servings))
                }
            }
            Section("Steps") {
                ForEach(Array(recipe.sortedSteps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(step.text)")
                        if let minutes = step.timerMinutes, minutes > 0 {
                            Label("\(minutes) min timer", systemImage: "timer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .toolbar {
            Button("Edit") { editing = true }
                .accessibilityIdentifier("editRecipe")
        }
        .sheet(isPresented: $editing) {
            RecipeEditorView(recipe: recipe)
        }
        .fullScreenCover(isPresented: $cooking) {
            CookModeView(recipe: recipe)
        }
    }
}
