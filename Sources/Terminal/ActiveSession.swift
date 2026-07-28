import SwiftUI

/// A live terminal session — the `SSHSession` transport plus the ghostty
/// `TerminalSurfaceView` it renders into — owned independently of any screen.
/// Because both halves are retained here, dismissing the terminal UI leaves
/// the SSH connection running and the scrollback intact; reopening the host
/// reattaches the same surface.
final class ActiveSession: ObservableObject, Identifiable {
    /// Keyed by the saved host so a host has at most one live session.
    let id: UUID
    let connection: SSHConnection
    let surface: TerminalSurfaceView
    private(set) var ssh: SSHSession!

    @Published private(set) var state: SSHSessionState = .idle
    @Published var forwardStates: [UUID: PortForwardStatus] = [:]
    /// A pending host-key trust decision, surfaced by whichever screen is
    /// currently showing this session.
    @Published var hostKeyRequest: HostKeyPromptRequest?

    init(connection: SSHConnection, ghostty: Ghostty.App, forwards: [PortForward]) {
        self.id = connection.savedID ?? connection.id
        self.connection = connection
        let surface = TerminalSurfaceView(ghostty: ghostty)
        self.surface = surface
        let session = SSHSession(
            connection: connection,
            view: surface,
            forwards: forwards,
            onHostKeyPrompt: { [weak self] prompt, decide in
                DispatchQueue.main.async {
                    self?.hostKeyRequest = HostKeyPromptRequest(prompt: prompt, decide: decide)
                }
            },
            onForwardChange: { [weak self] id, status in
                DispatchQueue.main.async { self?.forwardStates[id] = status }
            }
        ) { [weak self] newState in
            self?.state = newState
        }
        self.ssh = session
        surface.delegate = session
    }

    /// Whether the transport is (or may still become) usable. Failed and
    /// closed sessions are dead: they are pruned rather than kept around.
    var isAlive: Bool {
        switch state {
        case .failed, .closed: return false
        case .idle, .connecting, .authenticating, .connected: return true
        }
    }

    func start() {
        ssh.start()
    }

    /// Tear down the transport. `SSHSession.stop()` closes channels without a
    /// state callback, so mark the session closed here.
    func stop() {
        ssh.stop()
        state = .closed
    }
}

/// Owns every `ActiveSession`, keeping connections alive while the user is
/// back in the main UI. The Hosts list uses it to show live status, reattach,
/// and disconnect.
final class SessionManager: ObservableObject {
    @Published private(set) var sessions: [ActiveSession] = []

    func session(for id: UUID) -> ActiveSession? {
        sessions.first { $0.id == id }
    }

    /// Reattach to the live session for this connection, or start a new one.
    /// A dead leftover (failed / closed while backgrounded) is replaced.
    func open(
        _ connection: SSHConnection,
        ghostty: Ghostty.App,
        forwards: [PortForward]
    ) -> ActiveSession {
        let key = connection.savedID ?? connection.id
        if let existing = session(for: key) {
            if existing.isAlive { return existing }
            remove(existing)
        }
        let session = ActiveSession(connection: connection, ghostty: ghostty, forwards: forwards)
        sessions.append(session)
        session.start()
        return session
    }

    func disconnect(_ session: ActiveSession) {
        session.stop()
        remove(session)
    }

    /// Called when the terminal screen is dismissed: live sessions keep
    /// running in the background, dead ones are dropped so the next tap on
    /// the host reconnects fresh.
    func pruneIfDead(_ session: ActiveSession) {
        if !session.isAlive { remove(session) }
    }

    private func remove(_ session: ActiveSession) {
        sessions.removeAll { $0.id == session.id }
    }
}
