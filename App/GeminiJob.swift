import Foundation

/// One question to Gemini, asked the way a phone has to ask it.
///
/// Watching a video or writing a recipe takes Gemini from seconds to minutes. Holding one
/// connection open for that long is what failed on mobile data: the network drops a quiet
/// connection, and the whole answer is lost with it. So the question is handed over as a
/// background job (Google's Interactions API): a short request starts it and returns at once,
/// then short requests check on it. A dropped check costs nothing, the next one picks it up.
/// If Google turns the job request down for a reason other than the key, the older streamed
/// request is used instead.
enum GeminiJob {
    struct Video {
        /// A public YouTube link, or the uri of a file uploaded to Gemini's file store.
        var uri: String
        var mime: String?
    }

    struct Ask {
        var prompt: String
        var system: String?
        var video: Video?
        /// The answer's JSON shape, enforced by Gemini.
        var schema: [String: Any]
        /// How long to wait for the answer in all.
        var seconds: TimeInterval
        /// Let Gemini search Google first and answer from the pages it finds. The schema isn't
        /// enforced then (Google doesn't take both together), so the prompt must ask for the JSON.
        var search = false
        /// The models to try, when not the usual ones (only some can search).
        var models: [String]? = nil
    }

    /// A web page Gemini's answer came from.
    struct Source: Equatable {
        var url: String
        var title: String
    }

    struct Reply {
        var text: String
        /// The pages a searched answer cites, in the order they were cited.
        var sources: [Source] = []
    }

    enum Failure: LocalizedError {
        /// Google's own reason for saying no.
        case refused(String)
        /// Google couldn't be reached at all; carries the phone's own description of why.
        case unreachable(String)
        case slow(Int)
        /// Every model Google offers was too busy to take the job.
        case busy
        case unreadable

        var errorDescription: String? {
            switch self {
            case .refused(let reason): return reason
            case .unreachable(let why): return "Couldn't reach Gemini (\(why)). Check the internet connection and try again."
            case .slow(let seconds):
                return "Gemini hadn't finished after \(seconds >= 120 ? "\(seconds / 60) minutes" : "\(seconds) seconds"). Google may be busy: try again in a minute."
            case .busy: return "Gemini is very busy right now and none of its models would take this. Google's free tier gets crowded: try again in a minute."
            case .unreadable: return "Gemini's answer couldn't be read. Try again."
            }
        }
    }

    /// The models, fastest first. On Google's free tier the newest model is often overloaded
    /// (answers come back "high demand" or never), while the lite models answer in seconds and
    /// read a recipe just as well. The last is an alias that keeps working when a name is retired.
    /// The models that can search Google, fastest first.
    static let searchModels = ["gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.8-flash", "gemini-flash-lite-latest"]

