import SwiftUI

/// A pending host-key trust decision surfaced to the UI, pairing the prompt
/// details with the callback that resumes the SSH handshake.
struct HostKeyPromptRequest {
    let prompt: HostKeyPrompt
    let decide: (Bool) -> Void
}

/// A URL tapped in the terminal. Wraps `URL` so it can drive a `fullScreenCover(item:)`.
struct TappedURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Full-screen terminal for an active SSH connection, with a slim status bar
/// and a close button.
struct TerminalScreen: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    let connection: SSHConnection
    /// The owning `SavedConnection.id`, used to resolve persisted port forwards.
    let savedConnectionID: UUID?
    @ObservedObject var forwardStore: PortForwardStore
    let onClose: () -> Void

    @State private var state: SSHSessionState = .idle
    @State private var hostKeyRequest: HostKeyPromptRequest?
    @State private var terminalView: TerminalSurfaceView?
    @State private var showingAICommands = false
    @State private var showingForwards = false
    @State private var forwardStates: [UUID: PortForwardStatus] = [:]
    @State private var session: SSHSession?
    @State private var browsing: PortForward?
    /// A URL tapped in the terminal, opened in the in-app browser.
    @State private var linkURL: TappedURL?

    /// Persisted forward configs for this connection (empty if not a saved host).
    private var connectionForwards: [PortForward] {
        guard let id = savedConnectionID else { return [] }
        return forwardStore.forwards(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalView(ghostty: ghostty, makeSession: { view in
                SSHSession(
                    connection: connection,
                    view: view,
                    forwards: connectionForwards,
                    onHostKeyPrompt: { prompt, decide in
                        hostKeyRequest = HostKeyPromptRequest(prompt: prompt, decide: decide)
                    },
                    onForwardChange: { id, st in forwardStates[id] = st }
                ) { newState in
                    state = newState
                }
            }, onCreate: { view in
                view.onOpenURL = { url in linkURL = TappedURL(url: url) }
                DispatchQueue.main.async { terminalView = view }
            }, onSession: { s in
                DispatchQueue.main.async { session = s }
            })
        }
        .sheet(isPresented: $showingAICommands) {
            AICommandSheet(
                runCommand: { terminalView?.runCommand($0) },
                gatherContext: {
                    (terminalView?.readVisibleText() ?? "", CommandHistory.shared.recent(limit: 15))
                }
            )
        }
        .sheet(isPresented: $showingForwards) {
            PortForwardStatusSheet(
                forwards: connectionForwards,
                statuses: forwardStates,
                onToggle: { f, on in
                    if on { session?.startForward(f.id) } else { session?.stopForward(f.id) }
                },
                onOpenBrowser: { f in
                    showingForwards = false
                    browsing = f
                }
            )
        }
        .fullScreenCover(item: $browsing) { f in
            if let url = f.localURL {
                BrowserScreen(initialURL: url) { browsing = nil }
            }
        }
        .fullScreenCover(item: $linkURL) { tapped in
            BrowserScreen(initialURL: tapped.url) { linkURL = nil }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert(
            hostKeyRequest?.prompt.kind == .changed ? "Host Key Changed" : "Unknown Host",
            isPresented: Binding(
                get: { hostKeyRequest != nil },
                set: { if !$0 { hostKeyRequest?.decide(false); hostKeyRequest = nil } }
            ),
            presenting: hostKeyRequest
        ) { request in
            let isChanged = request.prompt.kind == .changed
            Button(isChanged ? "Accept New Key" : "Trust", role: isChanged ? .destructive : nil) {
                request.decide(true)
                hostKeyRequest = nil
            }
            Button("Cancel", role: .cancel) {
                request.decide(false)
                hostKeyRequest = nil
            }
        } message: { request in
            Text(hostKeyMessage(request.prompt))
        }
    }

    private func hostKeyMessage(_ prompt: HostKeyPrompt) -> String {
        switch prompt.kind {
        case .firstUse:
            return """
            The authenticity of host \(prompt.host) can't be established.

            Key fingerprint:
            \(prompt.fingerprint)

            Trust this host and continue connecting?
            """
        case .changed:
            return """
            ⚠️ The host key for \(prompt.host) has changed. This may indicate a \
            man-in-the-middle attack, or the server may simply have been reinstalled.

            Previously trusted:
            \(prompt.previousFingerprint ?? "<unknown>")

            New fingerprint:
            \(prompt.fingerprint)

            Only accept if you expected this change.
            """
        }
    }

    @ViewBuilder private var statusBar: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            Text("\(connection.username)@\(connection.host)")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Button { showingAICommands = true } label: {
                Image(systemName: "sparkles").font(.body.weight(.semibold))
            }
            .accessibilityLabel("AI commands")
            Button { showingForwards = true } label: {
                Image(systemName: "network").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Port forwards")
            .disabled(state != .connected)
            statusIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var statusIndicator: some View {
        switch state {
        case .idle, .connecting, .authenticating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(.white)
                Text(label).font(.caption)
            }
        case .connected:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        case .closed:
            Text("disconnected").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch state {
        case .connecting: return "connecting…"
        case .authenticating: return "authenticating…"
        default: return ""
        }
    }
}
