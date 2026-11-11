import SwiftUI
import SwiftData
import CookCore

/// The library: every saved recipe, with import at the top (a link, pasted text, or a share
/// from another app), then search, the Food / Drinks / Desserts shelves, favourites and sorting.
/// Typing a recipe in by hand is still there, under +, as the fallback.
struct RecipeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query private var shopping: [ShoppingItem]
    @State private var path: [Recipe] = []
    @State private var link = ""
    @State private var importing = false
    @State private var importError: String?
    @State private var sheet: LibrarySheet?
    @State private var showingToBuy = false
    @State private var search = ""
    @State private var category: RecipeCategory?
    @State private var favouritesOnly = false
    @State private var sort = LibrarySort.dateAdded

    enum LibrarySort: String, CaseIterable, Identifiable {
        case dateAdded = "Date added", newest = "Newest first", title = "A to Z", quickest = "Quickest first"
        var id: String { rawValue }
    }

    enum LibrarySheet: Identifiable {
        case manual
        case paste(String)
        case review(RecipeDraft)

        var id: String {
            switch self {
            case .manual: return "manual"
            case .paste: return "paste"
            case .review: return "review"
            }
        }
    }

    private var shown: [Recipe] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        var list = recipes.filter { recipe in
            (category == nil || recipe.categoryKind == category)
                && (!favouritesOnly || recipe.isFavorite)
                && (query.isEmpty || recipe.title.lowercased().contains(query)
                    || recipe.ingredients.contains { $0.name.lowercased().contains(query) })
        }
        switch sort {
        case .dateAdded: break
        case .newest: list.reverse()
        case .title: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        // Recipes with no time given go last, not first.
        case .quickest: list.sort { ($0.totalMinutes == 0 ? Int.max : $0.totalMinutes) < ($1.totalMinutes == 0 ? Int.max : $1.totalMinutes) }
        }
        return list
    }

    private var toBuyCount: Int { shopping.filter { !$0.isBought }.count }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 14) {
                        HearthLogo().frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hearth").font(Theme.body(24, bold: true, relativeTo: .title2))
                            Text("Recipes, timers and your to-buy list")
                                .font(Theme.body(14, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("libraryHeader")
                }
                importSection
                filterSection
                Section {
                    ForEach(shown) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeRow(recipe: recipe)
                        }
                        .accessibilityIdentifier("recipeRow_\(recipe.title)")
                        .swipeActions(edge: .leading) {
                            Button {
                                recipe.isFavorite.toggle()
                                try? context.save()
                            } label: {
                                Label(recipe.isFavorite ? "Unfavourite" : "Favourite",
                                      systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                            }
                            .tint(Theme.accent)
                        }
                    }
                    .onDelete { offsets in
                        let list = shown
                        offsets.map { list[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                    if shown.isEmpty {
                        Text(recipes.isEmpty ? "No recipes yet. Import one above, or tap + to type one in."
                                             : "No recipes match. Clear the search or the filters.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("libraryEmpty")
                    }
                } header: {
                    Text(shown.count == 1 ? "1 recipe" : "\(shown.count) recipes")
                        .accessibilityIdentifier("libraryCount")
                }
            }
            .warmList()
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(isPresented: $showingToBuy) { ShoppingListView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingToBuy = true
                    } label: {
                        Label(toBuyCount == 0 ? "To buy" : "To buy, \(toBuyCount)", systemImage: toBuyCount == 0 ? "cart" : "cart.fill")
                    }
                    .accessibilityIdentifier("openToBuy")
                    Menu {
                        Button {
                            sheet = .paste("")
                        } label: {
                            Label("Paste recipe text", systemImage: "doc.on.clipboard")
                        }
                        .accessibilityIdentifier("menuPasteText")
                        Button {
                            sheet = .manual
                        } label: {
                            Label("Type it in by hand", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("addRecipe")
                    } label: {
                        Label("Add Recipe", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addMenu")
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .manual:
                    RecipeEditorView(recipe: nil)
                case .paste(let text):
                    PasteTextView(initialText: text) { open($0) }
                case .review(let draft):
                    RecipeEditorView(review: draft) { open($0) }
                }
            }
        }
        .font(Theme.body())
        .onOpenURL(perform: handleIncoming)
    }

    private func open(_ recipe: Recipe) {
        path.append(recipe)
    }

    /// Paste a recipe page's link or a YouTube link; or paste the recipe's text.
    private var importSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Paste a recipe or YouTube link", text: $link)
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
            Button {
                sheet = .paste("")
            } label: {
                Label("Paste recipe text", systemImage: "doc.on.clipboard")
                    .foregroundStyle(Theme.navy)
            }
            .accessibilityIdentifier("pasteTextButton")
            if let importError {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    Text(importError)
                }
                .font(Theme.body(13, relativeTo: .footnote))
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("importError")
            }
        } header: {
            Text("Import")
        } footer: {
            Text("You review every import before it is saved. From YouTube or any other app, use Share and choose Hearth.")
        }
    }

    private var filterSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search recipes or ingredients", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("librarySearch")
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("librarySearchClear")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", selected: category == nil && !favouritesOnly, id: "category_All") {
                        category = nil
                        favouritesOnly = false
                    }
                    ForEach(RecipeCategory.allCases) { item in
                        filterChip(item.rawValue, symbol: item.symbol, selected: category == item, id: "category_\(item.rawValue)") {
                            category = category == item ? nil : item
                        }
                    }
                    filterChip("Favourites", symbol: favouritesOnly ? "heart.fill" : "heart", selected: favouritesOnly,
                               id: "favouritesFilter") {
                        favouritesOnly.toggle()
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
            Picker("Sort", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("sortPicker")
        }
    }

    private func filterChip(_ title: String, symbol: String? = nil, selected: Bool, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.footnote) }
                Text(title).font(Theme.body(15, bold: true, relativeTo: .subheadline))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .background(selected ? Theme.pill : Theme.beige, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityValue(selected ? "selected" : "")
        .accessibilityIdentifier(id)
    }

    private func startImport() {
        guard !importing, !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        importing = true
        importError = nil
        Task {
            do {
                let draft = try await LinkImport.draft(from: link)
                link = ""
                sheet = .review(draft)
            } catch {
                importError = error.localizedDescription
            }
            importing = false
        }
    }

    /// A share from another app: hearth://import?url=… or ?text=… (see ShareExtension).
    private func handleIncoming(_ url: URL) {
        guard url.scheme == "hearth", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        path = []
        if let address = items.first(where: { $0.name == "url" })?.value, !address.isEmpty {
            link = address
            startImport()
        } else if let text = items.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            // Shared text that is really a link ("Watch this https://youtu.be/…") is fetched;
            // anything else goes to the paste screen, ready to read.
            if text.count < 400, text.range(of: #"https?://\S+"#, options: .regularExpression) != nil {
                link = text
                startImport()
            } else {
                sheet = .paste(text)
            }
        }
    }
}

