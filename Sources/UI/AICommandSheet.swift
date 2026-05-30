import SwiftUI

/// Sheet for running terminal commands without typing them all out: one-tap
/// quick actions for common tmux/shell ops, and an "Ask AI" field that turns a
/// natural-language request into a command via the configured LLM provider. AI
/// results are always shown in an editable preview before they run.
struct AICommandSheet: View {
    /// Type a command into the terminal and run it.
    let runCommand: (String) -> Void
    /// Gather the current terminal context (visible text + recent history).
    let gatherContext: () -> (text: String, history: [String])

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var providers = ProviderStore.shared
    private let engine = CommandAssistantEngine()

    @State private var instruction = ""
    @State private var generating = false
    @State private var proposed: String?
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                quickActionsSection
                askSection
                if proposed != nil { previewSection }
            }
            .navigationTitle("AI Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Quick actions

    private var quickActionsSection: some View {
        Section("Quick Actions") {
            quickRow(QuickCommands.tmux)
            quickRow(QuickCommands.shell)
        }
    }

    private func quickRow(_ commands: [QuickCommand]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commands) { command in
                    Button { run(command.command) } label: {
                        Label(command.title, systemImage: command.systemImage)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            .foregroundStyle(command.isDestructive ? Color.red : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8))
    }

    // MARK: Ask AI

    private var askSection: some View {
        Section {
            HStack(alignment: .center, spacing: 8) {
                TextField("Ask AI to run a command…", text: $instruction, axis: .vertical)
                    .focused($fieldFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(generate)
                Button(action: generate) {
                    if generating {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .disabled(!canGenerate)
            }
            if !providers.hasUsableProvider {
                Label("Add an AI provider in the AI tab to use this.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle").font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Ask AI")
        } footer: {
            Text("The AI sees your recent commands and the visible screen. Review the command before it runs.")
        }
    }

    private var canGenerate: Bool {
        !instruction.trimmingCharacters(in: .whitespaces).isEmpty
            && !generating
            && providers.hasUsableProvider
    }

    // MARK: Preview

    private var previewSection: some View {
        Section("Proposed Command") {
            TextEditor(text: Binding(get: { proposed ?? "" }, set: { proposed = $0 }))
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 60)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button(role: .destructive) { proposed = nil } label: { Text("Discard") }
                Spacer()
                Button { if let command = proposed { run(command) } } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func generate() {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !generating, providers.hasUsableProvider else { return }
        fieldFocused = false
        errorMessage = nil
        proposed = nil
        generating = true
        let context = gatherContext()
        Task {
            let result = await engine.generateCommand(
                instruction: text, terminalText: context.text, history: context.history
            )
            generating = false
            switch result {
            case .success(let command): proposed = command
            case .failure(let error): errorMessage = error.errorDescription
            }
        }
    }

    private func run(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runCommand(trimmed)
        dismiss()
    }
}
