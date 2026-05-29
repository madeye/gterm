import SwiftUI

/// Add or edit a saved SSH connection.
struct AddConnectionView: View {
    @ObservedObject var store: ConnectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var connection: SavedConnection
    @State private var portText: String
    @State private var password: String

    init(store: ConnectionStore, connection: SavedConnection) {
        self.store = store
        _connection = State(initialValue: connection)
        _portText = State(initialValue: String(connection.port))
        _password = State(initialValue: store.savedPassword(for: connection) ?? "")
    }

    private var isValid: Bool {
        !connection.host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !connection.username.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(portText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("name (optional)", text: $connection.name)
                    TextField("host", text: $connection.host)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("port", text: $portText).keyboardType(.numberPad)
                }
                Section("Authentication") {
                    TextField("username", text: $connection.username)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("password", text: $password)
                    Toggle("Save password", isOn: $connection.savePassword)
                }
            }
            .navigationTitle(connection.host.isEmpty ? "New Connection" : "Edit Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        connection.host = connection.host.trimmingCharacters(in: .whitespaces)
        connection.username = connection.username.trimmingCharacters(in: .whitespaces)
        connection.port = Int(portText) ?? 22
        store.upsert(connection, password: connection.savePassword ? password : nil)
        dismiss()
    }
}
