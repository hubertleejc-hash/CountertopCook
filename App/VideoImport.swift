import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import CookCore

/// Import a cooking video saved to Photos (from Xiaohongshu, Douyin, TikTok, Instagram or the
/// camera). Hearth reads the text the video shows on screen (subtitles, ingredient cards) and
/// listens to what it says, all on the phone, and Apple Intelligence writes the recipe out
/// for the review screen. With a Gemini key (and the cook's consent), Gemini reads it instead.
struct VideoImportView: View {
    let onDraft: (RecipeDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var reading = false
    @State private var status: String?
    @State private var readError: String?
    /// A video waiting for the cook's answer to the Gemini notice.
    @State private var awaitingConsent: Source?
    /// The newest video in Photos, once Hearth is allowed to look.
    @State private var newest: NewestVideo.Info?

    /// Where the video to read comes from.
    private enum Source {
        case picked(PhotosPickerItem)
        case newest(PHAsset)
    }
    @State private var hasKey = OnlineVideoReader.hasKey

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $picked, matching: .videos) {
                        Label("Choose a video", systemImage: "film")
                            .frame(minHeight: 44)
                    }
                    .disabled(reading)
                    .accessibilityIdentifier("videoImportPick")
                    // Right after Save video in TikTok, Instagram or Xiaohongshu, the video is the newest one.
                    Button {
                        Task { await readNewest() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Read my newest saved video", systemImage: "clock.arrow.circlepath")
                            if let newest {
                                Text(newest.summary)
                                    .font(Theme.body(13, relativeTo: .footnote))
                                    .foregroundStyle(Theme.ink.opacity(0.7))
                            }
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .disabled(reading)
                    .accessibilityIdentifier("videoImportNewest")
                    if reading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(status ?? "Opening the video…")
                        }
                        .accessibilityIdentifier("videoImportProgress")
                    }
                    if let readError {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                            Text(readError)
                        }
                        .font(Theme.body(13, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Video")
                } footer: {
                    Text(hasKey
                         ? "A cooking video saved to Photos. Google's Gemini watches it and writes out the recipe for you to check; without a connection, Hearth reads it on this iPhone."
                         : "A cooking video saved to Photos. Hearth reads the words it shows on screen and listens to what it says, on this iPhone, then writes out the recipe for you to check. A few minutes of video takes about a minute.")
                }.warmRows()
                Section {
                    NavigationLink {
                        GeminiKeyView()
                    } label: {
                        Label(hasKey ? "Read videos online: on" : "Read videos online", systemImage: "sparkles.tv")
                    }
                    .disabled(reading)
                } footer: {
                    if !hasKey {
                        Text("With your own free Gemini key, Google's Gemini watches the video, which reads spoken Chinese and on-screen text better than the phone can.")
                    }
                }.warmRows()
            }
            .warmList()
            .navigationTitle("Import a Video")
            .navigationBarTitleDisplayMode(.inline)
            .font(Theme.body())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                hasKey = OnlineVideoReader.hasKey
                if NewestVideo.allowed { newest = NewestVideo.find() }
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                start(.picked(item))
            }
            .alert("Send this video to Gemini?", isPresented: Binding(
                get: { awaitingConsent != nil }, set: { if !$0 { awaitingConsent = nil } })) {
                Button("Send to Gemini") {
                    OnlineVideoReader.uploadAgreed = true
                    if let source = awaitingConsent { read(source, online: true) }
                    awaitingConsent = nil
                }
                Button("Read on this iPhone") {
                    if let source = awaitingConsent { read(source, online: false) }
                    awaitingConsent = nil
                }
                Button("Cancel", role: .cancel) { awaitingConsent = nil; picked = nil }
            } message: {
                Text(OnlineVideoReader.uploadNotice)
            }
        }
    }

    /// Asks first, once, before a video goes to Gemini.
    private func start(_ source: Source) {
        if OnlineVideoReader.hasKey && !OnlineVideoReader.uploadAgreed {
            awaitingConsent = source
        } else {
            read(source, online: OnlineVideoReader.hasKey)
        }
    }

    /// The video just saved from another app: the newest in Photos.
    private func readNewest() async {
        guard !reading else { return }
        readError = nil
        guard await NewestVideo.ensureAccess() else {
            readError = "Hearth needs to see your Photos to find the video you just saved. Allow it in Settings → Hearth → Photos, or choose the video below."
            return
        }
        guard let found = NewestVideo.find() else {
            readError = "Hearth can't see a video in Photos yet. Save one from the app first, or choose one below."
            return
        }
        newest = found
        start(.newest(found.asset))
    }

    private func read(_ source: Source, online: Bool) {
        guard !reading else { return }
        reading = true
        readError = nil
        status = "Opening the video…"
        Task {
            defer { reading = false; picked = nil }
            let file: URL?
            switch source {
            case .picked(let item): file = (try? await item.loadTransferable(type: PickedMovie.self))?.url
            case .newest(let asset): file = await NewestVideo.file(for: asset)
            }
            guard let file else {
                readError = "Couldn't open that video. Try another one."
                return
            }
            let movie = PickedMovie(url: file)
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let report: LinkImport.Progress = { line in Task { @MainActor in status = line } }
            var onlineProblem: String?
            if online {
                do {
                    if let watched = try await OnlineVideoReader.recipe(videoFile: movie.url, progress: report) {
                        var draft = RecipeDraft(imported: watched, sourceURL: nil, sourceName: "Video")
                        draft.readBy = "Gemini (Google), from the video"
                        draft.coverImage = await VideoText.cover(of: movie.url)
                        onDraft(draft)
                        return
                    }
                    onlineProblem = "Gemini found no recipe in this video."
                } catch {
                    onlineProblem = error.localizedDescription
                }
                // Fall back to reading it on the phone.
                report("Reading it on this iPhone instead…")
            }
            let content = await VideoText.read(movie.url, progress: report)
            guard !content.onScreen.isEmpty || !content.speech.isEmpty else {
                var draft = RecipeDraft(imported: TextRecipeParser.parse(""), sourceURL: nil, sourceName: "Video")
                draft.emptyReason = [onlineProblem, "Hearth couldn't find any words in this video: nothing on screen, and no speech it could make out."]
                    .compactMap { $0 }.joined(separator: " ")
                draft.coverImage = content.cover
                onDraft(draft)
                return
            }
            let text = [content.onScreen.isEmpty ? "" : "Text shown in the video:\n" + content.onScreen,
                        content.speech.isEmpty ? "" : "What the video says:\n" + content.speech]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
            var draft = await LinkImport.smartDraft(fromText: text, sourceName: "Video", preferAssistant: true, progress: report)
            if draft.readBy != nil { draft.readBy = "Apple Intelligence, from what the video shows and says" }
            if let onlineProblem, let reason = draft.emptyReason { draft.emptyReason = onlineProblem + " " + reason }
            draft.coverImage = content.cover
            onDraft(draft)
        }
    }
}

