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
        /// Import from photos or screenshots; `scan` opens the document camera straight away.
        case photos(scan: Bool)

        var id: String {
            switch self {
            case .manual: return "manual"
            case .link(let link, _): return "link-\(link)"
            case .paste: return "paste"
            case .photos: return "photos"
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
                    // Search, the to-buy list and + sit in the page, not in the navigation bar:
                    // on a closed iPhone Duo the bar's buttons float in the status strip.
                    HStack(spacing: 10) {
                        searchField
                        toBuyButton
                        addMenu
                    }
                    filterChips
                    HStack(spacing: 4) {
                        Text(shown.count == 1 ? "1 recipe" : "\(shown.count) recipes")
                            .font(Theme.body(14, relativeTo: .footnote))
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("libraryCount")
                        Spacer()
                        AppearanceMenu()
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
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .manual:
                    RecipeEditorView(recipe: nil)
                case .link(let link, let start):
                    ImportLinkView(initialLink: link, startNow: start) { open($0) }
                case .paste(let text):
                    PasteTextView(initialText: text) { open($0) }
                case .photos(let scan):
                    PhotoImportView(scanNow: scan) { open($0) }
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
                .accessibilityValue(recipe.photos.isEmpty ? "plain cover" : "photo cover")
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

    private var toBuyButton: some View {
        Button {
            showingToBuy = true
        } label: {
            Image(systemName: toBuyCount == 0 ? "cart" : "cart.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toBuyCount == 0 ? "To buy" : "To buy, \(toBuyCount)")
        .accessibilityIdentifier("openToBuy")
    }

    private var addMenu: some View {
        Menu {
            Button {
                sheet = .link("", start: false)
            } label: {
                Label("Import from a link", systemImage: "link")
            }
            .accessibilityIdentifier("menuImportLink")
            Button {
                sheet = .photos(scan: false)
            } label: {
                Label("Import from photos", systemImage: "photo.on.rectangle.angled")
            }
            .accessibilityIdentifier("menuImportPhotos")
            if DocumentScanner.isSupported {
                Button {
                    sheet = .photos(scan: true)
                } label: {
                    Label("Scan a recipe page", systemImage: "doc.viewfinder")
                }
                .accessibilityIdentifier("menuScanPage")
            }
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
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: Circle())
        }
        .accessibilityLabel("Add Recipe")
        .accessibilityIdentifier("addMenu")
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

    /// All / Food / Drinks / Desserts / Favourites. One row when it fits; else the same row with
    /// smaller chips; else a row that scrolls inside the page margins (never under the Duo's
    /// status strip), so Favourites is always reachable and never cut by the screen edge.
    private var filterChips: some View {
        ViewThatFits(in: .horizontal) {
            chipRow(compact: false)
            chipRow(compact: true)
            ScrollView(.horizontal, showsIndicators: false) {
                chipRow(compact: true)
            }
            .scrollClipDisabled(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func chipRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            filterChip("All", selected: category == nil && !favouritesOnly, compact: compact, id: "category_All") {
                category = nil
                favouritesOnly = false
            }
            ForEach(RecipeCategory.allCases) { item in
                filterChip(item.rawValue, symbol: compact ? nil : item.symbol, selected: category == item, compact: compact,
                           id: "category_\(item.rawValue)") {
                    category = category == item ? nil : item
                }
            }
            filterChip("Favourites", symbol: favouritesOnly ? "heart.fill" : "heart", selected: favouritesOnly, compact: compact,
                       iconOnly: compact, id: "favouritesFilter") {
                favouritesOnly.toggle()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func filterChip(_ title: String, symbol: String? = nil, selected: Bool, compact: Bool = false,
                            iconOnly: Bool = false, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.footnote) }
                if !iconOnly { Text(title).font(Theme.body(15, bold: true, relativeTo: .subheadline)) }
            }
            .padding(.horizontal, iconOnly ? 0 : (compact ? 11 : 14))
            .frame(minWidth: iconOnly ? 36 : nil, minHeight: 36)
            .foregroundStyle(selected ? Theme.onPill : Theme.ink)
            .background(selected ? Theme.pill : Theme.beige, in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
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
            // anything else (and the text read from a shared photo) goes to the paste screen,
            // ready to check and read.
            let fromPhoto = items.first(where: { $0.name == "source" })?.value == "photo"
            if !fromPhoto, text.count < 400, text.range(of: #"https?://\S+"#, options: .regularExpression) != nil {
                sheet = .link(text, start: true)
            } else {
                sheet = .paste(text)
            }
        }
    }
}

/// One recipe on the shelf, as a book.
/// - With a photo (added with Add photos, or the import source's own): the photo, full bleed,
///   with a soft dark gradient at the foot and the white serif title over it. The first photo
///   is the cover.
/// - Without one: a cloth cover, navy for food, green for drinks, brick for desserts, with a
///   thin gold border inside the edge, a small gold motif at the top, the tricolore strip above
///   the title, the title in white Lora and the time and steps below.
/// Covers look the same by day and by night: they are the books themselves.
struct BookCover: View {
    let recipe: Recipe

    static let navy = Color(hex: 0x1B2F4A)
    static let green = Color(hex: 0x2B5245)
    static let brick = Color(hex: 0x7E3626)
    static let gold = Color(hex: 0xC9A45C)

    private var cloth: Color {
        switch recipe.categoryKind {
        case .food: return Self.navy
        case .drinks: return Self.green
        case .desserts: return Self.brick
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

    private var cover: RecipePhoto? { recipe.sortedPhotos.first }

    var body: some View {
        cloth
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let cover {
                    PhotoImage(photo: cover, maxPixel: 700)
                    // A soft dark gradient at the foot, so the white title reads on any picture.
                    LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                           .init(color: .black.opacity(0.35), location: 0.62),
                                           .init(color: .black.opacity(0.78), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    shape.inset(by: 8).stroke(Self.gold.opacity(0.85), lineWidth: 1)
                    Image(systemName: recipe.categoryKind.symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Self.gold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    if let cuisine = recipe.cuisineKind {
                        TricoloreStrip(cuisine: cuisine, width: 34, height: 4)
                    } else if cover == nil {
                        Self.gold.frame(width: 26, height: 1.5).accessibilityHidden(true)
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
                .padding(.trailing, 16)
                .padding(.bottom, 20)
            }
            .overlay(alignment: .topTrailing) {
                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.footnote)
                        .foregroundStyle(cover == nil ? Self.gold : .white)
                        .padding(.trailing, 18)
                        .padding(.top, 18)
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
            .shadow(color: .black.opacity(0.24), radius: 6, x: 2, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityValue(cover == nil ? "plain cover" : "photo cover")
    }
}

/// Import from a link: a recipe page, or a video (YouTube, TikTok, Instagram, Facebook…). The review screen opens in this sheet.
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
                        TextField("Paste a recipe or video link", text: $link)
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
                        Text("A recipe page, or a video from YouTube, TikTok, Instagram or Facebook whose description or caption gives the recipe. You review every import before it is saved. From any app, you can also use Share and choose Hearth.")
                    }.warmRows()
                    Section {
                        Button(action: startImport) {
                            HStack(spacing: 8) {
                                if importing { ProgressView().accessibilityIdentifier("importProgress") }
                                Text(importing ? "Reading…" : "Import").font(Theme.body(17, bold: true)).foregroundStyle(Theme.onAccent)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(importing || link.trimmingCharacters(in: .whitespaces).isEmpty)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("importButton")
                    }.warmRows()
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
                    }.warmRows()
                    Section {
                        Button {
                            draft = LinkImport.draft(fromText: text)
                        } label: {
                            Text("Read recipe").font(Theme.body(17, bold: true)).foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("pasteTextRead")
                    }.warmRows()
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
