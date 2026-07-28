import SwiftUI

/// SwiftUI wrapper that hosts a `TerminalSurfaceView` owned by an
/// `ActiveSession`. The session and surface outlive this view: dismissing the
/// screen detaches the surface but leaves the SSH connection running, and
/// presenting it again reattaches the same surface with its scrollback.
struct TerminalView: UIViewRepresentable {
    let surface: TerminalSurfaceView

    func makeUIView(context: Context) -> TerminalSurfaceView {
        surface
    }

    func updateUIView(_ uiView: TerminalSurfaceView, context: Context) {}
}
