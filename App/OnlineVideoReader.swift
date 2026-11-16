import Foundation
import Security
import CookCore

/// Reads the recipe out of a public YouTube video from its link, online, with Google's Gemini
/// API: Google watches the video (picture and sound) on its own servers and Hearth gets back
/// the recipe as text. Hearth never downloads the video, which YouTube's terms don't allow.
/// Uses the cook's own free Gemini API key, kept in the iPhone's Keychain. For a YouTube link
/// only the link goes to Google; a video saved on the phone is uploaded, with the cook's consent.
enum OnlineVideoReader {
    enum Failure: LocalizedError {
        case noKey
        case refused(String)
        case unreadable
        case connection
        case slow

        var errorDescription: String? {
            switch self {
            case .noKey: return "Add a Gemini API key to read videos online."
            case .refused(let reason): return "Gemini couldn't read this video: \(reason)"
            case .unreadable: return "Gemini's answer couldn't be read."
            case .slow: return "Gemini took too long to watch this video. Try again in a minute, or on Wi-Fi."
            case .connection: return "The connection to Gemini kept dropping while it watched the video. Try again on Wi-Fi, or with a stronger signal."
            }
        }
    }

    /// Where to get a key, for the settings screen.
    static let keyPage = URL(string: "https://aistudio.google.com/apikey")!
    /// The models tried, in order: when Google retires one, the next still answers.
    static let models = ["gemini-3.8-flash", "gemini-flash-latest", "gemini-3.6-flash"]