/// One recipe in the library: title in Lora, then servings, time and steps, with the heart and
/// the cuisine accent when it has them.
private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(recipe.title).font(Theme.title(18))
                if recipe.isFavorite {
                    Image(systemName: "heart.fill").font(.footnote).foregroundStyle(Theme.accent)
                        .accessibilityLabel("Favourite")
                }
            }
            Text(summary)
                .font(Theme.body(15, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            if let cuisine = recipe.cuisineKind {
                CuisineBadge(cuisine: cuisine, size: 12)
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        var parts = [recipe.categoryKind.rawValue, "\(recipe.servings) servings"]
        if recipe.totalMinutes > 0 { parts.append(formatMinutes(recipe.totalMinutes)) }
        parts.append("\(recipe.steps.count) steps")
        return parts.joined(separator: " · ")
    }
}

/// Paste a recipe's text; Hearth reads the ingredient and step lists out of it and shows the
/// review screen in the same sheet.
struct PasteTextView: View {
    let onSaved: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var draft: RecipeDraft?

    init(initialText: String, onSaved: @escaping (Recipe) -> Void) {
        self.onSaved = onSaved
        _text = State(initialValue: initialText)
    }

    var body: some View {
        if let draft {
            RecipeEditorView(review: draft, onSaved: onSaved)
        } else {
            NavigationStack {
                Form {
                    Section {
                        TextEditor(text: $text)
                            // Pasted recipes shouldn't be "corrected": 1/2 stays 1/2.
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(minHeight: 240)
                            .accessibilityIdentifier("pasteTextEditor")
                    } header: {
                        Text("Recipe text")
                    } footer: {
                        Text("Paste the whole recipe. Hearth looks for an Ingredients list and a Method or Instructions list. It never fills in an amount or a time the text doesn't give.")
                    }
                    Section {
                        Button {
                            draft = LinkImport.draft(fromText: text)
                        } label: {
                            Text("Read recipe").font(Theme.body(17, bold: true)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("pasteTextRead")
                    }
                }
                .warmList()
                .navigationTitle("Paste Text")
                .navigationBarTitleDisplayMode(.inline)
                .font(Theme.body())
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
                }
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
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var cooking = false
    @State private var pickingToBuy = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(Theme.title(28))
                        .accessibilityIdentifier("recipeTitleHeader")
                    HStack(spacing: 10) {
                        Label(recipe.categoryKind.rawValue, systemImage: recipe.categoryKind.symbol)
                            .font(Theme.body(15, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                        if let cuisine = recipe.cuisineKind {
                            CuisineBadge(cuisine: cuisine, size: 14)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Section {
                Button {
                    cooking = true
                } label: {
                    Label("Start Cooking", systemImage: "frying.pan")
                        .font(Theme.body(20, bold: true, relativeTo: .title3))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("startCooking")
            }
            Section {
                Button {
                    pickingToBuy = true
                } label: {
                    Label("Add to the to-buy list", systemImage: "cart.badge.plus")
                        .foregroundStyle(Theme.navy)
                }
                .disabled(recipe.ingredients.isEmpty)
                .accessibilityIdentifier("addToBuy")
            }
            if let source = recipe.sourceURL, let url = URL(string: source) {
                Section {
                    Link(destination: url) {
                        Label("Source: \(recipe.sourceName ?? url.host ?? source)", systemImage: "link")
                            .foregroundStyle(Theme.navy)
                    }
                    .accessibilityIdentifier("recipeSource")
                }
            } else if let source = recipe.sourceName, !source.isEmpty {
                Section {
                    Label("Source: \(source)", systemImage: "doc.text")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Source: \(source)")
                        .accessibilityIdentifier("recipeSource")
                }
            }
            Section {
                LabeledContent("Servings", value: "\(recipe.servings)")
                LabeledContent("Total time", value: recipe.totalMinutes > 0 ? formatMinutes(recipe.totalMinutes) : "Not given")
            }
            Section("Ingredients") {
                ForEach(recipe.sortedIngredients) { item in
                    (Text(ingredientAmount(item, servingsFrom: recipe.servings, to: recipe.servings)).font(Theme.body(17, bold: true).monospacedDigit())
                     + Text(ingredientRest(item)))
                }
            }
            Section("Steps") {
                ForEach(Array(recipe.sortedSteps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(step.text)")
                        if let minutes = step.timerMinutes, minutes > 0 {
                            Label("\(minutes) min timer", systemImage: "timer")
                                .font(Theme.body(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("stepTimerLabel_\(index)")
                        }
                    }
                }
            }
        }
        .font(Theme.body())
        .warmList()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                recipe.isFavorite.toggle()
                try? context.save()
            } label: {
                Label(recipe.isFavorite ? "Remove from favourites" : "Add to favourites",
                      systemImage: recipe.isFavorite ? "heart.fill" : "heart")
            }
            .accessibilityValue(recipe.isFavorite ? "favourite" : "not favourite")
            .accessibilityIdentifier("favouriteToggle")
            Button("Edit") { editing = true }
                .accessibilityIdentifier("editRecipe")
        }
        .sheet(isPresented: $editing) {
            RecipeEditorView(recipe: recipe)
        }
        .sheet(isPresented: $pickingToBuy) {
            ToBuyPickerView(recipe: recipe)
        }
        .fullScreenCover(isPresented: $cooking) {
            CookModeView(recipe: recipe)
        }
    }
}
