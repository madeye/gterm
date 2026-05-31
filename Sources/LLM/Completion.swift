import Foundation

/// The context handed to the LLM to predict a completion: what the user has
/// typed so far, their recent command history, and the visible terminal text.
struct CompletionContext: Equatable, Sendable {
    var currentLine: String
    var history: [String] // most-recent first
    var terminalText: String

    init(currentLine: String, history: [String], terminalText: String) {
        self.currentLine = currentLine
        self.history = history
        self.terminalText = terminalText
    }
}

/// Builds the `LLMRequest` for a completion. Pure and testable: the prompt is a
/// deterministic function of the context.
enum CompletionPromptFactory {
    static let systemPrompt = """
    You are a shell command autocompletion engine inside an SSH terminal on iOS.
    Using the user's recent command history and the current terminal screen,
    predict the single most likely complete command line the user is typing.

    Rules:
    - Output ONLY the full command line — nothing else.
    - No explanation, no markdown, no code fences, no surrounding quotes.
    - The output MUST begin with the exact characters the user has already typed.
    - Output a single line. If you cannot make a confident prediction, repeat the\
     user's input unchanged.
    """

    static func request(
        context: CompletionContext,
        model: String,
        maxHistory: Int = 20,
        maxTerminalChars: Int = 2000
    ) -> LLMRequest {
        let recent = context.history.prefix(maxHistory)
        let historyBlock = recent.isEmpty ? "(none)" : recent.reversed().joined(separator: "\n")
        // The prompt line is at the BOTTOM of the screen, so keep the tail.
        let terminalTail = String(context.terminalText.suffix(maxTerminalChars))

        let userPrompt = """
        Recent commands (most recent last):
        \(historyBlock)

        Current terminal screen (tail):
        \(terminalTail)

        The user has typed this so far — complete it into a full command line:
        \(context.currentLine)
        """
        return LLMRequest(model: model, systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: 0.1, maxTokens: 64)
    }
}

/// Turns raw model output into the suffix to insert after the current line.
/// Pure and testable.
enum CompletionSanitizer {
    static func suffix(fromOutput raw: String, currentLine: String) -> String {
        let defenced = stripFenceLines(raw)
        guard var line = firstNonBlankLine(defenced) else { return "" }

        line = trimTrailingWhitespace(line)
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        line = trimTrailingWhitespace(line)

        // Preferred contract: the model echoes the full command line, so we
        // return only the part beyond what's already typed (this preserves any
        // needed leading space, e.g. "git" -> " status").
        if line.hasPrefix(currentLine) {
            return String(line.dropFirst(currentLine.count))
        }
        // Fallback: the model returned just the suffix.
        return line.trimmingCharacters(in: .whitespaces)
    }

    private static func stripFenceLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }

    private static func firstNonBlankLine(_ text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func trimTrailingWhitespace(_ text: String) -> String {
        var result = text
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        return result
    }
}

/// Decides whether a completion request is worth making for the current line.
enum CompletionPolicy {
    static let maxLineLength = 512

    static func shouldRequest(currentLine: String) -> Bool {
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard currentLine.count <= maxLineLength else { return false }
        return true
    }
}
