import SwiftUI

/// The home screen: a list of saved SSH connections. Tap to connect (prompting
/// for a password if none is saved), swipe to edit/delete, "+" to add.
struct ConnectionListView: View {
    @ObservedObject var store: ConnectionStore
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
                        Button(role: .destructive) { store.delete(conn) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editing = conn } label: {
                            Label("Edit", systemImage: "pencil")
                        }.tint(.blue)
                    }
                }
            }
            .navigationTitle("gterm")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = SavedConnection() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { conn in
                AddConnectionView(store: store, connection: conn)
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
                    onConnect(sshConnection(conn, password: promptPassword))
                    promptPassword = ""
                }
                Button("Cancel", role: .cancel) { promptPassword = "" }
            } message: { conn in
                Text("Enter the password for \(conn.username)@\(conn.host).")
            }
        }
    }

    private func connect(_ conn: SavedConnection) {
        if let saved = store.savedPassword(for: conn) {
            onConnect(sshConnection(conn, password: saved))
        } else {
            promptPassword = ""
            passwordPromptFor = conn
        }
    }

    private func sshConnection(_ c: SavedConnection, password: String) -> SSHConnection {
        SSHConnection(host: c.host, port: c.port, username: c.username, password: password)
    }
}
