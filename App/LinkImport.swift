import Foundation
import SwiftData
import CookCore

/// Reads a recipe from a link or from text and returns a draft for the review screen. Nothing is
/// saved here, and nothing is invented: a draft only holds what the source says, and lists what
/// it didn't say so the review screen can point at the blanks.
/// - A recipe page: its schema.org Recipe JSON-LD only (never the page's story text).
/// - A YouTube link: the video's title and description, and its captions when YouTube serves them.
/// - Any other page with no recipe card (a TikTok, Instagram or Facebook video, a pin…): the
///   post's caption, which is where most recipe videos write the recipe.
/// - Pasted text: an ingredients list and a method list.
enum LinkImport {
    enum Failure: LocalizedError {
        case badLink
        case network(String)
        case notFound(Int)
        case noVideoDetails
        case nothingToRead

        var errorDescription: String? {
            switch self {
            case .badLink: return "That doesn't look like a web link. Paste the full address of a recipe page or a YouTube video."
            case .network(let reason): return "Couldn't load the page: \(reason)"
            case .notFound(let status): return "Couldn't load the page (HTTP \(status))."
            case .noVideoDetails: return "Couldn't read this video's title or description. Take screenshots of the recipe and use + → Import from photos, or paste the recipe text."
            case .nothingToRead: return "No recipe or caption could be read at this link (some sites only show posts to signed-in visitors). Take screenshots of the recipe and use + → Import from photos, or paste the recipe text."
            }
        }
    }

    /// Fetches the link and reads a draft from it.
    static func draft(from text: String, progress: @escaping Progress = { _ in }) async throws -> RecipeDraft {
        let url = try link(from: text)
        if let video = YouTubePage.videoID(from: url) {
            return try await youTubeDraft(videoID: video, progress: progress)
        }
        // Instagram, Facebook and Threads show browsers a sign-in page, but give link previews
        // (the caption and the photo) to the preview reader that chat apps use.
        let preview = previewFirst(url)
        let html: String, page: URL
        do {
            (html, page) = try await fetch(url, userAgent: preview ? previewAgent : browserAgent)
        } catch where isSocial(url) {
            if let (other, otherPage) = try? await fetch(url, userAgent: preview ? browserAgent : previewAgent),
               let draft = await captionDraft(html: other, page: otherPage) {
                return draft
            }
            throw Failure.nothingToRead
        }
        if let video = YouTubePage.videoID(from: page) {
            // A short link that led to YouTube.
            return try await youTubeDraft(videoID: video, progress: progress)
        }
        do {
            let imported = try RecipeImporter.parse(html: html, url: page)
            var draft = RecipeDraft(imported: imported, sourceURL: page.absoluteString, sourceName: imported.siteName)
            draft.coverImage = await photo(at: imported.imageURL)
            return draft
        } catch RecipeImportError.noRecipeData {
            // No recipe card: a video or post. Read its caption instead.
            if let draft = await captionDraft(html: html, page: page) { return draft }
            if isSocial(page) || isSocial(url) {
                if let (other, otherPage) = try? await fetch(url, userAgent: preview ? browserAgent : previewAgent),
                   let draft = await captionDraft(html: other, page: otherPage) {
                    return draft
                }
                throw Failure.nothingToRead
            }
            throw RecipeImportError.noRecipeData
        }
    }

    // MARK: Captions (TikTok, Instagram, Facebook…)

    private static let socialHosts = ["tiktok.com", "instagram.com", "facebook.com", "fb.com", "fb.watch",
                                      "pinterest.com", "pin.it", "xiaohongshu.com", "xhslink.com", "threads.net",
                                      "x.com", "twitter.com", "douyin.com", "vimeo.com", "reddit.com"]

