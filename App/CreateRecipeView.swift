import SwiftUI

/// Create with AI: the cook says what they'd like (a dish, an idea, or what's in the fridge),
/// in English or Chinese, and a new recipe is written for them. It opens on the review screen
/// in the same sheet, where it can be changed before it is saved.
struct CreateRecipeView: View {
    let onDraft: (RecipeDraft, RecipeCreator.Request) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var request: RecipeCreator.Request
    @State private var engines = RecipeCreator.engines
    @AppStorage("createEngine") private var chosen = RecipeCreator.Engine.gemini.rawValue
    @State private var writing = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    init(request: RecipeCreator.Request, onDraft: @escaping (RecipeDraft, RecipeCreator.Request) -> Void) {
        self.onDraft = onDraft
        _request = State(initialValue: request)
    }

    private var engine: RecipeCreator.Engine? {
        engines.first { $0.rawValue == chosen } ?? engines.first
    }

    private static let examples = ["番茄炒蛋", "红烧肉，少油版", "A quick vegetarian dinner", "Chicken, broccoli, garlic, rice"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if request.idea.isEmpty {
                            Text("A dish, an idea, or what you have. For example 宫保鸡丁, a light summer soup, or eggs, tomatoes and spring onions.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $request.idea)
                            .focused($typing)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .accessibilityIdentifier("createIdea")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.examples, id: \.self) { example in
                                Button(example) { request.idea = example }
                                    .font(Theme.body(14, relativeTo: .footnote))
                                    .buttonStyle(.bordered)
                                    .tint(Theme.navy)
                            }
                        }
                    }
                } header: {
                    Text("What would you like to cook?")
                }.warmRows()

                Section {
                    Stepper("Serves \(request.servings)", value: $request.servings, in: 1...12)
                        .accessibilityIdentifier("createServings")
                    Toggle("Only use what I listed", isOn: $request.onlyListed)
                        .accessibilityIdentifier("createOnlyListed")
                } footer: {
                    Text("With only what you listed, the recipe adds nothing but water, salt, pepper, sugar, oil and basic sauces.")
                }.warmRows()

                if engines.isEmpty {
                    setup
                } else {
                    Section {
                        if engines.count > 1 {
                            Picker("Write with", selection: $chosen) {
                                ForEach(engines) { Text($0.rawValue).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("createEngine")
                        }
                        Button(action: create) {
                            HStack(spacing: 8) {
                                if writing { ProgressView() }
                                Text(writing ? "Writing with \(engine?.rawValue ?? "AI")…" : "Create recipe")
                                    .font(Theme.body(17, bold: true)).foregroundStyle(Theme.onAccent)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(writing || request.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("createGo")
                        if let problem {
                            Text(problem)
                                .font(Theme.body(14, relativeTo: .footnote))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("createProblem")
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let engine { Text(engine.privacyNote) }
                            if !engines.contains(.gemini) {
                                NavigationLink("For richer recipes, add a free Gemini key") { GeminiKeyView() }
                                    .font(Theme.body(13, bold: true, relativeTo: .footnote))
                            }
                        }
                    }.warmRows()
                }
            }
            .warmList()
            .navigationTitle("Create with AI")
            .navigationBarTitleDisplayMode(.inline)
            .font(Theme.body())
            .onAppear { engines = RecipeCreator.engines }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { typing = false }
                        .accessibilityIdentifier("keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Neither Gemini nor Apple Intelligence can be used yet: how to turn one on.
    private var setup: some View {
        Section {
            if case .unavailable(let why) = RecipeAssistant.status {
                Text(why.replacingOccurrences(of: "write out recipes that are only spoken", with: "create recipes")
                    .replacingOccurrences(of: "write out a spoken recipe", with: "create recipes")
                    .replacingOccurrences(of: "Writing out a spoken recipe", with: "Creating recipes on the phone"))
                    .font(Theme.body(15, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
            }
            NavigationLink {
                GeminiKeyView()
            } label: {
                Label("Add a free Gemini key", systemImage: "key")
            }
            .accessibilityIdentifier("createAddKey")
        } header: {
            Text("Turn on AI")
        } footer: {
            Text("A Gemini key works on any iPhone and writes the best recipes. Apple Intelligence works on iPhone 15 Pro and later, on the phone itself.")
        }.warmRows()
    }

    private func create() {
        guard let engine else { return }
        typing = false
        writing = true
        problem = nil
        Task {
            defer { writing = false }
            do {
                let draft = try await RecipeCreator.create(request, with: engine)
                onDraft(draft, request)
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
