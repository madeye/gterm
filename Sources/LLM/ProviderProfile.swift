import Foundation

/// The wire-protocol shape a provider speaks. Mirrors the kinds used by the
/// runse project so the same request/response handling applies.
enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case anthropicMessages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropicMessages: return "Anthropic Messages"
        }
    }
}

/// A user-configured LLM provider. The API key is NOT stored here — it lives in
/// the Keychain keyed by `id` (see ProviderStore), matching how gterm stores
/// SSH passwords. Everything else is plain Codable metadata in UserDefaults.
struct ProviderProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var chatEndpoint: String
    var model: String
    var extraHeadersJSON: String

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: ProviderKind,
        baseURL: String,
        chatEndpoint: String,
        model: String,
        extraHeadersJSON: String = "{}"
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.chatEndpoint = chatEndpoint
        self.model = model
        self.extraHeadersJSON = extraHeadersJSON
    }

    static func openAIPreset() -> ProviderProfile {
        ProviderProfile(
            id: "preset.openai",
            name: "OpenAI",
            kind: .openAICompatible,
            baseURL: "https://api.openai.com",
            chatEndpoint: "/v1/chat/completions",
            model: "gpt-4o-mini"
        )
    }

    static func anthropicPreset() -> ProviderProfile {
        ProviderProfile(
            id: "preset.anthropic",
            name: "Anthropic",
            kind: .anthropicMessages,
            baseURL: "https://api.anthropic.com",
            chatEndpoint: "/v1/messages",
            model: "claude-3-5-haiku-latest"
        )
    }

    static func openRouterPreset() -> ProviderProfile {
        ProviderProfile(
            id: "preset.openrouter",
            name: "OpenRouter",
            kind: .openAICompatible,
            baseURL: "https://openrouter.ai/api",
            chatEndpoint: "/v1/chat/completions",
            model: "openai/gpt-4o-mini"
        )
    }

    static func groqPreset() -> ProviderProfile {
        ProviderProfile(
            id: "preset.groq",
            name: "Groq",
            kind: .openAICompatible,
            baseURL: "https://api.groq.com/openai",
            chatEndpoint: "/v1/chat/completions",
            model: "llama-3.1-8b-instant"
        )
    }

    /// Built-in starting points the user can pick and then fill in a key/model.
    static func presets() -> [ProviderProfile] {
        [openAIPreset(), anthropicPreset(), openRouterPreset(), groqPreset()]
    }
}
