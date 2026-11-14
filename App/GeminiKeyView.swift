import SwiftUI

/// Sets up reading videos online: the cook pastes their own free Gemini API key, which stays
/// in this iPhone's Keychain. With a key, a YouTube link whose recipe is only spoken is read
/// by Gemini, which watches the video on Google's servers.
struct GeminiKeyView: View {
    /// Called after a key is saved, or nil when shown on its own.
    var onSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var hasKey = OnlineVideoReader.hasKey

    var body: some View {
        Form {
            Section {
                Text("Hearth can send a YouTube link to Google's Gemini, which watches the video, listens to what is said and reads its subtitles, then hands back the recipe. Only the link goes to Google; the video is never downloaded.")
                    .font(Theme.body(15, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
            }.warmRows()
            Section {
                Button {
                    openURL(OnlineVideoReader.keyPage)
                } label: {
                    Label("Get a free key from Google AI Studio", systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier("geminiGetKey")
                SecureField(hasKey ? "Paste a new key to replace it" : "Paste your Gemini API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("geminiKey")
            } header: {
                Text("Your Gemini key")
            } footer: {
                Text("Sign in with a Google account, choose Create API key, and copy it here. The free tier covers hours of video a day. The key is kept in this iPhone's Keychain only.")
            }.warmRows()
            Section {
                Button(action: save) {
                    Text(onSaved == nil ? "Save" : "Save and read the video")
                        .font(Theme.body(17, bold: true)).foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("geminiSave")
                if hasKey {
                    Button("Remove my key", role: .destructive) {
                        OnlineVideoReader.removeKey()
                        hasKey = false
                    }
                    .frame(minHeight: 44)
                }
            }.warmRows()
        }
        .warmList()
        .navigationTitle("Read videos online")
        .navigationBarTitleDisplayMode(.inline)
        .font(Theme.body())
    }

    private func save() {
        OnlineVideoReader.saveKey(key)
        key = ""
        hasKey = OnlineVideoReader.hasKey
        if let onSaved { onSaved() } else { dismiss() }
    }
}
