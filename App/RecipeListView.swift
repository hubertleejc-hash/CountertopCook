import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @State private var showingNewRecipe = false
    @State private var path: [Recipe] = []
    @State private var link = ""
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                importSection
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

    /// Paste a recipe page's link; only its schema.org Recipe data is imported.
    private var importSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Paste a recipe link", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(startImport)
                    .disabled(importing)
                    .accessibilityIdentifier("importLink")
                if importing {
                    ProgressView().accessibilityIdentifier("importProgress")
                } else {
                    Button("Import", action: startImport)
                        .buttonStyle(.borderedProminent)
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("importButton")
                }
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("importError")
            }
        } header: {
            Text("Import from link")
        }
    }

    private func startImport() {
        guard !importing, !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        importing = true
        importError = nil
        Task {
            do {
                let recipe = try await LinkImport.importRecipe(from: link, into: context)
                link = ""
                path.append(recipe)
            } catch {
                importError = error.localizedDescription
            }
            importing = false
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
            if let source = recipe.sourceURL, let url = URL(string: source) {
                Section {
                    Link(destination: url) {
                        Label("Source: \(recipe.sourceName ?? url.host ?? source)", systemImage: "link")
                    }
                    .accessibilityIdentifier("recipeSource")
                }
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
