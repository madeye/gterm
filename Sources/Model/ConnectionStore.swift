import Foundation

/// A persisted SSH connection. The password is never stored here; it lives in
/// the Keychain keyed by `id` when `savePassword` is set.
struct SavedConnection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var savePassword: Bool = true

    /// A display label, falling back to user@host when unnamed.
    var title: String {
        name.isEmpty ? "\(username)@\(host)" : name
    }

    var subtitle: String {
        port == 22 ? "\(username)@\(host)" : "\(username)@\(host):\(port)"
    }
}

/// Stores saved connections (metadata in UserDefaults, passwords in Keychain).
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [SavedConnection] = []

    private let key = "savedConnections"

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

    func upsert(_ connection: SavedConnection, password: String?) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
        } else {
            connections.append(connection)
        }
        if connection.savePassword, let password, !password.isEmpty {
            Keychain.setPassword(password, account: connection.id.uuidString)
        } else if !connection.savePassword {
            Keychain.deletePassword(account: connection.id.uuidString)
        }
        persist()
    }

    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        Keychain.deletePassword(account: connection.id.uuidString)
        persist()
    }

    func savedPassword(for connection: SavedConnection) -> String? {
        Keychain.password(account: connection.id.uuidString)
    }
}
