import SwiftUI
import UniformTypeIdentifiers

/// The "Keys" tab: import and manage SSH private keys. Keys are validated on
/// import and stored securely in the Keychain (device-only).
struct KeyListView: View {
    @ObservedObject var store: KeyStore
    @ObservedObject var connections: ConnectionStore

    @State private var importing = false
    @State private var pendingText: String?
    @State private var pendingName = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                if store.keys.isEmpty {
                    ContentUnavailableView(
                        "No Keys",
                        systemImage: "key",
                        description: Text("Import an SSH private key to use for connections.")
                    )
                }
                ForEach(store.keys) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name).font(.headline)
                        Text(key.type).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            connections.removeKeyReference(key.id)
                            store.delete(key)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Keys")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.data, .text, .item],
                allowsMultipleSelection: false
            ) { result in
                readFile(result)
            }
            .alert("Name this key", isPresented: Binding(
                get: { pendingText != nil },
                set: { if !$0 { pendingText = nil } }
            )) {
                TextField("name", text: $pendingName)
                Button("Save") { saveImported() }
                Button("Cancel", role: .cancel) { pendingText = nil }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                ),
                presenting: importError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private func readFile(_ result: Result<[URL], Error>) {
        guard let url = (try? result.get())?.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                importError = "Key file isn't valid text."
                return
            }
            // Validate before prompting for a name.
            _ = try SSHKeyParser.parse(text)
            pendingName = url.deletingPathExtension().lastPathComponent
            pendingText = text
        } catch let error as SSHKeyError {
            importError = error.description
        } catch {
            importError = "Couldn't read key file: \(error.localizedDescription)"
        }
    }

    private func saveImported() {
        guard let text = pendingText else { return }
        pendingText = nil
        do {
            try store.importKey(name: pendingName, text: text)
        } catch let error as SSHKeyError {
            importError = error.description
        } catch {
            importError = error.localizedDescription
        }
    }
}
