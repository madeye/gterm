import SwiftUI

/// Form sheet to add or edit a single SSH local port forward (ssh -L), mirroring
/// the shape of `AddConnectionView`. Local-port uniqueness within a connection is
/// enforced here (via `existingPorts`), not in the store.
struct PortForwardEditView: View {
    @ObservedObject var store: PortForwardStore
    /// Local ports already used by sibling forwards on the same connection,
    /// excluding this forward's own port.
    let existingPorts: [Int]
    @Environment(\.dismiss) private var dismiss

    @State private var forward: PortForward
    @State private var localPortText: String
    @State private var remotePortText: String

    init(store: PortForwardStore, existingPorts: [Int], forward: PortForward) {
        self.store = store
        self.existingPorts = existingPorts
        _forward = State(initialValue: forward)
        _localPortText = State(initialValue: String(forward.localPort))
        _remotePortText = State(initialValue: String(forward.remotePort))
    }

    private var isValid: Bool {
        guard let local = Int(localPortText), (1...65535).contains(local),
              let remote = Int(remotePortText), (1...65535).contains(remote),
              !forward.remoteHost.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return !existingPorts.contains(local)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("name (optional)", text: $forward.name)
                    Toggle("Start on connect", isOn: $forward.autoStart)
                }

                Section {
                    TextField("local port", text: $localPortText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Local")
                } footer: {
                    Text("Reachable at 127.0.0.1:\(localPortText) on this device.")
                }

                Section("Remote (from the server)") {
                    TextField("remote host", text: $forward.remoteHost)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("remote port", text: $remotePortText)
                        .keyboardType(.numberPad)
                    Picker("Scheme", selection: $forward.scheme) {
                        Text("http").tag("http")
                        Text("https").tag("https")
                    }
                }
            }
            .navigationTitle(forward.name.isEmpty ? "New Forward" : "Edit Forward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        forward.remoteHost = forward.remoteHost.trimmingCharacters(in: .whitespaces)
        forward.localPort = Int(localPortText) ?? forward.localPort
        forward.remotePort = Int(remotePortText) ?? forward.remotePort
        store.save(forward)
        dismiss()
    }
}
