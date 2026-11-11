import Foundation
import SwiftData
import CookCore

/// Reads a recipe from a link or from text and returns a draft for the review screen. Nothing is
/// saved here, and nothing is invented: a draft only holds what the source says, and lists what
/// it didn't say so the review screen can point at the blanks.
/// - A recipe page: its schema.org Recipe JSON-LD only (never the page's story text).
/// - A YouTube link: the video's title and description, and its captions when YouTube serves them.
/// - Pasted text: an ingredients list and a method list.
enum LinkImport {
    enum Failure: LocalizedError {
        case badLink
        case network(String)
        case notFound(Int)
        case noVideoDetails

        var errorDescription: String? {
            switch self {
            case .badLink: return "That doesn't look like a web link. Paste the full address of a recipe page or a YouTube video."
            case .network(let reason): return "Couldn't load the page: \(reason)"
            case .notFound(let status): return "Couldn't load the page (HTTP \(status))."
            case .noVideoDetails: return "Couldn't read this video's title or description. Paste the recipe text instead."
            }
        }
    }

    /// Fetches the link and reads a draft from it.
    static func draft(from text: String) async throws -> RecipeDraft {
        let url = try link(from: text)
        if let video = YouTubePage.videoID(from: url) {
            return try await youTubeDraft(videoID: video)
        }
        let (html, page) = try await fetch(url)
        let imported = try RecipeImporter.parse(html: html, url: page)
        return RecipeDraft(imported: imported, sourceURL: page.absoluteString, sourceName: imported.siteName)
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
        let (html, _) = try await fetch(watch, cookie: "SOCS=CAI")
        let info = YouTubePage.extract(html: html)
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
                if reference?.isEmpty == true { reference = "This video has no description or captions to read." }
            }
        }
        // The video's own title, not the description's first line.
        imported.title = info.title ?? imported.title
        let source = ["YouTube", info.channel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return RecipeDraft(imported: imported, sourceURL: watch.absoluteString, sourceName: source, referenceText: reference)
    }

    // MARK: Fetching

    private static func fetch(_ url: URL, cookie: String? = nil) async throws -> (String, URL) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // Some recipe sites refuse requests that don't look like a browser.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
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
