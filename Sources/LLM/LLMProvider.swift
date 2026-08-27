import Foundation
import OpenAI
import SwiftAnthropic

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
/// stub. Follows runse's `LLMProviderClient`: streaming with an optional delta
/// callback, plus a one-shot convenience.
protocol LLMProviderClient {
    @MainActor func complete(_ request: LLMRequest, onDelta: (@MainActor (String) -> Void)?) async throws -> LLMResponse
}

extension LLMProviderClient {
    @MainActor func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await complete(request, onDelta: nil)
    }
}

/// Streams completions over Server-Sent Events. The SSE handling follows the
/// runse project exactly: OpenAI-compatible providers stream through the MacPaw
/// `OpenAI` SDK (`chatsStream`) and Anthropic providers through `SwiftAnthropic`
/// (`streamMessage`). gterm adds no hand-rolled SSE parser.
final class HTTPProviderClient: LLMProviderClient {
    private let profile: ProviderProfile
    private let apiKey: String

    init(profile: ProviderProfile, apiKey: String, session: URLSession = .shared) {
        self.profile = profile
        self.apiKey = apiKey
    }

    @MainActor func complete(_ request: LLMRequest, onDelta: (@MainActor (String) -> Void)? = nil) async throws -> LLMResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey
        }
        switch profile.kind {
        case .openAICompatible:
            return try await streamOpenAIChat(request: request, onDelta: onDelta)
        case .anthropicMessages:
            return try await streamAnthropicMessage(request: request, onDelta: onDelta)
        }
    }

    @MainActor private func streamOpenAIChat(request: LLMRequest, onDelta: (@MainActor (String) -> Void)?) async throws -> LLMResponse {
        let client = OpenAI(configuration: try openAIConfiguration())
        guard let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: request.systemPrompt),
              let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: request.userPrompt) else {
            throw LLMProviderError.malformedJSON
        }
        let query = ChatQuery(
            messages: [systemMessage, userMessage],
            model: request.model,
            temperature: request.temperature,
            stream: true,
            streamOptions: ChatQuery.StreamOptions(includeUsage: true)
        )

        var content = ""
        var reasoning = ""
        var model: String?
        var usage: [String: Int] = [:]

        do {
            for try await chunk in client.chatsStream(query: query) {
                if model == nil { model = chunk.model }
                var contentChanged = false
                for choice in chunk.choices {
                    if let delta = choice.delta.content {
                        content += delta
                        contentChanged = true
                    }
                    if let delta = choice.delta.reasoning { reasoning += delta }
                }
                if contentChanged, let onDelta { onDelta(content) }
                if let chunkUsage = chunk.usage {
                    usage["prompt_tokens"] = chunkUsage.promptTokens
                    usage["completion_tokens"] = chunkUsage.completionTokens
                    usage["total_tokens"] = chunkUsage.totalTokens
                }
            }
        } catch let error as URLError where error.code == .timedOut {
            throw LLMProviderError.timeout
        } catch {
            throw mapStreamingError(error)
        }

        return try finalize(content: content, reasoning: reasoning, model: model, usage: usage)
    }

    @MainActor private func streamAnthropicMessage(request: LLMRequest, onDelta: (@MainActor (String) -> Void)?) async throws -> LLMResponse {
        let service = AnthropicServiceFactory.service(
            apiKey: apiKey,
            basePath: anthropicBasePath(),
            betaHeaders: nil
        )
        let parameter = MessageParameter(
            model: .other(request.model),
            messages: [.init(role: .user, content: .text(request.userPrompt))],
            maxTokens: max(request.maxTokens, 256),
            system: .text(request.systemPrompt),
            stream: true,
            temperature: request.temperature
        )

        var content = ""
        var reasoning = ""
        var model: String?
        var usage: [String: Int] = [:]

        do {
            let stream = try await service.streamMessage(parameter)
            for try await event in stream {
                if let message = event.message {
                    model = message.model
                    if let input = message.usage.inputTokens { usage["input_tokens"] = input }
                    usage["output_tokens"] = message.usage.outputTokens
                }
                if let delta = event.delta {
                    if let text = delta.text {
                        content += text
                        if let onDelta { onDelta(content) }
                    }
                    if let thinking = delta.thinking { reasoning += thinking }
                }
                if let usageInfo = event.usage {
                    if let input = usageInfo.inputTokens { usage["input_tokens"] = input }
                    usage["output_tokens"] = usageInfo.outputTokens
                }
                if event.streamEvent == .messageStop { break }
            }
        } catch let error as URLError where error.code == .timedOut {
            throw LLMProviderError.timeout
        } catch {
            throw mapStreamingError(error)
        }

        if usage["total_tokens"] == nil {
            let total = (usage["input_tokens"] ?? 0) + (usage["output_tokens"] ?? 0)
            if total > 0 { usage["total_tokens"] = total }
        }
        return try finalize(content: content, reasoning: reasoning, model: model, usage: usage)
    }

    private func openAIConfiguration() throws -> OpenAI.Configuration {
        let (scheme, host, port, basePath) = try ProviderURLSplitter.split(baseURL: profile.baseURL, endpoint: profile.chatEndpoint)
        return OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath,
            // 180s inactivity timeout. With streaming, deltas reset this on each
            // chunk so it really only fires when the connection truly stalls.
            timeoutInterval: 180,
            customHeaders: ProviderURLSplitter.extraHeaders(profile.extraHeadersJSON)
        )
    }

    private func anthropicBasePath() -> String {
        // SwiftAnthropic appends "/v1/messages" to the basePath, so we pass only
        // the scheme://host[:port] portion. Trim a trailing slash.
        var base = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    private func finalize(content: String, reasoning: String, model: String?, usage: [String: Int]) throws -> LLMResponse {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if !trimmedContent.isEmpty {
            text = trimmedContent
        } else {
            let trimmedReasoning = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedReasoning.isEmpty else { throw LLMProviderError.emptyOutput }
            text = trimmedReasoning
        }
        return LLMResponse(text: text, model: model, usage: usage)
    }

    private func mapStreamingError(_ error: Error) -> LLMProviderError {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut:
                return .timeout
            case .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed, .cannotConnectToHost:
                return .connectionLost(url.localizedDescription)
            default:
                break
            }
            if let response = url.userInfo["NSURLErrorFailingURLResponseErrorKey"] as? HTTPURLResponse {
                return .invalidStatus(response.statusCode, url.localizedDescription)
            }
            return .connectionLost(url.localizedDescription)
        }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return .invalidStatus(-1, message)
    }
}

