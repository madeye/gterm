import Foundation

/// High-level lifecycle of an SSH session, surfaced to the UI.
enum SSHSessionState: Equatable {
    case idle
    case connecting
    case authenticating
    case connected
    case failed(String)
    case closed
}

/// Delivers session state to the UI on the main queue.
///
/// `stop()` can race a `notify` that has already decided to hop: if the
/// callback ran without re-checking, a queued `.connected` would overwrite
/// `ActiveSession.state` after disconnect, and the subsequent
/// `handleChannelClose` would be dropped because the session is stopped.
/// The hop always re-reads `isStopped` on the main queue.
final class SessionStateNotifier {
    private let lock = NSLock()
    private var stopped = false
    private let onStateChange: (SSHSessionState) -> Void

    init(onStateChange: @escaping (SSHSessionState) -> Void) {
        self.onStateChange = onStateChange
    }

    func setStopped(_ value: Bool) {
        lock.lock()
        stopped = value
        lock.unlock()
    }

    func isStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func notify(_ state: SSHSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped() else { return }
            self.onStateChange(state)
        }
    }
}
