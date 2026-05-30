import Foundation

/// A single completion request. Kept deliberately small (system + user prompt);
/// follows the shape of runse's `LLMRequest`.
struct LLMRequest: Equatable, Sendable {
    var model: String
    var systemPrompt: String
    var userPrompt: String
    var temperature: Double
    var maxTokens: Int

    init(model: String, systemPrompt: String, userPrompt: String, temperature: Double = 0.2, maxTokens: Int = 256) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

struct LLMResponse: Equatable, Sendable {
    var text: String
    var model: String?
    var usage: [String: Int]

    var promptTokens: Int { usage["prompt_tokens"] ?? usage["input_tokens"] ?? 0 }
    var completionTokens: Int { usage["completion_tokens"] ?? usage["output_tokens"] ?? 0 }
    var totalTokens: Int { usage["total_tokens"] ?? (promptTokens + completionTokens) }

    init(text: String, model: String? = nil, usage: [String: Int] = [:]) {
        self.text = text
        self.model = model
        self.usage = usage
    }
}

enum LLMProviderError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case timeout
    case connectionLost(String)
    case invalidStatus(Int, String)
    case malformedJSON
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Missing API key."
        case .invalidURL: return "Invalid provider URL."
        case .timeout: return "The provider request timed out."
        case .connectionLost(let message): return "Network connection lost: \(message)"
        case .invalidStatus(let code, let body): return "Provider returned HTTP \(code): \(body)"
        case .malformedJSON: return "The provider response was malformed."
        case .emptyOutput: return "The provider returned an empty result."
        }
    }
}

/// Abstraction over an LLM backend so the completion engine can be tested with a
/// stub. Follows runse's `LLMProviderClient`.
protocol LLMProviderClient: Sendable {
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

/// A lean one-shot HTTP client. Unlike runse (which streams via the MacPaw/
/// OpenAI and SwiftAnthropic SPM packages), gterm keeps zero extra dependencies
/// and does a single non-streamed POST — completions are short and latency is
/// dominated by the model, not transport.
final class HTTPProviderClient: LLMProviderClient {
    private let profile: ProviderProfile
    private let apiKey: String
    private let session: URLSession

    init(profile: ProviderProfile, apiKey: String, session: URLSession = .shared) {
        self.profile = profile
        self.apiKey = apiKey
        self.session = session
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey
        }
        let urlRequest = try ProviderRequestFactory.urlRequest(profile: profile, apiKey: apiKey, request: request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMProviderError.timeout
        } catch let error as URLError {
            throw LLMProviderError.connectionLost(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw LLMProviderError.malformedJSON }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.invalidStatus(http.statusCode, body)
        }
        return try ProviderResponseParser.parse(data: data, kind: profile.kind)
    }
}

/// Builds the JSON body and `URLRequest` for a provider. Pure and testable.
enum ProviderRequestFactory {
    static func body(profile: ProviderProfile, request: LLMRequest) -> [String: Any] {
        switch profile.kind {
        case .anthropicMessages:
            return [
                "model": request.model,
                "system": request.systemPrompt,
                "max_tokens": request.maxTokens,
                "messages": [
                    ["role": "user", "content": request.userPrompt]
                ],
                "temperature": request.temperature,
            ]
        case .openAICompatible:
            return [
                "model": request.model,
                "max_tokens": request.maxTokens,
                "messages": [
                    ["role": "system", "content": request.systemPrompt],
                    ["role": "user", "content": request.userPrompt],
                ],
                "temperature": request.temperature,
            ]
        }
    }

    static func urlRequest(profile: ProviderProfile, apiKey: String, request: LLMRequest) throws -> URLRequest {
        guard let url = URL(string: endpointURL(profile: profile)), url.scheme != nil, url.host != nil else {
            throw LLMProviderError.invalidURL
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: 30)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        switch profile.kind {
        case .anthropicMessages:
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAICompatible:
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders(from: profile.extraHeadersJSON) {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(profile: profile, request: request))
        return urlRequest
    }

    private static func endpointURL(profile: ProviderProfile) -> String {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        let endpoint = profile.chatEndpoint.hasPrefix("/") ? profile.chatEndpoint : "/\(profile.chatEndpoint)"
        return "\(base)\(endpoint)"
    }

    private static func extraHeaders(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }
}

/// Parses a non-streamed JSON body into an `LLMResponse`. Pure and testable.
/// Mirrors runse's `ProviderResponseParser`.
enum ProviderResponseParser {
    static func parse(data: Data, kind: ProviderKind) throws -> LLMResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.malformedJSON
        }
        let content: String?
        let reasoning: String?
        switch kind {
        case .openAICompatible:
            let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            content = message?["content"] as? String
            reasoning = message?["reasoning_content"] as? String
        case .anthropicMessages:
            let blocks = object["content"] as? [[String: Any]] ?? []
            content = blocks
                .filter { ($0["type"] as? String) != "thinking" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            reasoning = blocks
                .filter { ($0["type"] as? String) == "thinking" }
                .compactMap { $0["thinking"] as? String }
                .joined(separator: "\n")
        }

        let trimmedContent = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalText: String
        if !trimmedContent.isEmpty {
            finalText = trimmedContent
        } else {
            let trimmedReasoning = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedReasoning.isEmpty else { throw LLMProviderError.emptyOutput }
            finalText = trimmedReasoning
        }
        return LLMResponse(
            text: finalText,
            model: object["model"] as? String,
            usage: parseUsage(object["usage"] as? [String: Any])
        )
    }

    private static func parseUsage(_ usage: [String: Any]?) -> [String: Int] {
        usage?.reduce(into: [String: Int]()) { partial, item in
            if let value = item.value as? Int {
                partial[item.key] = value
            } else if let value = item.value as? Double {
                partial[item.key] = Int(value)
            }
        } ?? [:]
    }
}
