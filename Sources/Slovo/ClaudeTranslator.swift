import Foundation

/// Claude's Messages API, called over HTTPS directly: Anthropic has no Swift SDK.
enum ClaudeTranslator {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models?limit=1000")!

    /// `lowEffort` also turns on server-side fallback, which exists only on models that take `effort`.
    /// If the API rejects either option for this model, the request is repeated without them.
    static func complete(system: String, user: String, model: String, lowEffort: Bool, apiKey: String) async throws -> String {
        do {
            return try await send(system: system, user: user, model: model, lowEffort: lowEffort, apiKey: apiKey)
        } catch RequestError.badRequest(let failure) {
            guard lowEffort else { throw failure }
        }
        do {
            return try await send(system: system, user: user, model: model, lowEffort: false, apiKey: apiKey)
        } catch RequestError.badRequest(let failure) {
            throw failure
        }
    }

    /// The models the key's account can use, newest first.
    static func models(apiKey: String) async throws -> [ClaudeModel] {
        var request = URLRequest(url: modelsEndpoint, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIFailure.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status: status, body: data) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let list = try? decoder.decode(ModelList.self, from: data) else {
            throw AIFailure.message(L10n.aiNoModelList)
        }
        return list.data.map { model in
            let effort = model.capabilities?.effort
            return ClaudeModel(
                id: model.id,
                name: model.displayName ?? model.id,
                supportsLowEffort: effort?.supported == true && effort?.low?.supported == true
            )
        }
    }

    /// A 400: the request itself was refused, so it may succeed without the optional parameters.
    private enum RequestError: Error {
        case badRequest(AIFailure)
    }

    private static func send(system: String, user: String, model: String, lowEffort: Bool, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "stream": true,
            "system": system,
            "messages": [
                ["role": "user", "content": user],
            ],
        ]
        if lowEffort {
            // Translation is a short, latency-sensitive task; thinking stays on, low effort keeps it brief.
            body["output_config"] = ["effort": "low"]
            // Server-side fallback: if a safety classifier declines the text (rare false positives on
            // benign content), the API re-runs the request on Anthropic's recommended fallback model.
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw AIFailure.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 400 { throw RequestError.badRequest(failure(status: status, body: data)) }
            throw failure(status: status, body: data)
        }

        // Streamed so a long text can't hit a request timeout; the popup shows the result at the end.
        var text = ""
        var stopReason: String?
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for try await line in bytes.lines {
            guard line.hasPrefix("data:"),
                  let event = try? decoder.decode(StreamEvent.self, from: Data(line.dropFirst(5).utf8)) else { continue }
            switch event.type {
            case "content_block_start" where event.contentBlock?.type == "fallback":
                // A fallback model takes over from one that declined: its partial output doesn't count.
                text = ""
            case "content_block_delta" where event.delta?.type == "text_delta":
                text += event.delta?.text ?? ""
            case "message_delta":
                stopReason = event.delta?.stopReason ?? stopReason
            case "error":
                throw failure(type: event.error?.type, message: event.error?.message)
            default:
                break
            }
        }

        // Checked before the text: on a refusal the content is empty or a partial to discard.
        if stopReason == "refusal" { throw AIFailure.refused }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIFailure.emptyResponse }
        return result
    }

    private static func failure(status: Int, body: Data) -> AIFailure {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        switch status {
        case 401: return .invalidKey
        case 429: return .rateLimited
        case 500..., 529: return .overloaded
        default: return failure(type: envelope?.error.type, message: envelope?.error.message ?? "HTTP \(status)")
        }
    }

    private static func failure(type: String?, message: String?) -> AIFailure {
        switch type {
        case "authentication_error": .invalidKey
        case "rate_limit_error": .rateLimited
        case "overloaded_error", "api_error": .overloaded
        default: .api(message ?? type ?? "unknown")
        }
    }

    private struct StreamEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?
        }

        struct Block: Decodable {
            let type: String
        }

        struct APIError: Decodable {
            let type: String
            let message: String
        }

        let type: String
        let delta: Delta?
        let contentBlock: Block?
        let error: APIError?
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
            let displayName: String?
            let capabilities: Capabilities?
        }

        struct Capabilities: Decodable {
            let effort: Effort?
        }

        struct Effort: Decodable {
            let supported: Bool
            let low: Support?
        }

        struct Support: Decodable {
            let supported: Bool
        }

        let data: [Model]
    }

    private struct ErrorEnvelope: Decodable {
        let error: StreamEvent.APIError
    }
}
