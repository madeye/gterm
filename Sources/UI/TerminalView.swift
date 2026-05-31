import SwiftUI

/// SwiftUI wrapper that hosts a `TerminalSurfaceView` and binds it to a terminal
/// session produced by `makeSession` (loopback, SSH, ...). The session is the
/// surface's delegate and is retained for the view's lifetime.
struct TerminalView: UIViewRepresentable {
    let ghostty: Ghostty.App
    let makeSession: (TerminalSurfaceView) -> TerminalSession
    /// Called once with the created surface view so the hosting screen can drive
    /// it (e.g. the AI command assistant typing a command into the terminal).
    var onCreate: ((TerminalSurfaceView) -> Void)? = nil
    /// Called in `makeUIView` with the freshly made session, when it is an
    /// `SSHSession`, so the hosting screen can drive port forwards.
    var onSession: ((SSHSession) -> Void)? = nil

    func makeUIView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(ghostty: ghostty)
        let session = makeSession(view)
        view.delegate = session
        context.coordinator.session = session
        session.start()
        if let ssh = session as? SSHSession { onSession?(ssh) }
        onCreate?(view)
        return view
    }

    func updateUIView(_ uiView: TerminalSurfaceView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalSurfaceView, coordinator: Coordinator) {
        coordinator.session?.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var session: TerminalSession?
    }
}