    static let models = ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3.6-flash", "gemini-3.8-flash",
                         "gemini-flash-lite-latest"]

    /// If a model hasn't answered in this many seconds, the next one is started beside it and
    /// whichever answers first is used.
    private static let hedge: Duration = .seconds(12)

    private static let api = "https://generativelanguage.googleapis.com"

    /// Why one way of asking didn't work, and what to try next.
    private enum Detour: Error {
        case nextModel(String)
        case streamed(String)
    }

    /// Short requests only: nothing here waits long on one connection.
    private static let quick: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private enum Outcome {
        case answer(Reply)
        case failed(Error)
        case slowStart
    }

    /// Gemini's answer text. `tick` is called every second with the seconds waited so far.
    /// Models are started one after another, and the next one is also started when the last
    /// is slow, so one overloaded model never holds the answer up.
    static func answer(_ ask: Ask, key: String, tick: @escaping @Sendable (Int) -> Void) async throws -> String {
        try await reply(ask, key: key, tick: tick).text
    }

    /// Gemini's answer, with the pages it cites when it searched.
    static func reply(_ ask: Ask, key: String, tick: @escaping @Sendable (Int) -> Void) async throws -> Reply {
        let models = ask.models ?? self.models
        let started = Date()
        let deadline = started.addingTimeInterval(ask.seconds)
        let ticker = Task {
            while !Task.isCancelled {
                tick(Int(Date().timeIntervalSince(started)))
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { ticker.cancel() }
        return try await withThrowingTaskGroup(of: Outcome.self) { group in
            var next = 0
            var running = 0
            var failures: [Error] = []
            func launch() {
                guard next < models.count else { return }
                let model = models[next]
                next += 1
                running += 1
                group.addTask {
                    do { return .answer(try await attempt(ask, model: model, key: key, deadline: deadline)) }
                    catch { return .failed(error) }
                }
                group.addTask {
                    try? await Task.sleep(for: hedge)
                    return .slowStart
                }
            }
            launch()
            while let outcome = try await group.next() {
                switch outcome {
                case .answer(let reply):
                    // The others are cancelled, which also cancels and deletes their jobs.
                    group.cancelAll()
                    return reply
                case .slowStart:
                    // At most two at once: each job counts against the free tier's allowance.
                    if Date() < deadline, running < 2 { launch() }
                case .failed(let error):
                    running -= 1
                    failures.append(error)
                    if running == 0 {
                        if next < models.count, Date() < deadline { launch() } else { group.cancelAll() }
                    }
                }
                if running == 0 && (next >= models.count || Date() >= deadline) { break }
            }
            group.cancelAll()
            // The most useful reason to show: Google's own words first, else whatever came last.
            for failure in failures { if case Failure.refused = failure { throw failure } }
            if failures.contains(where: { if case Failure.busy = $0 { return true } else { return false } }) { throw Failure.busy }
            throw failures.last ?? Failure.slow(Int(ask.seconds))
        }
    }

    /// One model's try: a background job, else the streamed request.
    private static func attempt(_ ask: Ask, model: String, key: String, deadline: Date) async throws -> Reply {
        do {
            return try await background(ask, model: model, key: key, deadline: deadline)
        } catch Detour.streamed(let reason) {
            do {
                return try await streamed(ask, model: model, key: key, deadline: deadline)
            } catch Detour.nextModel(let why) {
                throw Failure.refused(why.isEmpty ? reason : why)
            }
        } catch Detour.nextModel(let reason) {
            throw Failure.refused(reason)
        }
    }

    // MARK: Background job

    private static func background(_ ask: Ask, model: String, key: String, deadline: Date) async throws -> Reply {
        // 1. Start the job. Settings a model may not know are dropped on its first complaint.
        var full = true
        // The lightest thinking a model takes: recipes need knowledge, not long reasoning.
        var level: String? = "minimal"
        var busy = 0
        var id = ""
        var first: [String: Any] = [:]
        while id.isEmpty {
            let start = try request("/v1beta/interactions", method: "POST", key: key, json: jobBody(ask, model: model, level: level, full: full))
            let (data, status) = try await send(start, deadline: deadline, seconds: Int(ask.seconds))
            let reason = message(data, status)
            switch status {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let name = json["id"] as? String, !name.isEmpty else { throw Detour.streamed("Gemini's job answer couldn't be read.") }
                id = name
                first = json
            case 400 where level != nil && reason.localizedCaseInsensitiveContains("thinking"):
                // "minimal" isn't taken by every model: the next level up is.
                level = level == "minimal" ? "low" : nil
            case 400 where full:
                full = false
            case 401, 403:
                throw Failure.refused(reason)
            case 429, 500, 502, 503, 504:
                busy += 1
                guard busy < 3 else { throw Failure.busy }
                try await Task.sleep(for: .seconds(2 * busy))
            case 404 where reason.localizedCaseInsensitiveContains("model"):
                throw Detour.nextModel(reason)
            default:
                throw Detour.streamed(reason)
            }
        }
        // Whatever happens next, don't leave the job or its answer on Google's servers.
        var finished = false
        defer { tidy(id, key: key, cancel: !finished) }

        // 2. Check on it with short requests until it is done.
        var json = first
        var lastDrop = ""
        while true {
            switch json["status"] as? String ?? "in_progress" {
            case "completed":
                finished = true
                let text = outputText(json)
                guard !text.isEmpty else { throw Failure.unreadable }
                return Reply(text: text, sources: citations(json))
            case "in_progress", "queued", "pending":
                break
            case let other:
                finished = true
                let errors = (json["errors"] as? [[String: Any]])?.compactMap { $0["message"] as? String }.joined(separator: " ")
                    ?? (json["error"] as? [String: Any])?["message"] as? String ?? ""
                let reason = errors.isEmpty ? "Gemini stopped before answering (\(other))." : errors
                // Over the allowance or overloaded part-way: another model may still answer.
                let code = ((json["errors"] as? [[String: Any]])?.first?["code"] as? String ?? "").uppercased()
                if ["RESOURCE_EXHAUSTED", "INTERNAL", "UNAVAILABLE", "DEADLINE_EXCEEDED"].contains(code)
                    || reason.localizedCaseInsensitiveContains("quota") || reason.localizedCaseInsensitiveContains("overloaded")
                    || reason.localizedCaseInsensitiveContains("high demand") {
                    throw Failure.busy
                }
                throw Failure.refused(reason)
            }
            guard Date() < deadline else {
                throw lastDrop.isEmpty ? Failure.slow(Int(ask.seconds)) : Failure.unreachable(lastDrop)
            }
            try await Task.sleep(for: .milliseconds(1500))
            do {
                let (data, response) = try await quick.data(for: request("/v1beta/interactions/\(id)", method: "GET", key: key))
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let update = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    json = update
                    lastDrop = ""
                } else if ![429, 500, 502, 503, 504].contains(status) {
                    throw Failure.refused(message(data, status))
                }
            } catch let error as URLError where error.code != .cancelled {
                // A dropped check is no loss: the job carries on at Google, and the next check finds it.
                lastDrop = describe(error)
            }
        }
    }

    private static func jobBody(_ ask: Ask, model: String, level: String?, full: Bool) -> [String: Any] {
        var input: [[String: Any]] = []
        if let video = ask.video {
            var part: [String: Any] = ["type": "video", "uri": video.uri]
            if let mime = video.mime { part["mime_type"] = mime }
            // Small frames: plenty to read on-screen text, and quicker to watch.
            if full {
                part["resolution"] = "low"
                // Two frames a second apart add little to a recipe video: half a frame a second
                // reads the same words and is about a third fewer tokens to watch.
                part["processing"] = ["type": "static", "fps": 0.5]
            }
            input.append(part)
        }
        // The question goes after the video, as Google advises.
        input.append(["type": "text", "text": ask.prompt])
        var format: [String: Any] = ["type": "text", "mime_type": "application/json"]
        var body: [String: Any] = ["model": model, "input": input, "background": true]
        if let system = ask.system { body["system_instruction"] = system }
        if ask.search {
            body["tools"] = [["type": "google_search"]]
            if let level { body["generation_config"] = ["thinking_level": level] }
            return body
        }
        if full {
            var schema = ask.schema
            schema["propertyOrdering"] = nil
            format["schema"] = schema
        }
        if let level { body["generation_config"] = ["thinking_level": level] }
        body["response_format"] = format
        return body
    }

    /// The text of a finished job.
    static func outputText(_ json: [String: Any]) -> String {
        func texts(_ parts: Any?) -> String {
            (parts as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
        }
        let fromSteps = (json["steps"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "model_output" }.map { texts($0["content"]) }.joined()
        return fromSteps.isEmpty ? texts(json["outputs"]) : fromSteps
    }

    /// The pages a finished job's answer cites (its url_citation annotations), each once.
    static func citations(_ json: [String: Any]) -> [Source] {
        var found: [Source] = []
        for step in json["steps"] as? [[String: Any]] ?? [] where step["type"] as? String == "model_output" {
            for block in step["content"] as? [[String: Any]] ?? [] {
                for note in block["annotations"] as? [[String: Any]] ?? [] where note["type"] as? String == "url_citation" {
                    guard let url = note["url"] as? String, !url.isEmpty, !found.contains(where: { $0.url == url }) else { continue }
                    found.append(Source(url: url, title: note["title"] as? String ?? ""))
                }
            }
        }
        return found
    }

    /// Stops a job that is still running, and removes it either way.
    private static func tidy(_ id: String, key: String, cancel: Bool) {
        Task.detached {
            if cancel, let stop = try? request("/v1beta/interactions/\(id)/cancel", method: "POST", key: key) {
                _ = try? await quick.data(for: stop)
            }
            if let delete = try? request("/v1beta/interactions/\(id)", method: "DELETE", key: key) {
                _ = try? await quick.data(for: delete)
            }
        }
    }

    // MARK: Streamed request (the older way, kept as a fallback)

    private static func streamed(_ ask: Ask, model: String, key: String, deadline: Date) async throws -> Reply {
        var parts: [[String: Any]] = []
        if let video = ask.video {
            var file: [String: Any] = ["file_uri": video.uri]
            if let mime = video.mime { file["mime_type"] = mime }
            parts.append(["file_data": file])
        }
        parts.append(["text": ask.prompt])
        var config: [String: Any] = ["responseMimeType": "application/json", "responseSchema": ask.schema,
                                     "thinkingConfig": ["thinkingLevel": "low"]]
        if ask.video != nil { config["mediaResolution"] = "MEDIA_RESOLUTION_LOW" }
        if ask.search { config = ["thinkingConfig": ["thinkingLevel": "low"]] }
        var lastReason = ""
        var lastDrop = ""
        for attempt in 0..<3 {
            guard Date() < deadline else { throw Failure.slow(Int(ask.seconds)) }
            if attempt > 0 { try await Task.sleep(for: .seconds(2 * attempt)) }
            var body: [String: Any] = ["contents": [["role": "user", "parts": parts]], "generationConfig": config]
            if let system = ask.system { body["systemInstruction"] = ["parts": [["text": system]]] }
            if ask.search { body["tools"] = [["google_search": [String: Any]()]] }
            var call = try request("/v1beta/models/\(model):streamGenerateContent?alt=sse", method: "POST", key: key, json: body, timeout: 120)
            call.setValue(nil, forHTTPHeaderField: "Api-Revision")
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: call)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    var text = ""
                    var sources: [Source] = []
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                        if let error = json?["error"] as? [String: Any] {
                            throw Failure.refused(error["message"] as? String ?? "Gemini stopped answering.")
                        }
                        let candidate = (json?["candidates"] as? [[String: Any]])?.first
                        let chunks = (candidate?["groundingMetadata"] as? [String: Any])?["groundingChunks"] as? [[String: Any]] ?? []
                        for chunk in chunks {
                            guard let web = chunk["web"] as? [String: Any], let url = web["uri"] as? String,
                                  !sources.contains(where: { $0.url == url }) else { continue }
                            sources.append(Source(url: url, title: web["title"] as? String ?? ""))
                        }
                        let content = candidate?["content"] as? [String: Any]
                        text += (content?["parts"] as? [[String: Any]] ?? [])
                            .filter { ($0["thought"] as? Bool) != true }
                            .compactMap { $0["text"] as? String }.joined()
                    }
                    guard !text.isEmpty else { throw Failure.unreadable }
                    return Reply(text: text, sources: sources)
                }
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                lastReason = message(data, status)
                lastDrop = ""
                if status == 400, config.count > 1, !ask.search,
                   lastReason.localizedCaseInsensitiveContains("thinking") || lastReason.localizedCaseInsensitiveContains("schema") {
                    config = ["responseMimeType": "application/json"]
                    continue
                }
                if [429, 500, 502, 503, 504].contains(status) { continue }
                if status == 404 || lastReason.contains("not found") || lastReason.contains("is not supported") {
                    throw Detour.nextModel(lastReason)
                }
                throw Failure.refused(lastReason)
            } catch let error as URLError where error.code != .cancelled {
                lastDrop = describe(error)
            }
        }
        if !lastDrop.isEmpty { throw Failure.unreachable(lastDrop) }
        throw Failure.busy
    }

    // MARK: Plumbing

    private static func request(_ path: String, method: String, key: String, json: [String: Any]? = nil,
                                timeout: TimeInterval = 30) throws -> URLRequest {
        var request = URLRequest(url: URL(string: api + path)!, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("2026-05-20", forHTTPHeaderField: "Api-Revision")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    /// A short request, tried again when the connection drops.
    private static func send(_ request: URLRequest, deadline: Date, seconds: Int) async throws -> (Data, Int) {
        var lastDrop = ""
        for attempt in 0..<4 {
            guard Date() < deadline else { break }
            if attempt > 0 { try await Task.sleep(for: .milliseconds(1500 * attempt)) }
            do {
                let (data, response) = try await quick.data(for: request)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            } catch let error as URLError where error.code != .cancelled {
                lastDrop = describe(error)
            }
        }
        throw lastDrop.isEmpty ? Failure.slow(seconds) : Failure.unreachable(lastDrop)
    }

    /// Google's own message for a failed request.
    private static func message(_ data: Data, _ status: Int) -> String {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
    }

    /// The phone's reason for a failed connection, with its code so a report can be traced.
    private static func describe(_ error: URLError) -> String {
        "\(error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ". "))), code \(error.code.rawValue)"
    }
}
