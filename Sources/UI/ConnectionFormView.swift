import SwiftUI

/// A simple SSH connection form. Persistence, saved hosts, key auth, and
/// known-hosts management come in a later phase.
struct ConnectionFormView: View {
    let onConnect: (SSHConnection) -> Void

    @AppStorage("lastHost") private var host: String = ""
    @AppStorage("lastPort") private var port: String = "22"
    @AppStorage("lastUser") private var username: String = ""
    @State private var password: String = ""

    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("hostname or IP", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("port", text: $port)
                        .keyboardType(.numberPad)
                }
                Section("Authentication") {
                    TextField("username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("password", text: $password)
                        .textContentType(.password)
                }
                Section {
                    Button {
                        onConnect(SSHConnection(
                            host: host.trimmingCharacters(in: .whitespaces),
                            port: Int(port) ?? 22,
                            username: username.trimmingCharacters(in: .whitespaces),
                            password: password
                        ))
                    } label: {
                        Label("Connect", systemImage: "terminal")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle("gterm")
        }
    }
}
