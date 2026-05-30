import SwiftUI

/// A pending host-key trust decision surfaced to the UI, pairing the prompt
/// details with the callback that resumes the SSH handshake.
struct HostKeyPromptRequest {
    let prompt: HostKeyPrompt
    let decide: (Bool) -> Void
}

/// Full-screen terminal for an active SSH connection, with a slim status bar
/// and a close button.
struct TerminalScreen: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    let connection: SSHConnection
    let onClose: () -> Void

    @State private var state: SSHSessionState = .idle
    @State private var hostKeyRequest: HostKeyPromptRequest?

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalView(ghostty: ghostty) { view in
                SSHSession(
                    connection: connection,
                    view: view,
                    onHostKeyPrompt: { prompt, decide in
                        hostKeyRequest = HostKeyPromptRequest(prompt: prompt, decide: decide)
                    }
                ) { newState in
                    state = newState
                }
            }
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
