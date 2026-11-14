import SwiftUI

/// The import sheet: one place that moves between the ways in (a link, pasted text, photos,
/// a saved video), the review screen, and, when an import finds no recipe, the screen that
/// says why and offers the next way to try, without closing the sheet.
struct ImportSheet: View {
    enum Stage {
        case link(String, start: Bool)
        case paste(String)
        case photos(scan: Bool)
        case video
        case help(RecipeDraft, from: Origin)
        case review(RecipeDraft)
    }

    enum Origin { case link, paste, photos, video }

    let onSaved: (Recipe) -> Void
    @State private var stage: Stage
    /// Changes with every stage, so each screen starts fresh.
    @State private var step = 0

    init(start: Stage, onSaved: @escaping (Recipe) -> Void) {
        self.onSaved = onSaved
        _stage = State(initialValue: start)
    }

    var body: some View {
        Group {
            switch stage {
            case .link(let link, let start):
                ImportLinkView(initialLink: link, startNow: start) { received($0, from: .link) }
            case .paste(let text):
                PasteTextView(initialText: text) { received($0, from: .paste) }
            case .photos(let scan):
                PhotoImportView(scanNow: scan) { received($0, from: .photos) }
            case .video:
                VideoImportView { received($0, from: .video) }
            case .help(let draft, from: let origin):
                ImportHelpView(reason: draft.emptyReason ?? defaultReason(origin), choices: choices(origin)) { choice in
                    switch choice {
                    case .photos: go(.photos(scan: false))
                    case .video: go(.video)
                    case .paste: go(.paste(""))
                    case .manual: go(.review(draft))
                    case .retry: go(.link("", start: false))
                    }
                }
            case .review(let draft):
                RecipeEditorView(review: draft, onSaved: onSaved)
            }
        }
        .id(step)
    }

    private func go(_ next: Stage) {
        stage = next
        step += 1
    }

    private func received(_ draft: RecipeDraft, from origin: Origin) {
        go(draft.foundNothing ? .help(draft, from: origin) : .review(draft))
    }

    private func choices(_ origin: Origin) -> [ImportHelpView.Choice] {
        switch origin {
        case .link: return [.video, .photos, .paste, .manual, .retry]
        case .paste: return [.photos, .manual]
        case .photos: return [.photos, .paste, .manual]
        case .video: return [.photos, .manual]
        }
    }

    private func defaultReason(_ origin: Origin) -> String {
        switch origin {
        case .link: return "Hearth couldn't find a recipe at this link."
        case .paste: return "Hearth couldn't find an ingredient list or steps in this text."
        case .photos: return "Hearth couldn't find an ingredient list or steps in these photos. A sharper, closer photo of the recipe in good light reads best."
        case .video: return "Hearth couldn't find a recipe in this video."
        }
    }
}
