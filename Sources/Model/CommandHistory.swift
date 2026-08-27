import Foundation

/// Records command lines the user enters in the terminal and serves prefix-based
/// autocomplete suggestions for the accessory keyboard.
///
/// This is a best-effort *local* mirror of what the user types — it does not
/// read the remote shell's own history. Entries are capped, deduplicated
/// (most-recent first), and persisted in UserDefaults so suggestions survive
/// app restarts. Stored as plain text; `CommandHistoryPolicy` drops obvious
/// secret-bearing lines before they are saved.
final class CommandHistory {
    static let shared = CommandHistory()

    private let defaultsKey = "commandHistory"
    private let defaults: UserDefaults
    private let maxEntries = 200

    private var entries: [String] = [] // most-recent first

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        if let saved = defaults.stringArray(forKey: defaultsKey) {
            entries = saved
        }
    }

    private func persist() {
        defaults.set(entries, forKey: defaultsKey)
    }

    /// Record a completed command line. Blank/too-short/secret-looking lines
    /// are ignored; duplicates move to the front so recent commands rank highest.
    func record(_ line: String) {
        guard CommandHistoryPolicy.shouldRecord(line) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    /// Suggestions whose text begins with `prefix` (excluding an exact match),
    /// most-recent first, capped at `limit`.
    func suggestions(prefix: String, limit: Int = 6) -> [String] {
        guard !prefix.isEmpty else { return [] }
        var out: [String] = []
        for entry in entries where entry.count > prefix.count && entry.hasPrefix(prefix) {
            out.append(entry)
            if out.count >= limit { break }
        }
        return out
    }

    /// The most recent entries (most-recent first), for LLM context.
    func recent(limit: Int = 20) -> [String] {
        Array(entries.prefix(limit))
    }

    /// Forget all recorded history.
    func clear() {
        entries.removeAll()
        persist()
    }
}

/// Decides whether a committed line is safe to persist as shell history.
enum CommandHistoryPolicy {
    static let minLength = 2

    static func shouldRecord(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return false }
        let lower = trimmed.lowercased()
        if lower == "passwd" || lower.hasPrefix("passwd ") { return false }
        if lower.hasPrefix("sshpass ") { return false }
        return !containsSecretAssignment(trimmed)
    }

    /// True when a whitespace-delimited token looks like `NAME=value` and NAME
    /// is a password/secret/token/api-key style identifier.
    private static func containsSecretAssignment(_ line: String) -> Bool {
        for token in line.split(whereSeparator: { $0.isWhitespace }) {
            guard let eq = token.firstIndex(of: "=") else { continue }
            let name = token[..<eq].lowercased()
            if name.contains("password") || name.contains("passwd")
                || name.contains("secret") || name.contains("token")
                || name.contains("apikey") || name.contains("api_key")
                || name.contains("api-key") {
                return true
            }
        }
        return false
    }
}
