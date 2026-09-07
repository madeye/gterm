import Combine
import Foundation

/// A persisted SSH connection. Secrets are never stored here: the password (if
/// saved) lives in the Keychain keyed by `id`; private keys are referenced by
/// `keyIDs` and managed by KeyStore.
struct SavedConnection: Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    /// Private keys (from KeyStore) this connection will try, in order.
    var keyIDs: [UUID] = []
    /// Whether a password is saved in the Keychain for this connection.
    var savePassword: Bool = false
    /// When true, the SSH PTY execs `herdr` (start or attach to the default
    /// background session) instead of a login shell. Off by default so hosts
    /// without Herdr on `PATH` keep working.
    var attachHerdr: Bool = false

    var title: String { name.isEmpty ? "\(username)@\(host)" : name }

    var subtitle: String {
        let hostPart = port == 22 ? "\(username)@\(host)" : "\(username)@\(host):\(port)"
        if keyIDs.isEmpty { return hostPart }
        return "\(hostPart) · \(keyIDs.count) key\(keyIDs.count == 1 ? "" : "s")"
    }
}

extension SavedConnection: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, keyIDs, savePassword, attachHerdr
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        keyIDs = try c.decodeIfPresent([UUID].self, forKey: .keyIDs) ?? []
        savePassword = try c.decodeIfPresent(Bool.self, forKey: .savePassword) ?? false
        attachHerdr = try c.decodeIfPresent(Bool.self, forKey: .attachHerdr) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username)
        try c.encode(keyIDs, forKey: .keyIDs)
        try c.encode(savePassword, forKey: .savePassword)
        try c.encode(attachHerdr, forKey: .attachHerdr)
    }
}

/// Stores saved connections (metadata in UserDefaults, password in Keychain).
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [SavedConnection] = []

    private let key = "savedConnections"
    private let defaults: UserDefaults
    private func passwordAccount(_ c: SavedConnection) -> String { c.id.uuidString }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? SavedConnectionCodec.decode(data)
        else { return }
        connections = decoded
    }

    private func persist() {
        if let data = try? SavedConnectionCodec.encode(connections) {
            defaults.set(data, forKey: key)
        }
    }

    func save(_ connection: SavedConnection, password: String?) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
        } else {
            connections.append(connection)
        }
        if connection.savePassword, let password, !password.isEmpty {
            Keychain.setPassword(password, account: passwordAccount(connection))
        } else if !connection.savePassword {
            Keychain.deletePassword(account: passwordAccount(connection))
        }
        persist()
    }

    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        Keychain.deletePassword(account: passwordAccount(connection))
        persist()
    }

    func savedPassword(for connection: SavedConnection) -> String? {
        Keychain.password(account: passwordAccount(connection))
    }

    /// Remove references to a key that has been deleted from the KeyStore.
    func removeKeyReference(_ keyID: UUID) {
        var changed = false
        for i in connections.indices where connections[i].keyIDs.contains(keyID) {
            connections[i].keyIDs.removeAll { $0 == keyID }
            changed = true
        }
        if changed { persist() }
    }
}
