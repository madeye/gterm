import Foundation

/// Manages user-configured LLM providers for AI autocompletion. Profile
/// metadata (name, URL, model) lives in UserDefaults; each provider's API key
/// lives in the Keychain keyed by the profile id, mirroring how SSH passwords
/// are stored. A single shared instance is used app-wide so the terminal layer
/// and the settings UI stay in sync.
final class ProviderStore: ObservableObject {
    static let shared = ProviderStore()

    @Published private(set) var profiles: [ProviderProfile] = []
    @Published var selectedProviderID: String?
    @Published var isEnabled: Bool

    private let profilesKey = "llmProviders"
    private let selectedKey = "llmSelectedProvider"
    private let enabledKey = "llmCompletionEnabled"
    private func keychainAccount(_ id: String) -> String { "llmkey." + id }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        selectedProviderID = UserDefaults.standard.string(forKey: selectedKey)
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([ProviderProfile].self, from: data)
        else { return }
        profiles = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    /// The provider used for completions: the explicit selection, else the first.
    var activeProvider: ProviderProfile? {
        if let id = selectedProviderID, let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    func select(_ id: String?) {
        selectedProviderID = id
        UserDefaults.standard.set(id, forKey: selectedKey)
    }

    /// Add or update a provider (matched by id). Optionally set its API key.
    func save(_ profile: ProviderProfile, apiKey: String?) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
            if selectedProviderID == nil { select(profile.id) }
        }
        if let apiKey {
            setAPIKey(apiKey, for: profile.id)
        }
        persist()
    }

    func delete(_ profile: ProviderProfile) {
        profiles.removeAll { $0.id == profile.id }
        Keychain.deletePassword(account: keychainAccount(profile.id))
        if selectedProviderID == profile.id { select(profiles.first?.id) }
        persist()
    }

    func setAPIKey(_ key: String, for id: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.deletePassword(account: keychainAccount(id))
        } else {
            Keychain.setPassword(trimmed, account: keychainAccount(id))
        }
    }

    func apiKey(for id: String) -> String? {
        Keychain.password(account: keychainAccount(id))
    }

    /// True when AI completion is fully usable: enabled, a provider is selected,
    /// and that provider has a non-empty API key.
    var isReady: Bool {
        isEnabled && hasUsableProvider
    }

    /// True when a provider is selected and has a non-empty API key, regardless
    /// of the autocomplete toggle. The command assistant uses this — it works
    /// even when inline completion is turned off.
    var hasUsableProvider: Bool {
        guard let provider = activeProvider else { return false }
        let key = apiKey(for: provider.id)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }
}
