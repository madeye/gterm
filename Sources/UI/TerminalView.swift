import SwiftUI

/// SwiftUI wrapper that hosts a `TerminalSurfaceView` and binds it to a
/// terminal session. For now the session is a local echo; the SSH session is
/// substituted in a later phase.
struct TerminalView: UIViewRepresentable {
    let ghostty: Ghostty.App

    func makeUIView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(ghostty: ghostty)
        let session = LoopbackSession(view: view)
        view.delegate = session
        context.coordinator.session = session
        session.start()
        return view
    }

    func updateUIView(_ uiView: TerminalSurfaceView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// Retains the session for the lifetime of the view.
        var session: TerminalSession?
    }
}
