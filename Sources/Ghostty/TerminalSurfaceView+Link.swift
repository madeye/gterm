import UIKit
import GhosttyKit

/// Tap handling. By default this is tap-to-open-URL: libghostty detects links
/// (auto-detected URLs and OSC 8 hyperlinks) and opens the one under the cursor
/// on a left-click release, but only treats a cell as "over a link" when the
/// mouse modifiers match `ctrlOrSuper` — which is `super` (⌘) on Apple
/// platforms. iOS has no hover, so a single tap synthesizes a super-modified
/// move + click at the tapped point; if a link is there, libghostty fires the
/// OPEN_URL action (handled in `Ghostty.App.action`), which we route to the
/// in-app browser. A tap on a non-link is a harmless super-click.
///
/// When `attachHerdr` is on, the same tap is instead an unmodified left
/// press+release so Herdr's mouse-native TUI can receive the click.
extension TerminalSurfaceView {
    func setupLinkTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleLinkTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        addGestureRecognizer(tap)
    }

    @objc private func handleLinkTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let surface = ghosttySurface else { return }
        // A tap is also the affordance for re-summoning a dismissed keyboard.
        showKeyboardIfNeeded()
        let loc = gesture.location(in: self)
        switch HerdrSupport.tapDecision(attachHerdr: attachHerdr, x: Double(loc.x), y: Double(loc.y)) {
        case .mouseLeftClick(let x, let y):
            // Unmodified left press+release at the tap so Herdr (and other
            // mouse-mode programs) receive a real click.
            let mods = Ghostty.Mods.none.cMods
            ghostty_surface_mouse_pos(surface, x, y, mods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        case .existingGestures:
            let superMods = GHOSTTY_MODS_SUPER
            // Move with super so the cell registers as over_link, then click it.
            ghostty_surface_mouse_pos(surface, Double(loc.x), Double(loc.y), superMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, superMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, superMods)
            // Clear the hover modifiers so the link highlight doesn't stick.
            ghostty_surface_mouse_pos(surface, Double(loc.x), Double(loc.y), Ghostty.Mods.none.cMods)
        }
    }
}
