import Foundation

/// A persisted port-forward configuration (metadata only, no secrets). Mirrors
/// `SavedConnection`/`ConnectionStore`: configs live in UserDefaults JSON keyed
/// by the owning connection's id. Runtime status is never persisted here.
struct PortForward: Identifiable, Codable, Equatable {
    var id = UUID()
    /// FK -> SavedConnection.id (NOT defaulted: a forward always belongs to a connection).
    var connectionID: UUID
    var name: String = ""
    /// 127.0.0.1:localPort listener on the device.
    var localPort: Int = 8080
    /// Target host as seen FROM the SSH server.
    var remoteHost: String = "127.0.0.1"
    var remotePort: Int = 80
    /// Bind the listener as soon as the session connects.
    var autoStart: Bool = false
    /// "http" | "https"; builds the browser URL.
    var scheme: String = "http"

    var title: String { name.isEmpty ? "\(localPort) \u{2192} \(remoteHost):\(remotePort)" : name }
    var subtitle: String { "127.0.0.1:\(localPort) \u{2192} \(remoteHost):\(remotePort)" }
    var localURL: URL? { URL(string: "\(scheme)://127.0.0.1:\(localPort)/") }
    var isWeb: Bool { scheme == "http" || scheme == "https" }
}

/// Stores port-forward configs (metadata in UserDefaults). No Keychain: forwards
/// hold no secrets. Keyed conceptually by `connectionID`.
final class PortForwardStore: ObservableObject {
    @Published private(set) var forwards: [PortForward] = []

    private let key = "portForwards"

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PortForward].self, from: data)
        else { return }
        forwards = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(forwards) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Forwards belonging to a connection, sorted by local port.
    func forwards(for connectionID: UUID) -> [PortForward] {
        forwards
            .filter { $0.connectionID == connectionID }
            .sorted { $0.localPort < $1.localPort }
    }

    /// Upsert by id, then persist. Local-port uniqueness within a connection is
    /// enforced in the editor UI, not here.
    func save(_ f: PortForward) {
        if let idx = forwards.firstIndex(where: { $0.id == f.id }) {
            forwards[idx] = f
        } else {
            forwards.append(f)
        }
        persist()
    }

    func delete(_ f: PortForward) {
        forwards.removeAll { $0.id == f.id }
        persist()
    }

    /// Cascade: remove all forwards belonging to a (deleted) connection.
    func deleteForwards(for connectionID: UUID) {
        forwards.removeAll { $0.connectionID == connectionID }
        persist()
    }
}