/// The newest video in Photos, so a video saved a moment ago from TikTok, Instagram, Xiaohongshu
/// or Douyin is one tap away. Needs the cook's permission to see Photos, asked when they tap.
enum NewestVideo {
    struct Info {
        let asset: PHAsset

        /// "Saved 2 minutes ago · 0:42"
        var summary: String {
            let seconds = Int(asset.duration.rounded())
            let length = String(format: "%d:%02d", seconds / 60, seconds % 60)
            guard let date = asset.creationDate else { return length }
            let when = RelativeDateTimeFormatter()
            when.unitsStyle = .full
            return "Saved " + when.localizedString(for: date, relativeTo: Date()) + " · " + length
        }
    }

    static var allowed: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func ensureAccess() async -> Bool {
        if allowed { return true }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func find() -> Info? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .video, options: options).firstObject.map(Info.init)
    }

    /// A temporary copy of the video's file, fetched from iCloud if it isn't on the phone; nil when it can't be had.
    static func file(for asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video })
                ?? resources.first(where: { $0.type == .fullSizeVideo }) else { return nil }
        let ext = URL(fileURLWithPath: resource.originalFilename).pathExtension
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "mov" : ext)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: copy, options: options) { error in
                continuation.resume(returning: error == nil ? copy : nil)
            }
        }
    }
}

/// A video from the photo library, copied to a temporary file Hearth can read.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// The words in a video file: its on-screen text, read from frames, and its speech.
enum VideoText {
    struct Content {
        var onScreen = ""
        var speech = ""
        /// A frame near the end, where cooking videos show the finished dish, as a JPEG.
        var cover: Data?
    }

    /// A frame near the end, where cooking videos show the finished dish, as a JPEG.
    static func cover(of url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        guard seconds.isFinite, seconds > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        guard let frame = try? await generator.image(at: CMTime(seconds: seconds * 0.92, preferredTimescale: 600)).image else { return nil }
        return PhotoStore.jpeg(from: frame)
    }

    static func read(_ url: URL, progress: LinkImport.Progress) async -> Content {
        var content = Content()
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        guard seconds.isFinite, seconds > 0 else { return content }

        // On-screen text: a frame every two seconds or so, at most 60, each line kept once.
        progress("Reading the words on screen…")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let count = min(60, max(1, Int(seconds / 2)))
        var seen = Set<String>()
        var lines: [String] = []
        for index in 0..<count {
            let time = CMTime(seconds: seconds * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            let text = (try? await PhotoText.text(in: [frame])) ?? ""
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 2, !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                lines.append(trimmed)
            }
        }
        content.onScreen = lines.joined(separator: "\n")
        if let frame = try? await generator.image(at: CMTime(seconds: seconds * 0.92, preferredTimescale: 600)).image {
            content.cover = PhotoStore.jpeg(from: frame)
        }

        // Speech, in the language of the on-screen text when there is some.
        if (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false {
            progress("Listening to the video…")
            if let audio = await SpeechText.audio(of: url) {
                content.speech = await SpeechText.transcribe(audio, locale: SpeechText.locale(hint: content.onScreen)) ?? ""
                try? FileManager.default.removeItem(at: audio)
            }
        }
        return content
    }
}
