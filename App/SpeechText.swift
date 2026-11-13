import Foundation
import Speech
import AVFoundation

/// What a cooking video says, as text: Apple's speech recognition, on the phone where the
/// language allows it. Used for a video saved to Photos and for a YouTube video's audio.
enum SpeechText {
    /// Asks for speech recognition the first time; true when allowed.
    static func authorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        }
    }

    /// The language to listen for: Chinese when the text around the video (its title,
    /// description or on-screen text) is Chinese, else the phone's own language.
    static func locale(hint: String) -> Locale {
        if hint.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            // Traditional characters common in Taiwan and Hong Kong captions.
            let traditional = hint.range(of: "[們這為個說將麼與會從還點後們邊時開關鍋蔥]", options: .regularExpression) != nil
            return Locale(identifier: traditional ? "zh-TW" : "zh-CN")
        }
        return Locale.current
    }

    /// The transcript of the audio file, or nil when it can't be listened to.
    static func transcribe(_ url: URL, locale: Locale) async -> String? {
        guard await authorized(),
              let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        final class State: @unchecked Sendable {
            var committed = ""
            var latest = ""
            var done = false
            var task: SFSpeechRecognitionTask?
        }
        let state = State()
        let text: String? = await withCheckedContinuation { continuation in
            let lock = NSLock()
            func finish(_ value: String?) {
                lock.lock(); defer { lock.unlock() }
                guard !state.done else { return }
                state.done = true
                continuation.resume(returning: value)
            }
            state.task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    lock.lock()
                    // Long audio is recognised in stretches; a new stretch starts over short.
                    if text.count < state.latest.count / 2 { state.committed += state.latest + "\n" }
                    state.latest = text
                    let whole = state.committed + state.latest
                    lock.unlock()
                    if result.isFinal { finish(whole) }
                } else if error != nil {
                    lock.lock(); let whole = state.committed + state.latest; lock.unlock()
                    finish(whole.isEmpty ? nil : whole)
                }
            }
            // Never hang the import: give up after five minutes with what was heard.
            DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                lock.lock(); let whole = state.committed + state.latest; lock.unlock()
                state.task?.cancel()
                finish(whole.isEmpty ? nil : whole)
            }
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The audio of a video file as an .m4a in the temporary folder.
    static func audio(of video: URL) async -> URL? {
        let asset = AVURLAsset(url: video)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        export.outputURL = output
        export.outputFileType = .m4a
        await export.export()
        return export.status == .completed ? output : nil
    }
}
