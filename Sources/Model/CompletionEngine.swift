import Foundation

/// Orchestrates an async LLM completion for the current command line: debounces
/// rapid keystrokes, cancels any in-flight request, and delivers the predicted
/// full command line back on the main actor. The pure decision/prompt/sanitize
/// logic lives in the LLM core (CompletionPolicy / CompletionPromptFactory /
/// CompletionSanitizer); this type only wires them to the provider + network.
@MainActor
final class CompletionEngine {
    private let store: ProviderStore
    private var task: Task<Void, Never>?

    /// Debounce so we don't fire a request on every keystroke.
    private let debounceNanos: UInt64

    init(store: ProviderStore = .shared, debounceNanos: UInt64 = 350_000_000) {
        self.store = store
        self.debounceNanos = debounceNanos
    }

    /// Request a completion. Cancels any pending request first. `onResult` is
    /// called on the main actor with the predicted full command line, or nil if
    /// no suggestion is available. Only fires when the store is ready and the
    /// line is worth completing.
    func requestCompletion(context: CompletionContext, onResult: @escaping (String?) -> Void) {
        task?.cancel()

        guard store.isReady,
              CompletionPolicy.shouldRequest(currentLine: context.currentLine),
              let provider = store.activeProvider,
              let apiKey = store.apiKey(for: provider.id),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            onResult(nil)
            return
        }

        let client = HTTPProviderClient(profile: provider, apiKey: apiKey)
        let request = CompletionPromptFactory.request(context: context, model: provider.model)
        let currentLine = context.currentLine
        let debounce = debounceNanos

        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounce)
            if Task.isCancelled { return }
            do {
                let response = try await client.complete(request)
                if Task.isCancelled { return }
                let suffix = CompletionSanitizer.suffix(fromOutput: response.text, currentLine: currentLine)
                guard !suffix.isEmpty else { onResult(nil); return }
                onResult(currentLine + suffix)
            } catch {
                if !Task.isCancelled { onResult(nil) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