/// Splits a base URL + endpoint into the components the MacPaw OpenAI SDK needs.
/// Ported from runse so the streaming URL is built identically. Pure/testable.
enum ProviderURLSplitter {
    static func split(baseURL: String, endpoint: String) throws -> (scheme: String, host: String, port: Int, basePath: String) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMProviderError.invalidURL }
        // Accept "host[:port][/path]" without a scheme; never guess a vendor host.
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let host = url.host,
              !host.isEmpty else {
            throw LLMProviderError.invalidURL
        }
        let scheme = (url.scheme ?? "https").lowercased()
        guard scheme == "https" || scheme == "http" else {
            throw LLMProviderError.invalidURL
        }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        let path = url.path
        // MacPaw/OpenAI tacks "/chat/completions" onto basePath itself, so we
        // strip that suffix if the profile's endpoint includes it.
        let endpointBase: String
        if endpoint.hasSuffix("/chat/completions") {
            endpointBase = String(endpoint.dropLast("/chat/completions".count))
        } else {
            endpointBase = endpoint
        }
        var basePath = path + endpointBase
        while basePath.hasSuffix("/") { basePath.removeLast() }
        return (scheme, host, port, basePath)
    }

    static func extraHeaders(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }
}

/// Builds the JSON body for a provider (documents the wire format and is used by
/// the connectivity smoke test). Mirrors runse's `ProviderRequestFactory.body`.
enum ProviderRequestFactory {
    static func body(profile: ProviderProfile, request: LLMRequest) -> [String: Any] {
        switch profile.kind {
        case .anthropicMessages:
            return [
                "model": request.model,
                "system": request.systemPrompt,
                "max_tokens": request.maxTokens,
                "messages": [["role": "user", "content": request.userPrompt]],
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
}

/// Parses a non-streamed JSON body into an `LLMResponse`. Mirrors runse's
/// `ProviderResponseParser`; kept as a tested utility documenting the wire
/// format (the streaming client uses the SDKs above).
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
            if let value = item.value as? Int { partial[item.key] = value }
            else if let value = item.value as? Double { partial[item.key] = Int(value) }
        } ?? [:]
    }
}
