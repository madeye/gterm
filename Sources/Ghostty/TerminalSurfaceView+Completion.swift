import UIKit
import GhosttyKit

/// LLM autocompletion wiring for the terminal surface. The local command-line
/// mirror (see TerminalSurfaceView) already tracks what the user is typing; here
/// we read the visible screen and ask the configured provider to predict the
/// full command, surfacing it as a distinct chip in the accessory bar.
extension TerminalSurfaceView {
    /// Read the visible terminal text (the viewport) as a string. Used as LLM
    /// context. Returns "" if there is no surface or nothing to read.
    func readVisibleText() -> String {
        guard let surface = ghosttySurface else { return "" }
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0
            ),
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return "" }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let ptr = text.text, text.text_len > 0 else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: ptr, count: Int(text.text_len)), as: UTF8.self)
    }

    /// Kick off an AI completion for the current line, if a provider is ready.
    /// The result is shown as an AI chip; stale results (the line changed) are
    /// dropped. Safe to call on every keystroke — the engine debounces/cancels.
    func requestAICompletion(currentLine: String) {
        accessory.setAISuggestion(nil)
        guard ProviderStore.shared.isReady,
              CompletionPolicy.shouldRequest(currentLine: currentLine) else {
            completionEngine.cancel()
            return
        }
        let context = CompletionContext(
            currentLine: currentLine,
            history: CommandHistory.shared.recent(limit: 20),
            terminalText: readVisibleText()
        )
        completionEngine.requestCompletion(context: context) { [weak self] full in
            guard let self, let full, self.liveCurrentLine == currentLine else { return }
            self.accessory.setAISuggestion(full)
        }
    }
}
