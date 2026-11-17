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
    }

    enum Failure: LocalizedError {
        /// Google's own reason for saying no.
        case refused(String)
        /// Google couldn't be reached at all; carries the phone's own description of why.
        case unreachable(String)
        case slow(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .refused(let reason): return reason
            case .unreachable(let why): return "Couldn't reach Gemini (\(why)). Check the internet connection and try again."
            case .slow(let seconds):
                return "Gemini hadn't finished after \(seconds >= 120 ? "\(seconds / 60) minutes" : "\(seconds) seconds"). Google may be busy: try again in a minute."
            case .unreadable: return "Gemini's answer couldn't be read. Try again."
            }
        }
    }

    /// The models tried, in order. Each has its own free allowance, so when one is used up,
    /// busy or retired, the next still answers.
    static let models = ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-flash-latest"]

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

    /// Gemini's answer text. `tick` is called every second with the seconds waited so far.
    static func answer(_ ask: Ask, key: String, tick: @escaping @Sendable (Int) -> Void) async throws -> String {
        let started = Date()
        let deadline = started.addingTimeInterval(ask.seconds)
        let ticker = Task {
            while !Task.isCancelled {
                tick(Int(Date().timeIntervalSince(started)))
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { ticker.cancel() }
        var lastReason = ""
        for model in models {
            do {
                do {
                    return try await background(ask, model: model, key: key, deadline: deadline)
                } catch Detour.streamed(let reason) {
                    lastReason = reason
                    return try await streamed(ask, model: model, key: key, deadline: deadline)
                }
            } catch Detour.nextModel(let reason) {
                lastReason = reason
            } catch Detour.streamed(let reason) {
                lastReason = reason
            }
        }
        throw Failure.refused(lastReason.isEmpty ? "Gemini didn't answer." : lastReason)
    }

    // MARK: Background job

    private static func background(_ ask: Ask, model: String, key: String, deadline: Date) async throws -> String {
        // 1. Start the job. Settings a model may not know are dropped on its first complaint.
        var full = true
        var busy = 0
        var id = ""
        var first: [String: Any] = [:]
        while id.isEmpty {
            let start = try request("/v1beta/interactions", method: "POST", key: key, json: jobBody(ask, model: model, full: full))
            let (data, status) = try await send(start, deadline: deadline, seconds: Int(ask.seconds))
            let reason = message(data, status)
            switch status {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let name = json["id"] as? String, !name.isEmpty else { throw Detour.streamed("Gemini's job answer couldn't be read.") }
                id = name
                first = json
            case 400 where full:
                full = false
            case 401, 403:
                throw Failure.refused(reason)
            case 429, 500, 502, 503, 504:
                busy += 1
                guard busy < 3 else { throw Detour.nextModel(reason) }
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
                return text
            case "in_progress", "queued", "pending":
                break
            case let other:
                finished = true
                let errors = (json["errors"] as? [[String: Any]])?.compactMap { $0["message"] as? String }.joined(separator: " ")
                    ?? (json["error"] as? [String: Any])?["message"] as? String ?? ""
                let reason = errors.isEmpty ? "Gemini stopped before answering (\(other))." : errors
                // Over the allowance or overloaded part-way: another model may still answer.
                if reason.localizedCaseInsensitiveContains("quota") || reason.localizedCaseInsensitiveContains("overloaded")
                    || reason.localizedCaseInsensitiveContains("rate") || reason.localizedCaseInsensitiveContains("unavailable") {
                    throw Detour.nextModel(reason)
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

    private static func jobBody(_ ask: Ask, model: String, full: Bool) -> [String: Any] {
        var input: [[String: Any]] = []
        if let video = ask.video {
            var part: [String: Any] = ["type": "video", "uri": video.uri]
            if let mime = video.mime { part["mime_type"] = mime }
            // Small frames: plenty to read on-screen text, and quicker to watch.
            if full { part["resolution"] = "low" }
            input.append(part)
        }
        // The question goes after the video, as Google advises.
        input.append(["type": "text", "text": ask.prompt])
        var format: [String: Any] = ["type": "text", "mime_type": "application/json"]
        var body: [String: Any] = ["model": model, "input": input, "background": true]
        if let system = ask.system { body["system_instruction"] = system }
        if full {
            var schema = ask.schema
            schema["propertyOrdering"] = nil
            format["schema"] = schema
            // Writing out a recipe needs knowledge, not long reasoning: low thinking is far quicker.
            body["generation_config"] = ["thinking_level": "low"]
        }
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

    private static func streamed(_ ask: Ask, model: String, key: String, deadline: Date) async throws -> String {
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
        var lastReason = ""
        var lastDrop = ""
        for attempt in 0..<3 {
            guard Date() < deadline else { throw Failure.slow(Int(ask.seconds)) }
            if attempt > 0 { try await Task.sleep(for: .seconds(2 * attempt)) }
            var body: [String: Any] = ["contents": [["role": "user", "parts": parts]], "generationConfig": config]
            if let system = ask.system { body["systemInstruction"] = ["parts": [["text": system]]] }
            var call = try request("/v1beta/models/\(model):streamGenerateContent?alt=sse", method: "POST", key: key, json: body, timeout: 120)
            call.setValue(nil, forHTTPHeaderField: "Api-Revision")
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: call)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    var text = ""
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
                        if let error = json?["error"] as? [String: Any] {
                            throw Failure.refused(error["message"] as? String ?? "Gemini stopped answering.")
                        }
                        let content = (json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any]
                        text += (content?["parts"] as? [[String: Any]] ?? [])
                            .filter { ($0["thought"] as? Bool) != true }
                            .compactMap { $0["text"] as? String }.joined()
                    }
                    guard !text.isEmpty else { throw Failure.unreadable }
                    return text
                }
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                lastReason = message(data, status)
                lastDrop = ""
                if status == 400, config.count > 1,
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
        throw Detour.nextModel(lastReason)
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
