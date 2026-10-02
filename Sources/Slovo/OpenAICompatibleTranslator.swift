import Foundation

/// OpenAI's chat completions API, which OpenRouter, Ollama, LM Studio and many others speak too.
enum OpenAICompatibleTranslator {
    /// No token limit or temperature: servers and models disagree on those (newer OpenAI models
    /// reject `max_tokens`), and a translation is short anyway.
    static func complete(system: String, user: String, url: URL, model: String, apiKey: String?) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Local servers usually run without a key.
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
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
        var finishReason: String?
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let chunk = try? decoder.decode(Chunk.self, from: Data(payload.utf8)) else { continue }
            if let error = chunk.error { throw AIFailure.api(error.message) }
            for choice in chunk.choices ?? [] {
                text += choice.delta?.content ?? ""
                finishReason = choice.finishReason ?? finishReason
            }
        }

        if finishReason == "content_filter" { throw AIFailure.refused }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIFailure.emptyResponse }
        return result
    }

    /// Model IDs from `GET …/models`, sorted. OpenAI, OpenRouter, Ollama and LM Studio all serve it.
    static func models(at url: URL, apiKey: String?) async throws -> [String] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIFailure.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status: status, body: data) }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw AIFailure.message(L10n.aiNoModelList)
        }
        return Set(list.data.map(\.id)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private static func failure(status: Int, body: Data) -> AIFailure {
        let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error.message
        switch status {
        case 401, 403: return .invalidKey
        case 429: return .rateLimited
        case 500...: return .overloaded
        default: return .api(message ?? "HTTP \(status)")
        }
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
            let finishReason: String?
        }

        let choices: [Choice]?
        let error: APIError?
    }

    private struct APIError: Decodable {
        let message: String
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIError
    }
}
