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
/// and a close button. The session itself is owned by `SessionManager`, so
/// leaving this screen detaches from — but does not disconnect — the session.
struct TerminalScreen: View {
    @ObservedObject var session: ActiveSession
    @ObservedObject var forwardStore: PortForwardStore
    let onClose: () -> Void

    @State private var showingAICommands = false
    @State private var showingForwards = false
    @State private var browsing: PortForward?
    /// A URL tapped in the terminal, opened in the in-app browser.
    @State private var linkURL: TappedURL?

    private var connection: SSHConnection { session.connection }

    /// Persisted forward configs for this connection (empty if not a saved host).
    private var connectionForwards: [PortForward] {
        guard let id = connection.savedID else { return [] }
        return forwardStore.forwards(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalView(surface: session.surface)
        }
        .onAppear {
            session.surface.onOpenURL = { url in linkURL = TappedURL(url: url) }
        }
        .sheet(isPresented: $showingAICommands) {
            AICommandSheet(
                runCommand: { session.surface.runCommand($0) },
                gatherContext: {
                    (session.surface.readVisibleText(), CommandHistory.shared.recent(limit: 15))
                }
            )
        }
        .sheet(isPresented: $showingForwards) {
            PortForwardStatusSheet(
                forwards: connectionForwards,
                statuses: session.forwardStates,
                onToggle: { f, on in
                    if on { session.ssh.startForward(f.id) } else { session.ssh.stopForward(f.id) }
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
        .onChange(of: state) { _, newState in
            // A clean remote close (e.g. `exit` in the shell) dismisses the
            // terminal; failures keep the screen up so the error stays readable.
            if newState == .closed { onClose() }
        }
        .alert(
            session.hostKeyRequest?.prompt.kind == .changed ? "Host Key Changed" : "Unknown Host",
            isPresented: Binding(
                get: { session.hostKeyRequest != nil },
                set: { if !$0 { session.hostKeyRequest?.decide(false); session.hostKeyRequest = nil } }
            ),
            presenting: session.hostKeyRequest
        ) { request in
            let isChanged = request.prompt.kind == .changed
            Button(isChanged ? "Accept New Key" : "Trust", role: isChanged ? .destructive : nil) {
                request.decide(true)
                session.hostKeyRequest = nil
            }
            Button("Cancel", role: .cancel) {
                request.decide(false)
                session.hostKeyRequest = nil
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
            Button { terminalView?.toggleKeyboard() } label: {
                Image(systemName: "keyboard").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Toggle keyboard")
            Button { showingAICommands = true } label: {
                Image(systemName: "sparkles").font(.body.weight(.semibold))
            }
            .accessibilityLabel("AI commands")
            Button { showingForwards = true } label: {
                Image(systemName: "network").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Port forwards")
            .disabled(session.state != .connected)
            statusIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var statusIndicator: some View {
        switch session.state {
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
        switch session.state {
        case .connecting: return "connecting…"
        case .authenticating: return "authenticating…"
        default: return ""
        }
    }
}
