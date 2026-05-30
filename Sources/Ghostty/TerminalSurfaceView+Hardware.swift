import UIKit
import GhosttyKit

/// Hardware (physical) keyboard support: Bluetooth / Smart Keyboard / Magic
/// Keyboard. iOS delivers physical key presses as `UIPress`/`UIKey` events
/// through the responder chain (gated by `UIApplicationSupportsIndirectInputEvents`).
///
/// Routing mirrors the soft-keyboard path: special keys (arrows, esc, function
/// keys, …) and any Ctrl/Alt/Cmd combos are sent through `ghostty_surface_key`
/// (mode-aware), while plain printable input is left to `UIKeyInput.insertText`
/// so the layout-correct character is produced and we never double-send.
extension TerminalSurfaceView {
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = presses.filter { !handleHardwarePress($0, action: .press) }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
    }

    /// Returns true if we consumed the press (sent it as a key event), false to
    /// let UIKit's text path handle it.
    private func handleHardwarePress(_ press: UIPress, action: Ghostty.KeyAction) -> Bool {
        guard let uiKey = press.key else { return false }

        var mods = Ghostty.Mods.fromHardware(uiKey.modifierFlags)
        mods.formUnion(stickyMods)

        guard let key = Ghostty.Key(hid: uiKey.keyCode) else {
            // Unknown physical key but a modifier is armed from the accessory
            // bar — fall through to text so the modifier doesn't get stuck.
            if !stickyMods.isEmpty { clearStickyMods() }
            return false
        }

        // Shift alone is "just a capital/shifted character" — that belongs to
        // the text path. Anything beyond Shift (Ctrl/Alt/Cmd), or a special
        // key, must go through the key encoder.
        let beyondShift = !mods.subtracting(.shift).isEmpty
        if key.isSpecial || beyondShift {
            sendKey(key, mods: mods, action: action)
            clearStickyMods()
            return true
        }

        // Plain printable key. If a sticky modifier was armed (accessory bar),
        // honor it as a key event; otherwise defer to insertText.
        if !stickyMods.isEmpty {
            sendKey(key, mods: mods, action: action)
            clearStickyMods()
            return true
        }
        return false
    }
}

extension Ghostty.Mods {
    /// Translate UIKit hardware-keyboard modifier flags to ghostty modifiers.
    static func fromHardware(_ flags: UIKeyModifierFlags) -> Ghostty.Mods {
        var mods: Ghostty.Mods = .none
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.ctrl) }
        if flags.contains(.alternate) { mods.insert(.alt) }
        if flags.contains(.command) { mods.insert(.super) }
        return mods
    }
}

extension Ghostty.Key {
    /// Map an iOS HID usage code (from `UIKey.keyCode`) to a physical key.
    init?(hid: UIKeyboardHIDUsage) {
        switch hid {
        // Letters
        case .keyboardA: self = .a; case .keyboardB: self = .b; case .keyboardC: self = .c
        case .keyboardD: self = .d; case .keyboardE: self = .e; case .keyboardF: self = .f
        case .keyboardG: self = .g; case .keyboardH: self = .h; case .keyboardI: self = .i
        case .keyboardJ: self = .j; case .keyboardK: self = .k; case .keyboardL: self = .l
        case .keyboardM: self = .m; case .keyboardN: self = .n; case .keyboardO: self = .o
        case .keyboardP: self = .p; case .keyboardQ: self = .q; case .keyboardR: self = .r
        case .keyboardS: self = .s; case .keyboardT: self = .t; case .keyboardU: self = .u
        case .keyboardV: self = .v; case .keyboardW: self = .w; case .keyboardX: self = .x
        case .keyboardY: self = .y; case .keyboardZ: self = .z
        // Digits
        case .keyboard1: self = .d1; case .keyboard2: self = .d2; case .keyboard3: self = .d3
        case .keyboard4: self = .d4; case .keyboard5: self = .d5; case .keyboard6: self = .d6
        case .keyboard7: self = .d7; case .keyboard8: self = .d8; case .keyboard9: self = .d9
        case .keyboard0: self = .d0
        // Symbols
        case .keyboardHyphen: self = .minus; case .keyboardEqualSign: self = .equal
        case .keyboardOpenBracket: self = .bracketLeft; case .keyboardCloseBracket: self = .bracketRight
        case .keyboardBackslash: self = .backslash; case .keyboardSemicolon: self = .semicolon
        case .keyboardQuote: self = .quote; case .keyboardGraveAccentAndTilde: self = .backquote
        case .keyboardComma: self = .comma; case .keyboardPeriod: self = .period
        case .keyboardSlash: self = .slash
        // Functional
        case .keyboardEscape: self = .escape; case .keyboardTab: self = .tab
        case .keyboardReturnOrEnter, .keypadEnter: self = .enter
        case .keyboardDeleteOrBackspace: self = .backspace
        case .keyboardDeleteForward: self = .delete; case .keyboardSpacebar: self = .space
        // Navigation
        case .keyboardUpArrow: self = .up; case .keyboardDownArrow: self = .down
        case .keyboardLeftArrow: self = .left; case .keyboardRightArrow: self = .right
        case .keyboardHome: self = .home; case .keyboardEnd: self = .end
        case .keyboardPageUp: self = .pageUp; case .keyboardPageDown: self = .pageDown
        case .keyboardInsert: self = .insert
        // Function row
        case .keyboardF1: self = .f1; case .keyboardF2: self = .f2; case .keyboardF3: self = .f3
        case .keyboardF4: self = .f4; case .keyboardF5: self = .f5; case .keyboardF6: self = .f6
        case .keyboardF7: self = .f7; case .keyboardF8: self = .f8; case .keyboardF9: self = .f9
        case .keyboardF10: self = .f10; case .keyboardF11: self = .f11; case .keyboardF12: self = .f12
        default: return nil
        }
    }
}
