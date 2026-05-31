import UIKit
import GhosttyKit

/// Touch scrolling: a one-finger drag emulates the desktop mouse wheel, driving
/// ghostty's `mouse_scroll`. This scrolls the local scrollback, and — exactly
/// like a desktop mouse — is forwarded to programs that grab the mouse (tmux /
/// vim with mouse mode, `less`, …).
///
/// It uses precision (pixel) scrolling so the content tracks the finger, with
/// natural direction: dragging down reveals older lines. While a long-press
/// selection is active the recognizer is disabled (see TerminalSurfaceView+
/// Selection), so a stationary hold selects and an immediate drag scrolls.
extension TerminalSurfaceView {
    func setupScrollGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        scrollPan = pan
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        guard let surface = ghosttySurface else { return }
        switch gesture.state {
        case .began:
            lastScrollTranslationY = gesture.translation(in: self).y
        case .changed:
            let translationY = gesture.translation(in: self).y
            let delta = translationY - lastScrollTranslationY
            lastScrollTranslationY = translationY
            guard delta != 0 else { return }

            // Convert points to surface pixels and feed as a precision scroll so
            // the content follows the finger. Positive y scrolls toward older
            // lines, which is what dragging the content downward should do.
            let scale = window?.screen.scale ?? UIScreen.main.scale
            let yOffset = Double(delta * scale)
            ghostty_surface_mouse_scroll(surface, 0, yOffset, Self.precisionScrollMods)
        default:
            break
        }
    }

    /// `ghostty_input_scroll_mods_t` with only the precision bit set (bit 0).
    private static var precisionScrollMods: ghostty_input_scroll_mods_t { 1 }
}
