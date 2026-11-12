import SwiftUI
import SwiftData
import CookCore

/// The library: a shelf of books, one per saved recipe. Search, the Food / Drinks / Desserts
/// shelves, favourites and sorting sit above it; adding a recipe (from a link, pasted text, or
/// typed in by hand) is under +. A share from another app arrives here too.
struct RecipeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Query private var shopping: [ShoppingItem]
    @State private var path: [Recipe] = []
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
        /// Import from a link; `start` fetches it straight away (a share from another app).
        case link(String, start: Bool)
        case paste(String)

        var id: String {
            switch self {
            case .manual: return "manual"
            case .link(let link, _): return "link-\(link)"
            case .paste: return "paste"
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    searchField
                    filterChips
                    HStack {
                        Text(shown.count == 1 ? "1 recipe" : "\(shown.count) recipes")
                            .font(Theme.body(14, relativeTo: .footnote))
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("libraryCount")
                        Spacer()
                        Picker("Sort", selection: $sort) {
                            ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.navy)
                        .accessibilityIdentifier("sortPicker")
                    }
                    if shown.isEmpty {
                        Text(recipes.isEmpty ? "No recipes yet. Tap + to import one or type one in."
                                             : "No recipes match. Clear the search or the filters.")
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                            .accessibilityIdentifier("libraryEmpty")
                    } else {
                        shelf
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .navigationDestination(isPresented: $showingToBuy) { ShoppingListView() }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingToBuy = true
                    } label: {
                        Label(toBuyCount == 0 ? "To buy" : "To buy, \(toBuyCount)", systemImage: toBuyCount == 0 ? "cart" : "cart.fill")
                    }
                    .accessibilityIdentifier("openToBuy")
                    Menu {
                        Button {
                            sheet = .link("", start: false)
                        } label: {
                            Label("Import from a link", systemImage: "link")
                        }
                        .accessibilityIdentifier("menuImportLink")
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
                case .link(let link, let start):
                    ImportLinkView(initialLink: link, startNow: start) { open($0) }
                case .paste(let text):
                    PasteTextView(initialText: text) { open($0) }
                }
            }
        }
        .font(Theme.body())
        .onOpenURL(perform: handleIncoming)
    }

    private func open(_ recipe: Recipe) {
        path.append(recipe)
    }

    /// The books, as many across as fit: two on a phone, more on an iPad or an open Duo.
    private var shelf: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 18, alignment: .top)],
                  spacing: 22) {
            ForEach(shown) { recipe in
                NavigationLink(value: recipe) {
                    BookCover(recipe: recipe)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recipeRow_\(recipe.title)")
                .contextMenu {
                    Button {
                        recipe.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Label(recipe.isFavorite ? "Unfavourite" : "Favourite",
                              systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                    }
                    Button(role: .destructive) {
                        context.delete(recipe)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Search recipes or ingredients", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("librarySearch")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("librarySearchClear")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Theme.card, in: Capsule())
    }

    private var filterChips: some View {
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
            .padding(.horizontal, 20)
        }
        // The chips scroll edge to edge, past the page margin.
        .padding(.horizontal, -20)
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

    /// A share from another app: hearth://import?url=… or ?text=… (see ShareExtension).
    private func handleIncoming(_ url: URL) {
        guard url.scheme == "hearth", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        path = []
        if let address = items.first(where: { $0.name == "url" })?.value, !address.isEmpty {
            sheet = .link(address, start: true)
        } else if let text = items.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            // Shared text that is really a link ("Watch this https://youtu.be/…") is fetched;
            // anything else goes to the paste screen, ready to read.
            if text.count < 400, text.range(of: #"https?://\S+"#, options: .regularExpression) != nil {
                sheet = .link(text, start: true)
            } else {
                sheet = .paste(text)
            }
        }
    }
}

/// One recipe on the shelf, as a book: its first photo for a cover, or a plain cloth cover in
/// the shelf's colour, with the title in Lora, a spine down the left and the cuisine's ribbon.
struct BookCover: View {
    let recipe: Recipe

    /// Cloth colours for books without a photo: navy for food, deep green for drinks, brick for
    /// desserts. All dark enough for white type.
    private var cloth: Color {
        switch recipe.categoryKind {
        case .food: return Theme.navy
        case .drinks: return Color(hex: 0x2F5D50)
        case .desserts: return Color(hex: 0x8C3B2A)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if recipe.totalMinutes > 0 { parts.append(formatMinutes(recipe.totalMinutes)) }
        parts.append(recipe.steps.count == 1 ? "1 step" : "\(recipe.steps.count) steps")
        return parts.joined(separator: " · ")
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 10, topTrailingRadius: 10)
    }

    var body: some View {
        cloth
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let photo = recipe.sortedPhotos.first {
                    PhotoImage(photo: photo, maxPixel: 700)
                    // Darkens the foot of the photo so the title reads on any picture.
                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                } else {
                    Image(systemName: recipe.categoryKind.symbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(14)
                        .accessibilityHidden(true)
                    shape.inset(by: 7).stroke(.white.opacity(0.28), lineWidth: 1)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if let cuisine = recipe.cuisineKind {
                        TricoloreStrip(cuisine: cuisine, width: 34, height: 4)
                    }
                    Text(recipe.title)
                        .font(Theme.title(19))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                    Text(summary)
                        .font(Theme.text(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.leading, 24)
                .padding(.trailing, 14)
                .padding(.bottom, 16)
            }
            .overlay(alignment: .topLeading) {
                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.leading, 24)
                        .padding(.top, 16)
                        .accessibilityLabel("Favourite")
                }
            }
            // The spine: a shaded strip down the bound edge.
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.06), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .shadow(color: Theme.ink.opacity(0.24), radius: 6, x: 2, y: 4)
            .accessibilityElement(children: .combine)
    }
}

/// Import from a link: a recipe page or a YouTube video. The review screen opens in this sheet.
struct ImportLinkView: View {
    let startNow: Bool
    let onSaved: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link: String
    @State private var importing = false
    @State private var importError: String?
    @State private var draft: RecipeDraft?

    init(initialLink: String, startNow: Bool, onSaved: @escaping (Recipe) -> Void) {
        self.startNow = startNow
        self.onSaved = onSaved
        _link = State(initialValue: initialLink)
    }

    var body: some View {
        if let draft {
            RecipeEditorView(review: draft, onSaved: onSaved)
        } else {
            NavigationStack {
                Form {
                    Section {
                        TextField("Paste a recipe or YouTube link", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(startImport)
                            .disabled(importing)
                            .accessibilityIdentifier("importLink")
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
                        Text("Link")
                    } footer: {
                        Text("You review every import before it is saved. From YouTube or any other app, you can also use Share and choose Hearth.")
                    }
                    Section {
                        Button(action: startImport) {
                            HStack(spacing: 8) {
                                if importing { ProgressView().accessibilityIdentifier("importProgress") }
                                Text(importing ? "Reading…" : "Import").font(Theme.body(17, bold: true))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(importing || link.trimmingCharacters(in: .whitespaces).isEmpty)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("importButton")
                    }
                }
                .warmList()
                .navigationTitle("Import Link")
                .navigationBarTitleDisplayMode(.inline)
                .font(Theme.body())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task {
                if startNow { startImport() }
            }
        }
    }

    private func startImport() {
        guard !importing, !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        importing = true
        importError = nil
        Task {
            do {
                draft = try await LinkImport.draft(from: link)
            } catch {
                importError = error.localizedDescription
            }
            importing = false
        }
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
