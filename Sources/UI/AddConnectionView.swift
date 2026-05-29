import SwiftUI

/// Add or edit a saved SSH connection. A connection can select any number of
/// private keys (from the Keys tab) and/or use a password.
struct AddConnectionView: View {
    @ObservedObject var store: ConnectionStore
    @ObservedObject var keyStore: KeyStore
    @Environment(\.dismiss) private var dismiss

    @State private var connection: SavedConnection
    @State private var portText: String
    @State private var password: String

    init(store: ConnectionStore, keyStore: KeyStore, connection: SavedConnection) {
        self.store = store
        self.keyStore = keyStore
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
                    TextField("username", text: $connection.username)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }

                Section {
                    if keyStore.keys.isEmpty {
                        Text("No keys imported. Add them in the Keys tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keyStore.keys) { key in
                            Button {
                                toggle(key.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key.name).foregroundStyle(.primary)
                                        Text(key.type).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if connection.keyIDs.contains(key.id) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Private Keys")
                } footer: {
                    Text("Selected keys are tried in order, before the password.")
                }

                Section("Password") {
                    SecureField("password (optional)", text: $password)
                    Toggle("Save password", isOn: $connection.savePassword)
                }
            }
            .navigationTitle(connection.host.isEmpty ? "New Connection" : "Edit Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let idx = connection.keyIDs.firstIndex(of: id) {
            connection.keyIDs.remove(at: idx)
        } else {
            connection.keyIDs.append(id)
        }
    }

    private func save() {
        connection.host = connection.host.trimmingCharacters(in: .whitespaces)
        connection.username = connection.username.trimmingCharacters(in: .whitespaces)
        connection.port = Int(portText) ?? 22
        store.save(connection, password: password)
        dismiss()
    }
}
