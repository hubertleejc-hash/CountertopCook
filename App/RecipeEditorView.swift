import SwiftUI
import SwiftData

/// The recipe form. Three uses: typing a recipe in by hand, editing a saved one, and reviewing
/// an import before it is saved (every import stops here first, so it can be corrected).
struct RecipeEditorView: View {
    let recipe: Recipe?
    /// True when this is the review of an import.
    private let reviewing: Bool
    private let onSaved: ((Recipe) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeDraft

    init(recipe: Recipe?) {
        self.recipe = recipe
        reviewing = false
        onSaved = nil
        _draft = State(initialValue: recipe.map(RecipeDraft.init(recipe:)) ?? RecipeDraft())
    }

    /// Review an import: `draft` holds only what the source gave. Nothing is saved until Save.
    init(review draft: RecipeDraft, onSaved: @escaping (Recipe) -> Void) {
        recipe = nil
        reviewing = true
        self.onSaved = onSaved
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                if reviewing {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Check this against the original before saving.", systemImage: "checkmark.seal")
                                .font(Theme.body(17, bold: true))
                                .foregroundStyle(Theme.navy)
                            Text("Nothing was guessed. Anything the source didn't give is left blank for you to fill in or leave.")
                                .font(Theme.body(15, relativeTo: .subheadline))
                                .foregroundStyle(.secondary)
                            if !draft.notInSource.isEmpty {
                                Text("Not in the source: \(draft.notInSource.joined(separator: ", ")).")
                                    .font(Theme.body(15, bold: true, relativeTo: .subheadline))
                                    .foregroundStyle(Theme.label)
                                    .accessibilityIdentifier("reviewMissing")
                            }
                            if let source = draft.sourceName, !source.isEmpty {
                                Text("Source: \(source)")
                                    .font(Theme.body(15, relativeTo: .subheadline))
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("reviewSource")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("reviewNotice")
                    }
                    if let reference = draft.referenceText, !reference.isEmpty {
                        Section("From the source") {
                            Text("No ingredient or step list could be read from this. Here is its text to work from:")
                                .font(Theme.body(15, relativeTo: .subheadline))
                                .foregroundStyle(.secondary)
                            ScrollView {
                                Text(reference)
                                    .font(Theme.body(15, relativeTo: .subheadline))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 220)
                            .accessibilityIdentifier("reviewReference")
                        }
                    }
                }

                Section("Recipe") {
                    TextField("Title", text: $draft.title)
                        .font(Theme.title(20))
                        .accessibilityIdentifier("recipeTitle")
                    Picker("Category", selection: $draft.category) {
                        ForEach(RecipeCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("recipeCategory")
                    Stepper("Servings: \(draft.servings)", value: $draft.servings, in: 1...99)
                        .accessibilityIdentifier("recipeServings")
                    Stepper(draft.totalMinutes == 0 ? "Total time: not given" : "Total time: \(formatMinutes(draft.totalMinutes))",
                            value: $draft.totalMinutes, in: 0...2880, step: 5)
                        .accessibilityIdentifier("recipeTotalTime")
                }

                Section {
                    ForEach($draft.ingredients) { $item in
                        let index = draft.ingredients.firstIndex { $0.id == item.id } ?? 0
                        HStack {
                            TextField("1 1/2", text: $item.amount)
                                .frame(width: 64)
                                .accessibilityIdentifier("ingredientAmount_\(index)")
                            TextField("unit", text: $item.unit)
                                .frame(width: 56)
                                .textInputAutocapitalization(.never)
                                .accessibilityIdentifier("ingredientUnit_\(index)")
                            TextField("Ingredient", text: $item.name)
                                .accessibilityIdentifier("ingredientName_\(index)")
                        }
                    }
                    .onDelete { draft.ingredients.remove(atOffsets: $0) }
                    .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        draft.ingredients.append(IngredientDraft())
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle").foregroundStyle(Theme.navy)
                    }
                    .accessibilityIdentifier("addIngredient")
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Amounts can be fractions like 1 1/2 or 3/4.")
                }

                Section("Steps") {
                    ForEach($draft.steps) { $step in
                        let index = draft.steps.firstIndex { $0.id == step.id } ?? 0
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Step \(index + 1)").font(.caption).foregroundStyle(.secondary)
                            TextField("What to do", text: $step.text, axis: .vertical)
                                .lineLimit(2...6)
                                .accessibilityIdentifier("stepText_\(index)")
                            Stepper(step.timerMinutes == 0 ? "No timer" : "Timer: \(step.timerMinutes) min",
                                    value: $step.timerMinutes, in: 0...1440)
                                .accessibilityIdentifier("stepTimer_\(index)")
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        draft.steps.append(StepDraft())
                    } label: {
                        Label("Add Step", systemImage: "plus.circle").foregroundStyle(Theme.navy)
                    }
                    .accessibilityIdentifier("addStep")
                }

                // Also at the bottom: on some devices the top bar scrolls away with a long form.
                Section {
                    Button {
                        save()
                    } label: {
                        Text("Save Recipe").font(Theme.body(17, bold: true)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("saveRecipeBottom")
                }
            }
            .warmList()
            .navigationTitle(reviewing ? "Review Import" : (recipe == nil ? "New Recipe" : "Edit Recipe"))
            .font(Theme.body())
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("saveRecipe")
                }
            }
        }
    }

    private func save() {
        let saved = draft.save(into: recipe, context: context)
        dismiss()
        onSaved?(saved)
    }
}
