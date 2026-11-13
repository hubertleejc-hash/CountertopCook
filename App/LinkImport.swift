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
    static func draft(from text: String) async throws -> RecipeDraft {
        let url = try link(from: text)
        if let video = YouTubePage.videoID(from: url) {
            return try await youTubeDraft(videoID: video)
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
            return try await youTubeDraft(videoID: video)
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
        let nothingRead = imported.ingredients.isEmpty && imported.steps.isEmpty
        if nothingRead && !isSocial(page) { return nil }
        // The caption's own first line names the dish more often than the page title does
        // ("cook on Instagram: …").
        if imported.title.isEmpty || nothingRead { imported.title = info.title ?? imported.title }
        var host = page.host ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var draft = RecipeDraft(imported: imported, sourceURL: page.absoluteString, sourceName: info.siteName ?? host,
                                referenceText: nothingRead ? caption : nil)
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

    private static func youTubeDraft(videoID: String) async throws -> RecipeDraft {
        let watch = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        var info = YouTubePage.Info()
        if let (html, _) = try? await fetch(watch, cookie: "SOCS=CAI") {
            info = YouTubePage.extract(html: html)
        }
        if info.description == nil {
            // The watch page sometimes comes back as a consent or "confirm you're not a bot" page
            // without the video's details. YouTube's own player data has them too.
            let player = await playerInfo(videoID: videoID)
            info.title = info.title ?? player.title
            info.channel = info.channel ?? player.channel
            info.description = player.description
            info.captionURL = info.captionURL ?? player.captionURL
        }
        if info.title == nil {
            // At least the title, from YouTube's public oEmbed.
            let oembed = await oEmbed(videoID: videoID)
            info.title = oembed.title
            info.channel = info.channel ?? oembed.channel
        }
        guard info.title != nil || info.description != nil else { throw Failure.noVideoDetails }

        let description = info.description ?? ""
        var imported = TextRecipeParser.parse(description)
        var reference: String?
        if imported.ingredients.isEmpty && imported.steps.isEmpty {
            // Nothing list-like in the description: try the captions, and either way show the
            // source text for the reader to work from. Spoken captions are never turned into
            // ingredients or steps by guesswork.
            var transcript = ""
            if let captions = info.captionURL, let (xml, _) = try? await fetch(captions, cookie: "SOCS=CAI") {
                transcript = YouTubePage.transcript(xml: xml)
                let fromCaptions = TextRecipeParser.parse(transcript)
                if !fromCaptions.ingredients.isEmpty || !fromCaptions.steps.isEmpty { imported = fromCaptions }
            }
            if imported.ingredients.isEmpty && imported.steps.isEmpty {
                let parts = [description.trimmingCharacters(in: .whitespacesAndNewlines),
                             transcript.isEmpty ? "" : "Captions:\n" + transcript]
                reference = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
                if reference?.isEmpty == true {
                    reference = "This video's description and captions don't give the recipe in writing. Take screenshots of the recipe as the video shows it and use + → Import from photos."
                }
            }
        }
        // The video's own title, not the description's first line.
        imported.title = info.title ?? imported.title
        let source = ["YouTube", info.channel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        var draft = RecipeDraft(imported: imported, sourceURL: watch.absoluteString, sourceName: source, referenceText: reference)
        // The video's own thumbnail, as YouTube publishes it for every video.
        draft.coverImage = await photo(at: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"))
        return draft
    }

    /// The title, channel, description and caption track from YouTube's player data, as its
    /// iPhone app asks for them. Empty when YouTube doesn't answer.
    private static func playerInfo(videoID: String) async -> YouTubePage.Info {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!,
                                 timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let body: [String: Any] = [
            "videoId": videoID,
            "context": ["client": ["clientName": "IOS", "clientVersion": "19.45.4", "deviceMake": "Apple",
                                   "deviceModel": "iPhone16,2", "osName": "iPhone", "osVersion": "18.1.0.22B83",
                                   "hl": "en", "gl": "US"]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .init() }
        var info = YouTubePage.Info()
        if let details = json["videoDetails"] as? [String: Any] {
            info.title = (details["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            info.channel = (details["author"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            info.description = (details["shortDescription"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let tracks = ((json["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any])?["captionTracks"]
            as? [[String: Any]] ?? []
        let track = tracks.first { ($0["languageCode"] as? String)?.hasPrefix("en") == true } ?? tracks.first
        if let address = track?["baseUrl"] as? String {
            info.captionURL = URL(string: address.hasPrefix("/") ? "https://www.youtube.com" + address : address)
        }
        return info
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
