import UIKit
import GhosttyKit

extension TerminalSurfaceView {
    func setupPointerGestures() {
        let pointerTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        let drag = UIPanGestureRecognizer(target: self, action: #selector(pointerDrag(_:)))
        drag.allowedTouchTypes = pointerTypes
        drag.allowedScrollTypesMask = []
        addGestureRecognizer(drag)

        let click = UITapGestureRecognizer(target: self, action: #selector(pointerClick(_:)))
        click.allowedTouchTypes = pointerTypes
        click.require(toFail: drag)
        addGestureRecognizer(click)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(pointerHover(_:))))
    }

    @objc private func pointerHover(_ gesture: UIHoverGestureRecognizer) {
        guard let surface = ghosttySurface else { return }
        let point = gesture.location(in: self)
        let mods = Ghostty.Mods.fromHardware(gesture.modifierFlags).cMods
        ghostty_surface_mouse_pos(surface, Double(point.x), Double(point.y), mods)
    }

    @objc private func pointerClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let surface = ghosttySurface else { return }
        _ = becomeFirstResponder()
        let point = gesture.location(in: self)
        let mods = Ghostty.Mods.fromHardware(gesture.modifierFlags).cMods
        ghostty_surface_mouse_pos(surface, Double(point.x), Double(point.y), mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    @objc private func pointerDrag(_ gesture: UIPanGestureRecognizer) {
        guard let surface = ghosttySurface else { return }
        let point = gesture.location(in: self)
        let mods = Ghostty.Mods.fromHardware(gesture.modifierFlags).cMods
        if gesture.state == .began {
            _ = becomeFirstResponder()
            // Recognition starts after the pointer has moved. Anchor the
            // selection at the original press rather than the threshold point.
            let translation = gesture.translation(in: self)
            ghostty_surface_mouse_pos(surface, Double(point.x - translation.x), Double(point.y - translation.y), mods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
        }
        ghostty_surface_mouse_pos(surface, Double(point.x), Double(point.y), mods)
        if [.ended, .cancelled, .failed].contains(gesture.state) {
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        }
    }
}
