import SwiftUI

/// The "Hosts" tab: saved SSH connections. Tap to connect (resolving selected
/// keys and any saved password; prompting for a password only if there's no
/// key and none saved). Swipe to edit/delete, "+" to add.
struct ConnectionListView: View {
    @ObservedObject var store: ConnectionStore
    @ObservedObject var keyStore: KeyStore
    @ObservedObject var forwardStore: PortForwardStore
    let onConnect: (SSHConnection) -> Void

    @State private var editing: SavedConnection?
    @State private var passwordPromptFor: SavedConnection?
    @State private var promptPassword = ""

    var body: some View {
        NavigationStack {
            List {
                if store.connections.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "terminal",
                        description: Text("Tap + to add an SSH host.")
                    )
                }
                ForEach(store.connections) { conn in
                    Button { connect(conn) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conn.title).font(.headline)
                            Text(conn.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(conn)
                            forwardStore.deleteForwards(for: conn.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editing = conn } label: {
                            Label("Edit", systemImage: "pencil")
                        }.tint(.blue)
                    }
                }
            }
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = SavedConnection() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { conn in
                AddConnectionView(store: store, keyStore: keyStore, forwardStore: forwardStore, connection: conn)
            }
            .alert(
                "Password",
                isPresented: Binding(
                    get: { passwordPromptFor != nil },
                    set: { if !$0 { passwordPromptFor = nil } }
                ),
                presenting: passwordPromptFor
            ) { conn in
                SecureField("password", text: $promptPassword)
                Button("Connect") {
                    onConnect(makeConnection(conn, password: promptPassword))
                    promptPassword = ""
                }
                Button("Cancel", role: .cancel) { promptPassword = "" }
            } message: { conn in
                Text("Enter the password for \(conn.username)@\(conn.host).")
            }
        }
    }

    private func keyTexts(for conn: SavedConnection) -> [String] {
        conn.keyIDs.compactMap { keyStore.text(for: $0) }
    }

    private func makeConnection(_ conn: SavedConnection, password: String) -> SSHConnection {
        SSHConnection(
            host: conn.host, port: conn.port, username: conn.username,
            password: password, privateKeys: keyTexts(for: conn), savedID: conn.id)
    }

    private func connect(_ conn: SavedConnection) {
        let keys = keyTexts(for: conn)
        if let saved = store.savedPassword(for: conn) {
            onConnect(makeConnection(conn, password: saved))
        } else if !keys.isEmpty {
            onConnect(makeConnection(conn, password: ""))
        } else {
            promptPassword = ""
            passwordPromptFor = conn
        }
    }
}
