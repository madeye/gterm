import SwiftUI

/// Full-screen terminal for an active SSH connection, with a slim status bar
/// and a close button.
struct TerminalScreen: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    let connection: SSHConnection
    let onClose: () -> Void

    @State private var state: SSHSessionState = .idle

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TerminalView(ghostty: ghostty) { view in
                SSHSession(connection: connection, view: view) { newState in
                    state = newState
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)

            statusBar
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
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
