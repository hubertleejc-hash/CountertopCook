import SwiftUI
import SwiftData

struct RecipeEditorView: View {
    let recipe: Recipe?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeDraft

    init(recipe: Recipe?) {
        self.recipe = recipe
        _draft = State(initialValue: recipe.map(RecipeDraft.init(recipe:)) ?? RecipeDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Title", text: $draft.title)
                        .font(.title3)
                        .accessibilityIdentifier("recipeTitle")
                    Stepper("Servings: \(draft.servings)", value: $draft.servings, in: 1...99)
                    Stepper("Total time: \(formatMinutes(draft.totalMinutes))", value: $draft.totalMinutes, in: 0...2880, step: 5)
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
                        Label("Add Ingredient", systemImage: "plus.circle")
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
                                    value: $step.timerMinutes, in: 0...600)
                                .accessibilityIdentifier("stepTimer_\(index)")
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        draft.steps.append(StepDraft())
                    } label: {
                        Label("Add Step", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addStep")
                }

                // Also at the bottom: on some devices the top bar scrolls away with a long form.
                Section {
                    Button {
                        save()
                    } label: {
                        Text("Save Recipe").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canSave)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("saveRecipeBottom")
                }
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
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
        draft.save(into: recipe, context: context)
        dismiss()
    }
}
