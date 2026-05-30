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

    // MARK: Presets

    static func openAIPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.openai", name: "OpenAI", kind: .openAICompatible,
                        baseURL: "https://api.openai.com", chatEndpoint: "/v1/chat/completions",
                        model: "gpt-4o-mini")
    }

    static func anthropicPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.anthropic", name: "Anthropic", kind: .anthropicMessages,
                        baseURL: "https://api.anthropic.com", chatEndpoint: "/v1/messages",
                        model: "claude-3-5-haiku-latest")
    }

    static func openRouterPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.openrouter", name: "OpenRouter", kind: .openAICompatible,
                        baseURL: "https://openrouter.ai/api", chatEndpoint: "/v1/chat/completions",
                        model: "openai/gpt-4o-mini")
    }

    static func groqPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.groq", name: "Groq", kind: .openAICompatible,
                        baseURL: "https://api.groq.com/openai", chatEndpoint: "/v1/chat/completions",
                        model: "llama-3.1-8b-instant")
    }

    // China providers — base URLs/endpoints follow the runse project; model IDs
    // are the current flagship-flash tiers. All speak the OpenAI-compatible API
    // and stream via SSE.
    static func deepSeekPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.deepseek", name: "DeepSeek China", kind: .openAICompatible,
                        baseURL: "https://api.deepseek.com", chatEndpoint: "/chat/completions",
                        model: "deepseek-v4-flash")
    }

    static func kimiPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.kimi", name: "Kimi China", kind: .openAICompatible,
                        baseURL: "https://api.moonshot.cn/v1", chatEndpoint: "/chat/completions",
                        model: "kimi-k2.6")
    }

    static func miniMaxPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.minimax", name: "MiniMax China", kind: .openAICompatible,
                        baseURL: "https://api.minimaxi.com/v1", chatEndpoint: "/chat/completions",
                        model: "MiniMax-M2.5")
    }

    static func glmPreset() -> ProviderProfile {
        ProviderProfile(id: "preset.glm", name: "GLM China", kind: .openAICompatible,
                        baseURL: "https://open.bigmodel.cn/api/paas/v4", chatEndpoint: "/chat/completions",
                        model: "glm-5.1")
    }

    /// Built-in starting points the user can pick and then fill in a key.
    static func presets() -> [ProviderProfile] {
        [
            openAIPreset(), anthropicPreset(), openRouterPreset(), groqPreset(),
            deepSeekPreset(), kimiPreset(), miniMaxPreset(), glmPreset(),
        ]
    }
}
