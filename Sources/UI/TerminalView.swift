import SwiftUI

/// SwiftUI wrapper that hosts a `TerminalSurfaceView` and binds it to a terminal
/// session produced by `makeSession` (loopback, SSH, ...). The session is the
/// surface's delegate and is retained for the view's lifetime.
struct TerminalView: UIViewRepresentable {
    let ghostty: Ghostty.App
    let makeSession: (TerminalSurfaceView) -> TerminalSession

    func makeUIView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(ghostty: ghostty)
        let session = makeSession(view)
        view.delegate = session
        context.coordinator.session = session
        session.start()
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
