import Foundation

/// Records command lines the user enters in the terminal and serves prefix-based
/// autocomplete suggestions for the accessory keyboard.
///
/// This is a best-effort *local* mirror of what the user types — it does not
/// read the remote shell's own history. Entries are capped, deduplicated
/// (most-recent first), and persisted in UserDefaults so suggestions survive
/// app restarts. Stored as plain text; callers should avoid recording lines
/// that are obviously secrets (handled at the call site).
final class CommandHistory {
    static let shared = CommandHistory()

    private let defaultsKey = "commandHistory"
    private let maxEntries = 200
    private let minLength = 2

    private var entries: [String] = [] // most-recent first

    init() { load() }

    private func load() {
        if let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            entries = saved
        }
    }

    private func persist() {
        UserDefaults.standard.set(entries, forKey: defaultsKey)
    }

    /// Record a completed command line. Blank/too-short lines are ignored;
    /// duplicates move to the front so recent commands rank highest.
    func record(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= minLength else { return }
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