    private static func isSocial(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return socialHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func previewFirst(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["instagram.com", "facebook.com", "fb.com", "fb.watch", "threads.net"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static let previewAgent = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

    /// The post's caption as a draft: its lists when it has them, else the caption itself beside
    /// the empty form. Nil when the page has no caption to read. On a site that isn't a video or
    /// social site, only a caption with a real ingredient or step list counts: a blog's summary
    /// line is not a recipe.
    private static func captionDraft(html: String, page: URL) async -> RecipeDraft? {
        // A sign-in page that a post redirected to has no caption of the post.
        guard !page.path.lowercased().contains("login") else { return nil }
        let info = PageCaption.extract(html: html, page: page)
        guard let caption = info.text, !caption.isEmpty else { return nil }
        var imported = TextRecipeParser.parse(caption)
        if !isSocial(page) && !anything(imported) { return nil }
        var readBy: String?
        if !complete(imported), let written = await RecipeAssistant.recipe(from: caption, title: nil),
           written.steps.count >= imported.steps.count {
            imported = written
            readBy = "Apple Intelligence, from the post's caption"
        }
        let nothingRead = !anything(imported)
        // The caption's own first line names the dish more often than the page title does
        // ("cook on Instagram: …").
        if imported.title.isEmpty || nothingRead { imported.title = info.title ?? imported.title }
        var host = page.host ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var draft = RecipeDraft(imported: imported, sourceURL: page.absoluteString, sourceName: info.siteName ?? host,
                                referenceText: caption)
        draft.readBy = readBy
        if nothingRead {
            if case .unavailable(let why) = RecipeAssistant.status {
                draft.emptyReason = "This post's caption doesn't list the ingredients and steps. " + why
            } else {
                draft.emptyReason = "This post's caption doesn't give the recipe, and the video's sound can't be reached from its link."
            }
        }
        draft.coverImage = await photo(at: RecipeImporter.imageURL(nil, html: html, page: page))
        return draft
    }

    /// The source's own photo of the dish, shrunk for storage; nil when it has none or it can't
    /// be loaded. A missing photo never stops an import.
    static func photo(at url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              data.count < 25_000_000 else { return nil }
        return PhotoStore.jpeg(from: data)
    }

    /// Reads a draft from pasted text. When no ingredient or step list can be read, the text
    /// itself goes along as reference, so the review screen can show it beside the empty form.
    static func draft(fromText text: String, sourceName: String = "Pasted text") -> RecipeDraft {
        let imported = TextRecipeParser.parse(text)
        let nothingRead = imported.ingredients.isEmpty && imported.steps.isEmpty
        return RecipeDraft(imported: imported, sourceURL: nil, sourceName: sourceName,
                           referenceText: nothingRead ? text.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
    }

    /// Reads a draft from text (pasted, read from photos, or heard in a video). When the plain
    /// reader can't find both an ingredient list and steps, Apple Intelligence writes the
    /// recipe out from the text instead, where the phone has it.
    /// `preferAssistant`: the text is speech or subtitles, which the plain reader can't follow,
    /// so Apple Intelligence reads it first when the phone has it.
    static func smartDraft(fromText text: String, title: String? = nil, sourceName: String, preferAssistant: Bool = false,
                           progress: @escaping Progress = { _ in }) async -> RecipeDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var imported = preferAssistant && RecipeAssistant.isAvailable
            ? ImportedRecipe(title: "", servings: nil, totalMinutes: nil, ingredients: [], steps: [], siteName: "", cuisine: nil)
            : TextRecipeParser.parse(trimmed)
        var readBy: String?
        if !complete(imported), RecipeAssistant.isAvailable {
            progress("Writing out the recipe…")
            if let written = await RecipeAssistant.recipe(from: trimmed, title: title),
               written.steps.count >= imported.steps.count, written.ingredients.count + written.steps.count > 0 {
                imported = written
                readBy = "Apple Intelligence"
            }
        }
        if let title, !title.isEmpty, imported.title.isEmpty { imported.title = title }
        var draft = RecipeDraft(imported: imported, sourceURL: nil, sourceName: sourceName,
                                referenceText: trimmed.isEmpty ? nil : trimmed)
        draft.readBy = readBy
        if !anything(imported) {
            if case .unavailable(let why) = RecipeAssistant.status {
                draft.emptyReason = "Hearth couldn't find an ingredient list or numbered steps here. " + why
            } else {
                draft.emptyReason = "Hearth couldn't find a recipe here."
            }
        }
        return draft
    }

    static func link(from text: String) throws -> URL {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Shared text can be "Watch this: https://youtu.be/…"; take the link out of it.
        if let range = trimmed.range(of: #"https?://\S+"#, options: .regularExpression) {
            trimmed = String(trimmed[range])
        } else if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty
        else { throw Failure.badLink }
        return url
    }

    // MARK: YouTube

    /// Status lines for the import screen while a long import runs ("Listening to the video…").
    typealias Progress = @Sendable (String) -> Void

    private static func complete(_ recipe: ImportedRecipe) -> Bool { !recipe.ingredients.isEmpty && !recipe.steps.isEmpty }
    private static func anything(_ recipe: ImportedRecipe) -> Bool { !recipe.ingredients.isEmpty || !recipe.steps.isEmpty }

    /// A YouTube video: the recipe as its description writes it; else as the video says it
    /// (its captions, or its sound heard on the phone), written out by Apple Intelligence.
    private static func youTubeDraft(videoID: String, progress: Progress) async throws -> RecipeDraft {
        progress("Opening the video…")
        let watch = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        var info = YouTubePage.Info()
        if let (html, _) = try? await fetch(watch, cookie: "SOCS=CAI") {
            info = YouTubePage.extract(html: html)
        }
        // YouTube's own player data: the details when the watch page came back as a consent or
        // "confirm you're not a bot" page, and the caption tracks and sound when needed.
        let player = await playerData(videoID: videoID)
        info.title = info.title ?? player.info.title
        info.channel = info.channel ?? player.info.channel
        info.description = info.description ?? player.info.description
        info.captionURL = player.info.captionURL ?? info.captionURL
        if info.title == nil {
            let oembed = await oEmbed(videoID: videoID)
            info.title = oembed.title
            info.channel = info.channel ?? oembed.channel
        }
        guard info.title != nil || info.description != nil else { throw Failure.noVideoDetails }

        let description = (info.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var imported = TextRecipeParser.parse(description)
        var readBy: String?
        var emptyReason: String?
        var spoken = ""
        if !complete(imported) {
            if let captions = info.captionURL {
                progress("Reading the video's captions…")
                spoken = await captionText(captions)
            }
            if spoken.isEmpty, let audio = player.audioURL, player.seconds <= 40 * 60 {
                progress("Listening to the video…")
                if let file = await download(audio, userAgent: player.userAgent) {
                    let hint = (info.title ?? "") + description
                    spoken = await SpeechText.transcribe(file, locale: SpeechText.locale(hint: hint)) ?? ""
                    try? FileManager.default.removeItem(at: file)
                }
            }
            if !spoken.isEmpty {
                let fromSpoken = TextRecipeParser.parse(spoken)
                if complete(fromSpoken) { imported = fromSpoken; readBy = "the video's captions" }
            }
            if !complete(imported) {
                switch RecipeAssistant.status {
                case .available:
                    progress("Writing out the recipe…")
                    let text = [description, spoken.isEmpty ? "" : "What the video says:\n" + spoken]
                        .filter { !$0.isEmpty }.joined(separator: "\n\n")
                    if let written = await RecipeAssistant.recipe(from: text, title: info.title),
                       written.steps.count >= imported.steps.count {
                        imported = written
                        readBy = spoken.isEmpty ? "Apple Intelligence, from the video's description"
                                                : "Apple Intelligence, from what the video says"
                    } else if !anything(imported) {
                        emptyReason = spoken.isEmpty
                            ? "This video doesn't write the recipe down, and Hearth couldn't get its captions or its sound."
                            : "Hearth listened to this video but couldn't find a recipe in what it says."
                    }
                case .unavailable(let why):
                    if !anything(imported) {
                        emptyReason = spoken.isEmpty
                            ? "This video doesn't write the recipe down, and Hearth couldn't get its captions or its sound."
                            : "This video only says the recipe out loud. " + why
                    }
                }
            }
        }
        // The video's own title, not the description's first line.
        imported.title = info.title ?? imported.title
        let source = ["YouTube", info.channel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let reference = [description, spoken.isEmpty ? "" : "What the video says:\n" + spoken]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        var draft = RecipeDraft(imported: imported, sourceURL: watch.absoluteString, sourceName: source,
                                referenceText: reference.isEmpty ? nil : reference)
        draft.readBy = readBy
        draft.emptyReason = emptyReason
        // The video's own thumbnail, as YouTube publishes it for every video.
        draft.coverImage = await photo(at: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"))
        return draft
    }

    private struct PlayerData {
        var info = YouTubePage.Info()
        var audioURL: URL?
        var seconds = 0
        var userAgent = ""
    }

    /// The video's details, caption track and sound from YouTube's player data, as its phone
    /// apps ask for them (the iPhone app first, then the Android app).
    private static func playerData(videoID: String) async -> PlayerData {
        let clients: [(agent: String, client: [String: Any])] = [
            ("com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)",
             ["clientName": "IOS", "clientVersion": "19.45.4", "deviceMake": "Apple", "deviceModel": "iPhone16,2",
              "osName": "iPhone", "osVersion": "18.1.0.22B83", "hl": "en", "gl": "US"]),
            ("com.google.android.youtube/19.44.38 (Linux; U; Android 14) gzip",
             ["clientName": "ANDROID", "clientVersion": "19.44.38", "androidSdkVersion": 34, "osName": "Android",
              "osVersion": "14", "hl": "en", "gl": "US"]),
        ]
        var result = PlayerData()
        for (agent, client) in clients {
            var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!,
                                     timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(agent, forHTTPHeaderField: "User-Agent")
            request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["videoId": videoID, "context": ["client": client]])
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let details = json["videoDetails"] as? [String: Any] {
                result.info.title = result.info.title ?? (details["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                result.info.channel = result.info.channel ?? (details["author"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                result.info.description = result.info.description
                    ?? (details["shortDescription"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if let seconds = Int(details["lengthSeconds"] as? String ?? "") { result.seconds = seconds }
            }
            if result.info.captionURL == nil {
                let tracks = ((json["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any])?["captionTracks"]
                    as? [[String: Any]] ?? []
                // Captions someone wrote before automatic ones, in the video's own language.
                let track = tracks.first { ($0["kind"] as? String) != "asr" } ?? tracks.first
                if let address = track?["baseUrl"] as? String {
                    result.info.captionURL = URL(string: address.hasPrefix("/") ? "https://www.youtube.com" + address : address)
                }
            }
            if result.audioURL == nil,
               let formats = (json["streamingData"] as? [String: Any])?["adaptiveFormats"] as? [[String: Any]] {
                let audio = formats.filter { ($0["mimeType"] as? String)?.hasPrefix("audio/mp4") == true && $0["url"] != nil }
                let pick = audio.first { ($0["itag"] as? Int) == 140 } ?? audio.first
                if let address = pick?["url"] as? String, let url = URL(string: address) {
                    result.audioURL = url
                    result.userAgent = agent
                }
            }
            if result.info.description != nil, result.info.captionURL != nil || result.audioURL != nil { break }
        }
        return result
    }

    /// The captions as text: YouTube's JSON captions, else its timed-text XML.
    private static func captionText(_ url: URL) async -> String {
        if var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "fmt" } + [URLQueryItem(name: "fmt", value: "json3")]
            if let json = parts.url, let (data, response) = try? await URLSession.shared.data(from: json),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                let text = YouTubePage.transcript(json3: data)
                if !text.isEmpty { return text }
            }
        }
        if let (xml, _) = try? await fetch(url, cookie: "SOCS=CAI") { return YouTubePage.transcript(xml: xml) }
        return ""
    }

    /// The video's sound, saved to a temporary .m4a; nil when YouTube won't hand it over.
    private static func download(_ url: URL, userAgent: String) async -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (file, response) = try? await URLSession.shared.download(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        guard (try? FileManager.default.moveItem(at: file, to: target)) != nil else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
        guard size > 10_000 else { try? FileManager.default.removeItem(at: target); return nil }
        return target
    }

    private static func oEmbed(videoID: String) async -> (title: String?, channel: String?) {
        guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(videoID)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return (json["title"] as? String, json["author_name"] as? String)
    }

    // MARK: Fetching

    private static let browserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func fetch(_ url: URL, cookie: String? = nil, userAgent: String = browserAgent) async throws -> (String, URL) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // Some recipe sites refuse requests that don't look like a browser.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.notFound(http.statusCode)
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (html, response.url ?? url)
    }
}