    /// Checks a key before it is saved: nil when Gemini accepts it, else what's wrong.
    static func problem(withKey key: String) async -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: URL(string: "\(api)/v1beta/models?pageSize=1")!, timeoutInterval: 30)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return "Couldn't reach Google to check the key. Check the internet connection and try again."
        }
        do {
            try check(response, data)
        } catch let failure as Failure {
            return "Google didn't accept this key: " + reason(failure)
        } catch {
            return "Google didn't accept this key: " + error.localizedDescription
        }
        return nil
    }

    private static func reason(_ failure: Failure) -> String {
        if case .refused(let message) = failure { return message }
        return failure.localizedDescription
    }

    static var hasKey: Bool { !(Keychain.read() ?? "").isEmpty }

    static func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete() } else { Keychain.write(trimmed) }
    }

    static func removeKey() { Keychain.delete() }

    static let prompt = """
    Watch this cooking video, listening to what is said and reading any text shown on screen, \
    and write out its recipe. Use only what the video says or shows: never add an ingredient, \
    amount, time or step it doesn't give, and leave an amount or unit empty when it isn't stated. \
    Keep the video's own language (Chinese stays Chinese). Each step is one short instruction, \
    keeping any time or temperature stated. Answer with JSON only, in this shape:
    {"title": "", "servings": 0, "ingredients": [{"amount": "", "unit": "", "name": ""}], "steps": [""]}
    servings is 0 when the video doesn't say. If the video has no recipe, answer with empty lists.
    """

    static let api = "https://generativelanguage.googleapis.com"

    /// The saved key, for the other Gemini features (Create with AI).
    static var savedKey: String? { Keychain.read().flatMap { $0.isEmpty ? nil : $0 } }

    /// The recipe in the YouTube video at `url`; nil when the video has none.
    static func recipe(youTube url: URL, progress: @escaping @Sendable (String) -> Void) async throws -> ImportedRecipe? {
        try await generate(video: ["file_uri": url.absoluteString], progress: progress)
    }

    /// The recipe in a video file on the phone (one saved from Xiaohongshu, Douyin or another
    /// app, or a screen recording): uploaded to Gemini's file store, read, then deleted there.
    static func recipe(videoFile file: URL, progress: @escaping @Sendable (String) -> Void) async throws -> ImportedRecipe? {
        guard let key = Keychain.read(), !key.isEmpty else { throw Failure.noKey }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw Failure.refused("the video file is empty.") }
        let mime = file.pathExtension.lowercased() == "mp4" || file.pathExtension.lowercased() == "m4v" ? "video/mp4" : "video/mov"

        // 1. Start a resumable upload.
        progress("Sending the video to Gemini…")
        var start = URLRequest(url: URL(string: "\(api)/upload/v1beta/files")!, timeoutInterval: 60)
        start.httpMethod = "POST"
        start.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue(String(size), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue(mime, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": "Hearth recipe video"]])
        let (startData, startResponse) = try await session.data(for: start)
        try check(startResponse, startData)
        guard let uploadURL = (startResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Goog-Upload-URL")
                .flatMap(URL.init(string:)) else { throw Failure.unreadable }

        // 2. Send the bytes straight from the file.
        var upload = URLRequest(url: uploadURL, timeoutInterval: 600)
        upload.httpMethod = "POST"
        upload.setValue(String(size), forHTTPHeaderField: "Content-Length")
        upload.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        upload.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        let (uploadData, uploadResponse) = try await session.upload(for: upload, fromFile: file)
        try check(uploadResponse, uploadData)
        guard let uploaded = (try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any])?["file"] as? [String: Any],
              let name = uploaded["name"] as? String, let uri = uploaded["uri"] as? String else { throw Failure.unreadable }
        defer {
            // Don't leave the cook's video on Google's servers (it would expire in two days anyway).
            var delete = URLRequest(url: URL(string: "\(api)/v1beta/\(name)")!)
            delete.httpMethod = "DELETE"
            delete.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            URLSession.shared.dataTask(with: delete).resume()
        }

        // 3. Wait while Google prepares the video, then ask for the recipe.
        progress("Gemini is watching the video…")
        var state = uploaded["state"] as? String ?? "PROCESSING"
        var waited = 0
        while state == "PROCESSING" {
            guard waited < 300 else { throw Failure.refused("the video took too long to prepare.") }
            try await Task.sleep(for: .seconds(3))
            waited += 3
            var poll = URLRequest(url: URL(string: "\(api)/v1beta/\(name)")!, timeoutInterval: 30)
            poll.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let (pollData, pollResponse) = try await session.data(for: poll)
            try check(pollResponse, pollData)
            state = (try? JSONSerialization.jsonObject(with: pollData) as? [String: Any])?["state"] as? String ?? "FAILED"
        }
        guard state == "ACTIVE" else { throw Failure.refused("Google couldn't open this video.") }
        return try await generate(video: ["file_uri": uri, "mime_type": mime], progress: progress)
    }

    /// A session that waits out long answers: watching a video can take minutes.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private static func generate(video: [String: String], progress: @escaping @Sendable (String) -> Void) async throws -> ImportedRecipe? {
        guard let key = Keychain.read(), !key.isEmpty else { throw Failure.noKey }
        var body: [String: Any] = [
            "contents": [["parts": [["text": prompt], ["file_data": video]]]],
            // Low resolution frames: plenty to read on-screen text, and much quicker to watch.
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1,
                                 "mediaResolution": "MEDIA_RESOLUTION_LOW",
                                 // Writing out a recipe needs little reasoning; long thinking
                                 // was most of the wait.
                                 "thinkingConfig": ["thinkingLevel": "low"]],
        ]
        // Give up after four minutes in all, rather than retrying for a quarter of an hour.
        let deadline = Date().addingTimeInterval(240)
        // Shows the time spent, so a long wait doesn't look stuck.
        let started = Date()
        let ticker = Task {
            while !Task.isCancelled {
                let seconds = Int(Date().timeIntervalSince(started))
                progress(seconds < 5 ? "Gemini is watching the video…"
                         : String(format: "Gemini is watching the video… %d:%02d", seconds / 60, seconds % 60))
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { ticker.cancel() }
        var lastError: Error = Failure.unreadable
        for model in models {
            // A dropped connection or a busy answer is tried again, up to three times in all.
            for attempt in 0..<3 {
                guard Date() < deadline else { throw Failure.slow }
                if attempt > 0 { try await Task.sleep(for: .seconds(3 * attempt)) }
                // Streamed, so bytes keep flowing while Gemini watches: a silent connection
                // held for minutes is what mobile networks drop ("connection was lost").
                var request = URLRequest(url: URL(string: "\(api)/v1beta/models/\(model):streamGenerateContent?alt=sse")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 200 {
                        var text = ""
                        for try await line in bytes.lines where line.hasPrefix("data:") {
                            let chunk = Data(line.dropFirst(5).utf8)
                            let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any]
                            if let error = json?["error"] as? [String: Any] {
                                throw Failure.refused(error["message"] as? String ?? "Gemini stopped answering.")
                            }
                            text += ((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
                                .flatMap { $0 as? [[String: Any]] }?.compactMap { $0["text"] as? String }.joined() ?? ""
                        }
                        return try parse(text)
                    }
                    var data = Data()
                    for try await byte in bytes { data.append(byte) }
                    do { try check(response, data) } catch { lastError = error }
                    // A model that doesn't take a thinking level is asked again without one.
                    if status == 400, case Failure.refused(let message) = lastError, message.lowercased().contains("thinking"),
                       var config = body["generationConfig"] as? [String: Any], config["thinkingConfig"] != nil {
                        config["thinkingConfig"] = nil
                        body["generationConfig"] = config
                        continue
                    }
                    if [429, 500, 503, 504].contains(status) { continue }
                    break
                } catch let error as URLError where error.code != .cancelled {
                    lastError = Failure.connection
                    continue
                }
            }
            // Only a model Google no longer offers moves on to the next one.
            guard case Failure.refused(let message) = lastError,
                  message.contains("not found") || message.contains("is not supported") || message.contains("HTTP 404")
            else { throw lastError }
        }
        throw lastError
    }

    /// Throws Google's own message for a failed request.
    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, status != 200 else { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
        throw Failure.refused(message)
    }

    /// Whether the cook has agreed to send saved videos to Google (asked once, before the first).
    static var uploadAgreed: Bool {
        get { UserDefaults.standard.bool(forKey: "geminiUploadAgreed") }
        set { UserDefaults.standard.set(newValue, forKey: "geminiUploadAgreed") }
    }

    static let uploadNotice = "Hearth will send this video to Google's Gemini to read the recipe, then delete it there. On Gemini's free tier, Google may use what you send to improve its products."

    /// Gemini's JSON answer as a recipe; nil when it found none.
    static func parse(_ text: String) throws -> ImportedRecipe? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Tolerate a fenced answer.
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}") { body = String(body[start...end]) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else {
            throw Failure.unreadable
        }
        func string(_ value: Any?) -> String {
            if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let number = value as? NSNumber { return number.stringValue }
            return ""
        }
        let ingredients: [ImportedRecipe.Ingredient] = (object["ingredients"] as? [[String: Any]] ?? []).compactMap { item in
            let name = string(item["name"])
            return name.isEmpty ? nil : .init(amount: string(item["amount"]), unit: string(item["unit"]), name: name)
        }
        let steps = (object["steps"] as? [Any] ?? []).map(string).filter { !$0.isEmpty }
        guard !ingredients.isEmpty || !steps.isEmpty else { return nil }
        func number(_ value: Any?) -> Int? {
            let n = (value as? NSNumber)?.intValue ?? Int(string(value)) ?? 0
            return n > 0 ? n : nil
        }
        func optionalText(_ value: Any?) -> String? {
            let t = string(value)
            return t.isEmpty ? nil : t
        }
        // totalMinutes, cuisine and category come only from Create with AI; a video's answer has none.
        return ImportedRecipe(title: string(object["title"]), servings: number(object["servings"]),
                              totalMinutes: number(object["totalMinutes"]), ingredients: ingredients, steps: steps,
                              siteName: "", cuisine: optionalText(object["cuisine"]), category: optionalText(object["category"]))
    }
}

/// The Gemini key in the Keychain, on this iPhone only.
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hubertlee.countertopcook.gemini",
        kSecAttrAccount as String: "api-key",
    ]

    static func read() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
