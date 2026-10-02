import Foundation

/// Claude's Messages API, called over HTTPS directly: Anthropic has no Swift SDK.
enum ClaudeTranslator {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func complete(system: String, user: String, model: ClaudeModel, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16000,
            "stream": true,
            "system": system,
            "messages": [
                ["role": "user", "content": user],
            ],
        ]
        if model.supportsEffortAndFallbacks {
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
            throw failure(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
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

    private struct ErrorEnvelope: Decodable {
        let error: StreamEvent.APIError
    }
}
