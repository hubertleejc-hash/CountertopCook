import SwiftUI

/// Shown instead of an empty review screen when an import found no recipe: says why in a
/// sentence, and offers the next ways to get it, the most likely to work first.
struct ImportHelpView: View {
    enum Choice { case photos, video, paste, manual, retry }

    let reason: String
    /// The ways offered, in order.
    let choices: [Choice]
    let choose: (Choice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Couldn't find the recipe", systemImage: "magnifyingglass")
                            .font(Theme.body(19, bold: true))
                            .foregroundStyle(Theme.navy)
                        Text(reason)
                            .font(Theme.body(16, relativeTo: .body))
                            .foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("importHelpReason")
                    }
                    .padding(.vertical, 4)
                }.warmRows()
                Section {
                    ForEach(choices, id: \.self) { choice in
                        Button { choose(choice) } label: { row(choice) }
                            .accessibilityIdentifier("importHelp_\(String(describing: choice))")
                    }
                } header: {
                    Text("Try this instead")
                }.warmRows()
            }
            .warmList()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .font(Theme.body())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ choice: Choice) -> some View {
        let (title, detail, symbol): (String, String, String) = {
            switch choice {
            case .photos:
                return ("Import from screenshots",
                        "Pause the video where it shows the ingredients and steps, take screenshots, and Hearth reads them.",
                        "photo.on.rectangle.angled")
            case .video:
                return ("Import a saved video or screen recording",
                        "Save the video, or screen-record it playing (Control Center → Screen Recording). Hearth listens to it and reads its subtitles.",
                        "film")
            case .paste:
                return ("Paste the recipe text", "Copy the recipe from anywhere and paste it in.", "doc.on.clipboard")
            case .manual:
                return ("Fill it in myself", "Open the form with the title and photo, and the source's text to copy from.",
                        "square.and.pencil")
            case .retry:
                return ("Try another link", "", "link")
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(17, bold: true)).foregroundStyle(Theme.ink)
                if !detail.isEmpty {
                    Text(detail).font(Theme.body(14, relativeTo: .footnote)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }
}
