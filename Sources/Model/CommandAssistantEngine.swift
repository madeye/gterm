import Foundation

/// Turns a natural-language request into a terminal command via the configured
/// LLM provider. The pure prompt/sanitize logic lives in the LLM core
/// (CommandPromptFactory / CommandSanitizer); this only wires it to the provider.
@MainActor
final class CommandAssistantEngine {
    private let store: ProviderStore

    init(store: ProviderStore = .shared) {
        self.store = store
    }

    enum AssistantError: LocalizedError {
        case notConfigured
        case provider(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Set up an AI provider in the AI tab first."
            case .provider(let message): return message
            case .empty: return "The AI didn't return a command. Try rephrasing."
            }
        }
    }

    /// Generate a command for `instruction`, using the terminal text and recent
    /// history as context. Returns the cleaned command or a descriptive error.
    func generateCommand(
        instruction: String,
        terminalText: String,
        history: [String]
    ) async -> Result<String, AssistantError> {
        guard let provider = store.activeProvider,
              let apiKey = store.apiKey(for: provider.id),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failure(.notConfigured)
        }

        let client = HTTPProviderClient(profile: provider, apiKey: apiKey)
        let context = CommandContext(instruction: instruction, history: history, terminalText: terminalText)
        let request = CommandPromptFactory.request(context: context, model: provider.model)

        do {
            let response = try await client.complete(request)
            let command = CommandSanitizer.command(fromOutput: response.text)
            return command.isEmpty ? .failure(.empty) : .success(command)
        } catch let error as LLMProviderError {
            return .failure(.provider(error.errorDescription ?? "Provider error"))
        } catch {
            return .failure(.provider(error.localizedDescription))
        }
    }
}
