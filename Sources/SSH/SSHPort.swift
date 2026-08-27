import Foundation

/// TCP port numbers accepted for SSH connections and similar UI fields.
enum SSHPort {
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...65535).contains(value) else { return nil }
        return value
    }
}
