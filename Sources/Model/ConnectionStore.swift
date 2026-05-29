import Foundation

/// A persisted SSH connection. Secrets are never stored here: the password (if
/// saved) lives in the Keychain keyed by `id`; private keys are referenced by
/// `keyIDs` and managed by KeyStore.
struct SavedConnection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    /// Private keys (from KeyStore) this connection will try, in order.
    var keyIDs: [UUID] = []
    /// Whether a password is saved in the Keychain for this connection.
    var savePassword: Bool = false

    var title: String { name.isEmpty ? "\(username)@\(host)" : name }

    var subtitle: String {
        let hostPart = port == 22 ? "\(username)@\(host)" : "\(username)@\(host):\(port)"
        if keyIDs.isEmpty { return hostPart }
        return "\(hostPart) · \(keyIDs.count) key\(keyIDs.count == 1 ? "" : "s")"
    }
}

/// Stores saved connections (metadata in UserDefaults, password in Keychain).
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [SavedConnection] = []

    private let key = "savedConnections"
    private func passwordAccount(_ c: SavedConnection) -> String { c.id.uuidString }

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedConnection].self, from: data)
        else { return }
        connections = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: key)
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
