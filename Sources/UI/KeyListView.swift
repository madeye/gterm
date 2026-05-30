import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The "Keys" tab: import and manage SSH private keys. Keys are validated on
/// import and stored securely in the Keychain (device-only). Keys can be
/// imported from a file or pasted in as plain text.
struct KeyListView: View {
    @ObservedObject var store: KeyStore
    @ObservedObject var connections: ConnectionStore

    @State private var importing = false
    @State private var pastingText = false
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
                    Menu {
                        Button {
                            importing = true
                        } label: {
                            Label("Import from File", systemImage: "doc")
                        }
                        Button {
                            pastingText = true
                        } label: {
                            Label("Enter Text", systemImage: "doc.plaintext")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.data, .text, .item],
                allowsMultipleSelection: false
            ) { result in
                readFile(result)
            }
            .sheet(isPresented: $pastingText) {
                PasteKeyView { name, text in
                    pastingText = false
                    importText(name: name, text: text)
                }
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

    /// Import a key supplied as plain text (pasted or typed). Validates the key
    /// material and stores it directly; the name is taken from the paste sheet.
    private func importText(name: String, text: String) {
        do {
            try store.importKey(name: name, text: text)
        } catch let error as SSHKeyError {
            importError = error.description
        } catch {
            importError = error.localizedDescription
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

/// A sheet for importing an SSH private key from plain text. Provides a name
/// field, a multi-line editor for the key material, and a Paste button that
/// pulls the current clipboard contents into the editor.
private struct PasteKeyView: View {
    /// Called with (name, keyText) when the user taps Import.
    let onImport: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var keyText = ""

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Optional name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    TextEditor(text: $keyText)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 220)
                } header: {
                    HStack {
                        Text("Private Key")
                        Spacer()
                        Button {
                            if let clip = UIPasteboard.general.string {
                                keyText = clip
                            }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                        }
                        .textCase(nil)
                        .disabled(!UIPasteboard.general.hasStrings)
                    }
                } footer: {
                    Text("Paste an OpenSSH or PEM private key. It is validated on import and stored in the Keychain (device-only).")
                }
            }
            .navigationTitle("Enter Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(name.trimmingCharacters(in: .whitespaces), trimmedKey)
                    }
                    .disabled(trimmedKey.isEmpty)
                }
            }
        }
    }
}
