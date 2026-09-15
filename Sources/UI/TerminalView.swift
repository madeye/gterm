import SwiftUI

/// Hosts a session-owned surface without tying the SSH connection to a screen.
struct TerminalView: UIViewRepresentable {
    let surface: TerminalSurfaceView
    let onOpenURL: (URL) -> Void
    let onKeyboardShortcut: (String) -> Void

    final class Coordinator {
        var onOpenURL: ((URL) -> Void)?
        var onKeyboardShortcut: ((String) -> Void)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TerminalSurfaceView {
        updateHandlers(context.coordinator)
        return surface
    }

    func updateUIView(_ uiView: TerminalSurfaceView, context: Context) {
        updateHandlers(context.coordinator)
    }

    private func updateHandlers(_ coordinator: Coordinator) {
        coordinator.onOpenURL = onOpenURL
        coordinator.onKeyboardShortcut = onKeyboardShortcut
        // SwiftUI can call onDisappear during split-view navigation while the
        // surface is still visible. Bind to the representable's lifetime instead.
        // Weak captures also prevent a retained session surface from retaining
        // its old screen and the session manager after detaching.
        surface.onOpenURL = { [weak coordinator] in coordinator?.onOpenURL?($0) }
        surface.onKeyboardShortcut = { [weak coordinator] input in
            coordinator?.onKeyboardShortcut?(input)
        }
    }
}
