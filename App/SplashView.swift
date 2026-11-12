import SwiftUI

/// What the app shows first: the startup page (the mark and the name) for a moment, then the
/// library. A tap skips the wait.
struct RootView: View {
    @State private var showingSplash = RootView.wantsSplash
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue

    /// UI tests skip the startup page unless they ask for it with `-splash`.
    private static var wantsSplash: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-uitesting") || arguments.contains("-splash")
    }

    /// Long enough to read the name; `-splash` holds it longer so a test can see it.
    private static var splashSeconds: Double {
        ProcessInfo.processInfo.arguments.contains("-splash") ? 6 : 1.6
    }

    var body: some View {
        ZStack {
            RecipeListView()
            if showingSplash {
                SplashView()
                    .onTapGesture(perform: hideSplash)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear { Appearance.apply(Appearance(rawValue: appearance) ?? .system) }
        .onChange(of: appearance) { _, value in Appearance.apply(Appearance(rawValue: value) ?? .system) }
        .task {
            guard showingSplash else { return }
            try? await Task.sleep(for: .seconds(Self.splashSeconds))
            hideSplash()
        }
    }

    private func hideSplash() {
        withAnimation(.easeOut(duration: 0.45)) { showingSplash = false }
    }
}

/// The startup page: the Hearth mark, the name and one line, on the app's cream.
struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                HearthLogo()
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
                Text("Hearth")
                    .font(Theme.text(44, bold: true))
                    .foregroundStyle(Theme.ink)
                Text("Your recipes, kept like a cookbook")
                    .font(Theme.text(17))
                    .foregroundStyle(Theme.muted)
            }
            .padding(32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hearth")
        .accessibilityIdentifier("splash")
    }
}
