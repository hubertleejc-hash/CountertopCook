import SwiftUI
import SwiftData
import PhotosUI
import CookCore

/// A recipe opened like a book: paper pages for the cover (photos, title, Start Cooking), the
/// ingredients, the method and the cook's own notes. On a wide screen (iPad, an open Duo) it is
/// a two-page spread, with the method on the right-hand page; on a phone the pages follow each
/// other down the screen.
struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var cooking = false
    @State private var pickingToBuy = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var addingPhotos = false
    @FocusState private var notesFocused: Bool

    /// Width from which the book opens as a spread.
    private static let spreadWidth: CGFloat = 700

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= Self.spreadWidth {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            coverPage
                            ingredientsPage
                            notesPage
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 14)
                        .padding(.vertical, 16)
                    }
                    .frame(width: geo.size.width / 2)
                    ScrollView {
                        methodPage
                            .padding(.leading, 14)
                            .padding(.trailing, 20)
                            .padding(.vertical, 16)
                    }
                    .frame(width: geo.size.width / 2)
                }
                // The gutter between the two pages, shaded like the fold of an open book.
                .background {
                    LinearGradient(colors: [.clear, Theme.ink.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 44)
                        .accessibilityHidden(true)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        coverPage
                        ingredientsPage
                        methodPage
                        notesPage
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .font(Theme.body())
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { notesFocused = false }
                    .accessibilityIdentifier("keyboardDone")
            }
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
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            addPhotos(items)
        }
        .onChange(of: notesFocused) { _, focused in
            if !focused { try? context.save() }
        }
    }

    // MARK: Pages

    private var coverPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            photos
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recipeTitleHeader")
                HStack(spacing: 10) {
                    Label(recipe.categoryKind.rawValue, systemImage: recipe.categoryKind.symbol)
                    if let cuisine = recipe.cuisineKind {
                        CuisineBadge(cuisine: cuisine, size: 14)
                    }
                }
                .font(Theme.body(15, relativeTo: .subheadline))
                .foregroundStyle(Theme.muted)
                Text(facts)
                    .font(Theme.body(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("recipeFacts")
            }
            Button {
                cooking = true
            } label: {
                Label("Start Cooking", systemImage: "frying.pan")
                    .font(Theme.body(20, bold: true, relativeTo: .title3))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("startCooking")
            Button {
                pickingToBuy = true
            } label: {
                Label("Add to the to-buy list", systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .foregroundStyle(recipe.ingredients.isEmpty ? Theme.muted : Theme.navy)
            .disabled(recipe.ingredients.isEmpty)
            .accessibilityIdentifier("addToBuy")
            source
        }
        .bookPage()
    }

    private var facts: String {
        let servings = recipe.servings == 1 ? "1 serving" : "\(recipe.servings) servings"
        return recipe.totalMinutes > 0 ? "\(servings) · \(formatMinutes(recipe.totalMinutes))" : "\(servings) · time not given"
    }

    @ViewBuilder private var source: some View {
        if let source = recipe.sourceURL, let url = URL(string: source) {
            Link(destination: url) {
                Label("Source: \(recipe.sourceName ?? url.host ?? source)", systemImage: "link")
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
            .accessibilityIdentifier("recipeSource")
        } else if let source = recipe.sourceName, !source.isEmpty {
            Label("Source: \(source)", systemImage: "doc.text")
                .foregroundStyle(Theme.muted)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Source: \(source)")
                .accessibilityIdentifier("recipeSource")
        }
    }

    /// The recipe's photos, side by side, then the button that adds more from the photo library.
    @ViewBuilder private var photos: some View {
        let list = recipe.sortedPhotos
        if list.count == 1, let only = list.first {
            photoTile(only)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        } else if !list.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list) { photo in
                        photoTile(photo).frame(width: 250, height: 200)
                    }
                }
            }
        }
        PhotosPicker(selection: $picked, maxSelectionCount: 6, matching: .images) {
            HStack(spacing: 8) {
                if addingPhotos { ProgressView() }
                Label(list.isEmpty ? "Add photos" : "Add more photos", systemImage: "camera")
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .foregroundStyle(Theme.navy)
        .disabled(addingPhotos)
        .accessibilityIdentifier("addPhoto")
    }

    private func photoTile(_ photo: RecipePhoto) -> some View {
        PhotoImage(photo: photo)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contextMenu {
                if photo.order != recipe.sortedPhotos.first?.order {
                    Button {
                        makeCover(photo)
                    } label: {
                        Label("Use as the cover", systemImage: "book.closed")
                    }
                }
                Button(role: .destructive) {
                    context.delete(photo)
                    try? context.save()
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Photo of \(recipe.title)")
            .accessibilityIdentifier("recipePhoto")
    }

    private var ingredientsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Ingredients").padding(.bottom, 8)
            let items = recipe.sortedIngredients
            if items.isEmpty {
                Text("No ingredients listed.").foregroundStyle(Theme.muted)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                (Text(ingredientAmount(item, servingsFrom: recipe.servings, to: recipe.servings)).font(Theme.body(17, bold: true).monospacedDigit())
                 + Text(ingredientRest(item)))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                if index < items.count - 1 {
                    Divider().overlay(Theme.beige)
                }
            }
        }
        .bookPage()
    }

    private var methodPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Method")
            ForEach(Array(recipe.sortedSteps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(Theme.body(20, bold: true, relativeTo: .title3).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 24, alignment: .leading)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.text)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(index + 1). \(step.text)")
                        if let minutes = step.timerMinutes, minutes > 0 {
                            Label("\(minutes) min timer", systemImage: "timer")
                                .font(Theme.body(12, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                                .accessibilityIdentifier("stepTimerLabel_\(index)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .bookPage()
    }

    /// The cook's own page: free text, saved with the recipe.
    private var notesPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "My notes")
            TextField("What you changed, who you made it for, how it went…", text: $recipe.notes, axis: .vertical)
                .lineLimit(3...)
                .foregroundStyle(Theme.ink)
                .focused($notesFocused)
                .accessibilityIdentifier("recipeNotes")
        }
        .bookPage()
    }

    // MARK: Photos

    private func addPhotos(_ items: [PhotosPickerItem]) {
        addingPhotos = true
        picked = []
        Task {
            var order = (recipe.photos.map(\.order).max() ?? -1) + 1
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = PhotoStore.jpeg(from: data) else { continue }
                let photo = RecipePhoto(data: jpeg, order: order)
                context.insert(photo)
                photo.recipe = recipe
                order += 1
            }
            try? context.save()
            addingPhotos = false
        }
    }

    /// Moves a photo to the front, which makes it the cover on the shelf.
    private func makeCover(_ photo: RecipePhoto) {
        photo.order = (recipe.photos.map(\.order).min() ?? 0) - 1
        try? context.save()
    }
}

private struct BookPage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.beige, lineWidth: 1)
            }
            .shadow(color: Theme.ink.opacity(0.08), radius: 5, y: 2)
    }
}

private extension View {
    /// A sheet of the recipe's book: warm white paper with a soft edge.
    func bookPage() -> some View { modifier(BookPage()) }
}
