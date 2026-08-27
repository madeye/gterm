import Foundation

/// Context for translating a natural-language request into terminal commands:
/// the user's request plus the recent command history and visible terminal text.
struct CommandContext: Equatable, Sendable {
    var instruction: String
    var history: [String] // most-recent first
    var terminalText: String

    init(instruction: String, history: [String], terminalText: String) {
        self.instruction = instruction
        self.history = history
        self.terminalText = terminalText
    }
}

/// Builds the `LLMRequest` that asks the model to turn a request into a command.
/// Pure and testable.
enum CommandPromptFactory {
    static let systemPrompt = """
    You convert a user's natural-language request into shell command(s) to run in
    their terminal on iOS. The user is often inside a tmux session.

    Rules:
    - Output ONLY the command(s) to run — no explanation, no markdown, no code
      fences, no shell prompt characters ($ or #), no surrounding quotes.
    - Prefer a single line; combine steps with && or ; when reasonable.
    - For window/pane/session actions use tmux subcommands, e.g.
      `tmux new-window`, `tmux kill-window`, `tmux split-window -h`.
    - Keep it short. Do not include destructive commands (rm -rf, mkfs, dd, …)
      unless the request explicitly and unambiguously asks for them.
    """

    static func request(
        context: CommandContext,
        model: String,
        maxHistory: Int = 15,
        maxTerminalChars: Int = 1500
    ) -> LLMRequest {
        let recent = context.history.prefix(maxHistory)
        let historyBlock = recent.isEmpty ? "(none)" : recent.reversed().joined(separator: "\n")
        let terminalTail = String(context.terminalText.suffix(maxTerminalChars))

        let userPrompt = """
        Recent commands (most recent last):
        \(historyBlock)

        Current terminal screen (tail):
        \(terminalTail)

        Request:
        \(context.instruction)
        """
        return LLMRequest(model: model, systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: 0.1, maxTokens: 256)
    }
}

/// Extracts the runnable command(s) from raw model output. Pure and testable.
enum CommandSanitizer {
    static func command(fromOutput raw: String) -> String {
        // Models often wrap the command in a fenced block, sometimes with prose
        // around it. Prefer the fenced content when present.
        if let fenced = fencedBlock(in: raw) {
            return cleanLines(fenced)
        }
        return cleanLines(raw)
    }

    private static func fencedBlock(in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inside = false
        var collected: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                if inside { return collected.joined(separator: "\n") } // closing fence
                inside = true
                continue
            }
            if inside { collected.append(line) }
        }
        return nil
    }

    private static func cleanLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map(stripLine)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        s = unwrapSurroundingQuotes(s)
        for prefix in ["$ ", "# ", "% "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        return unwrapSurroundingQuotes(s)
    }

    /// Unwrap one matching pair of quotes around the whole line.
    static func unwrapSurroundingQuotes(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last else { return text }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(text.dropFirst().dropLast())
        }
        return text
    }
}

/// A one-tap deterministic command (no LLM needed) for common terminal actions.
struct QuickCommand: Identifiable, Equatable, Sendable {
    var id: String { title }
    var title: String
    var systemImage: String
    var command: String
    var isDestructive: Bool = false
}

enum QuickCommands {
    static let tmux: [QuickCommand] = [
        QuickCommand(title: "New Window", systemImage: "plus.rectangle", command: "tmux new-window"),
        QuickCommand(title: "Close Window", systemImage: "xmark.rectangle", command: "tmux kill-window", isDestructive: true),
        QuickCommand(title: "Next", systemImage: "arrow.right", command: "tmux next-window"),
        QuickCommand(title: "Prev", systemImage: "arrow.left", command: "tmux previous-window"),
        QuickCommand(title: "Split →", systemImage: "rectangle.split.2x1", command: "tmux split-window -h"),
        QuickCommand(title: "Split ↓", systemImage: "rectangle.split.1x2", command: "tmux split-window -v"),
        QuickCommand(title: "Detach", systemImage: "rectangle.portrait.and.arrow.right", command: "tmux detach"),
    ]

    static let shell: [QuickCommand] = [
        QuickCommand(title: "List", systemImage: "list.bullet", command: "ls -la"),
        QuickCommand(title: "Disk", systemImage: "internaldrive", command: "df -h"),
        QuickCommand(title: "Processes", systemImage: "cpu", command: "ps aux | sort -nrk 3 | head -10"),
        QuickCommand(title: "Clear", systemImage: "clear", command: "clear"),
    ]
}
