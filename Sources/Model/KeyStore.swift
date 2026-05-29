import Foundation

/// Metadata for an imported SSH private key. The key material itself is NOT
/// stored here — only in the Keychain (see KeyStore).
struct StoredKey: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var type: String // e.g. "Ed25519", "ECDSA P-256"
}

/// Manages imported SSH private keys. Key metadata (name/type) lives in
/// UserDefaults; the secret key text lives in the Keychain, marked
/// `ThisDeviceOnly` so it is never synced to iCloud or included in backups.
final class KeyStore: ObservableObject {
    @Published private(set) var keys: [StoredKey] = []

    private let defaultsKey = "sshKeys"
    private func account(_ id: UUID) -> String { "sshkey." + id.uuidString }

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([StoredKey].self, from: data)
        else { return }
        keys = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Validate and import a private key. Throws SSHKeyError if it can't be
    /// parsed / is unsupported. The key text is stored in the Keychain.
    @discardableResult
    func importKey(name: String, text: String) throws -> StoredKey {
        let parsed = try SSHKeyParser.parse(text) // validates; throws on failure
        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Key \(keys.count + 1)" : name
        let key = StoredKey(name: displayName, type: parsed.type)
        guard Keychain.setPassword(text, account: account(key.id)) else {
            throw SSHKeyError.malformed("couldn't store key in Keychain")
        }
        keys.append(key)
        persist()
        return key
    }

    func rename(_ key: StoredKey, to name: String) {
        guard let idx = keys.firstIndex(where: { $0.id == key.id }) else { return }
        keys[idx].name = name
        persist()
    }

    func delete(_ key: StoredKey) {
        keys.removeAll { $0.id == key.id }
        Keychain.deletePassword(account: account(key.id))
        persist()
    }

    func text(for id: UUID) -> String? {
        Keychain.password(account: account(id))
    }

    func key(for id: UUID) -> StoredKey? {
        keys.first { $0.id == id }
    }
}
