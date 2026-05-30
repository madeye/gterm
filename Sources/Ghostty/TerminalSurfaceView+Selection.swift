import UIKit
import GhosttyKit

/// Touch-based text selection and clipboard for the terminal.
///
/// A long press drives ghostty's mouse-selection machinery:
/// - **Hold + drag** highlights text and, on release, copies it to the
///   clipboard ("select to copy").
/// - **Hold without moving** pastes the clipboard into the terminal as input
///   ("hold to paste").
///
/// Mouse positions are passed in view points (top-left origin); ghostty applies
/// the content scale internally — matching how the macOS apprt reports them.
extension TerminalSurfaceView {
    /// Distance (points) a hold must travel before it's treated as a selection
    /// drag rather than a paste.
    private static let selectionDragThreshold: CGFloat = 8

    func setupSelectionGestures() {
        let longPress = UILongPressGestureRecognizer(
            target: self, action: #selector(handleSelectionLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        addGestureRecognizer(longPress)
    }

    @objc private func handleSelectionLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let surface = ghosttySurface else { return }
        let location = gesture.location(in: self)
        let noMods = Ghostty.Mods.none.cMods

        switch gesture.state {
        case .began:
            selectionStart = location
            selectionMoved = false
            sendMousePos(location, surface: surface)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, noMods)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        case .changed:
            if let start = selectionStart,
               hypot(location.x - start.x, location.y - start.y) > Self.selectionDragThreshold {
                selectionMoved = true
            }
            sendMousePos(location, surface: surface)

        case .ended, .cancelled, .failed:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, noMods)
            if gesture.state == .ended {
                if selectionMoved {
                    copySelection(surface: surface)
                } else {
                    pasteClipboard()
                }
            }
            selectionStart = nil
            selectionMoved = false

        default:
            break
        }
    }

    private func sendMousePos(_ location: CGPoint, surface: ghostty_surface_t) {
        ghostty_surface_mouse_pos(surface, Double(location.x), Double(location.y), Ghostty.Mods.none.cMods)
    }

    /// Read the current ghostty selection and copy it to the clipboard.
    private func copySelection(surface: ghostty_surface_t) {
        guard ghostty_surface_has_selection(surface) else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let ptr = text.text, text.text_len > 0 else { return }
        let selected = String(decoding: UnsafeRawBufferPointer(start: ptr, count: Int(text.text_len)), as: UTF8.self)
        guard !selected.isEmpty else { return }
        UIPasteboard.general.string = selected
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Send the clipboard's text to the terminal as input.
    private func pasteClipboard() {
        guard let clip = UIPasteboard.general.string, !clip.isEmpty else { return }
        sendText(clip)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
