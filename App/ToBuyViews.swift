import SwiftUI
import SwiftData
import CookCore

/// From a recipe: tick what you already have; the rest goes on the to-buy list.
struct ToBuyPickerView: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Positions (in the recipe's ingredient order) of what is already in the kitchen.
    @State private var have: Set<Int> = []

    private var ingredients: [Ingredient] { recipe.sortedIngredients }
    private var needed: [ShoppingLine] {
        ingredients.enumerated().filter { !have.contains($0.offset) }
            .map { ShoppingLine(amount: $0.element.amountText, unit: $0.element.unit, name: $0.element.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, item in
                        let has = have.contains(index)
                        Button {
                            if has { have.remove(index) } else { have.insert(index) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: has ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(has ? Cuisine.italian.accent : Color.secondary)
                                    .accessibilityHidden(true)
                                Text(ingredientLine(item, servingsFrom: recipe.servings, to: recipe.servings))
                                    .strikethrough(has)
                                    .foregroundStyle(has ? Color.secondary : Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(has ? "have it" : "need it")
                        .accessibilityIdentifier("have_\(index)")
                    }
                } header: {
                    Text("Tick what you already have")
                } footer: {
                    Text("Everything left unticked goes on your to-buy list. The same item from another recipe is added to the same line.")
                }
                Section {
                    Button {
                        ToBuy.add(needed, from: recipe.title, context: context)
                        dismiss()
                    } label: {
                        Text(needed.isEmpty ? "Nothing to buy" : (needed.count == 1 ? "Add 1 item to the list" : "Add \(needed.count) items to the list"))
                            .font(Theme.body(17, bold: true))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(needed.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("confirmToBuy")
                }
            }
            .font(Theme.body())
            .warmList()
            .navigationTitle("To Buy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The to-buy list: what's still to buy on top, checked off as you shop; bought items below.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]

    private var waiting: [ShoppingItem] { items.filter { !$0.isBought } }
    private var bought: [ShoppingItem] { items.filter(\.isBought) }

    var body: some View {
        List {
            if items.isEmpty {
                Section {
                    Text("Nothing to buy yet. Open a recipe and tap “Add to the to-buy list”.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("toBuyEmpty")
                }
            }
            if !waiting.isEmpty {
                Section {
                    ForEach(waiting) { row($0) }
                        .onDelete { offsets in delete(offsets.map { waiting[$0] }) }
                } header: {
                    Text(waiting.count == 1 ? "To buy · 1 item" : "To buy · \(waiting.count) items")
                        .accessibilityIdentifier("toBuyCount")
                }
            }
            if !bought.isEmpty {
                Section {
                    ForEach(bought) { row($0) }
                        .onDelete { offsets in delete(offsets.map { bought[$0] }) }
                    Button("Clear bought items", role: .destructive) { delete(bought) }
                        .accessibilityIdentifier("clearBought")
                } header: {
                    Text("Bought")
                }
            }
        }
        .font(Theme.body())
        .warmList()
        .navigationTitle("To Buy")
        .toolbar {
            if !items.isEmpty {
                Button("Clear all", role: .destructive) { delete(items) }
                    .accessibilityIdentifier("clearToBuy")
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            item.isBought.toggle()
            try? context.save()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isBought ? Cuisine.italian.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    (Text(item.amountText.isEmpty ? "" : item.amountText + " ").font(Theme.body(17, bold: true).monospacedDigit())
                     + Text([item.unit, item.name].filter { !$0.isEmpty }.joined(separator: " ")))
                        .strikethrough(item.isBought)
                        .foregroundStyle(item.isBought ? Color.secondary : Theme.ink)
                    if !item.recipes.isEmpty {
                        Text(item.recipes)
                            .font(Theme.body(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.line.text)
        .accessibilityValue(item.isBought ? "bought" : "to buy")
        .accessibilityIdentifier("toBuy_\(ShoppingMerge.key(item.name))")
    }

    private func delete(_ list: [ShoppingItem]) {
        list.forEach(context.delete)
        try? context.save()
    }
}
