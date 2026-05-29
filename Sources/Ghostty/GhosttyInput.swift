import Foundation
import GhosttyKit

/// Lightweight, iOS-only port of ghostty's input model. Just enough to send
/// keyboard input to a surface: modifiers, a practical set of physical keys,
/// and a builder for `ghostty_input_key_s`.
///
/// IMPORTANT: ghostty derives the *physical key* from the `keycode` field
/// (using its macOS-virtual-keycode table) and uses that, together with the
/// terminal's current modes (application cursor keys, keypad, Kitty protocol,
/// etc.), to produce the correct bytes. So special/control keys MUST be sent
/// as key events with the right keycode — not as raw text. Plain printable
/// characters can be sent via `ghostty_surface_text` instead.
enum Ghostty {}

extension Ghostty {
    struct Mods: OptionSet {
        let rawValue: UInt32

        static let none = Mods([])
        static let shift = Mods(rawValue: GHOSTTY_MODS_SHIFT.rawValue)
        static let ctrl = Mods(rawValue: GHOSTTY_MODS_CTRL.rawValue)
        static let alt = Mods(rawValue: GHOSTTY_MODS_ALT.rawValue)
        static let `super` = Mods(rawValue: GHOSTTY_MODS_SUPER.rawValue)

        init(rawValue: UInt32) { self.rawValue = rawValue }
        init(_ opts: [Mods]) { self.rawValue = opts.reduce(0) { $0 | $1.rawValue } }

        var cMods: ghostty_input_mods_e { ghostty_input_mods_e(rawValue) }
    }

    enum KeyAction {
        case press, release, `repeat`
        var cAction: ghostty_input_action_e {
            switch self {
            case .press: return GHOSTTY_ACTION_PRESS
            case .release: return GHOSTTY_ACTION_RELEASE
            case .repeat: return GHOSTTY_ACTION_REPEAT
            }
        }
    }

    /// A physical key. The raw value is the macOS virtual keycode that ghostty
    /// expects (from src/input/keycodes.zig); `cKey` is the ghostty enum used
    /// for documentation/lookups. Only the keys we actually need on mobile are
    /// included.
    enum Key {
        // Letters
        case a, b, c, d, e, f, g, h, i, j, k, l, m
        case n, o, p, q, r, s, t, u, v, w, x, y, z
        // Digits
        case d0, d1, d2, d3, d4, d5, d6, d7, d8, d9
        // Symbols
        case minus, equal, bracketLeft, bracketRight, backslash
        case semicolon, quote, backquote, comma, period, slash
        // Functional
        case escape, tab, enter, backspace, delete, space
        // Navigation
        case up, down, left, right, home, end, pageUp, pageDown, insert
        // Function row
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

        /// macOS virtual keycode (what ghostty's keycode table maps from).
        var macKeyCode: UInt16 {
            switch self {
            case .a: return 0x00; case .b: return 0x0b; case .c: return 0x08
            case .d: return 0x02; case .e: return 0x0e; case .f: return 0x03
            case .g: return 0x05; case .h: return 0x04; case .i: return 0x22
            case .j: return 0x26; case .k: return 0x28; case .l: return 0x25
            case .m: return 0x2e; case .n: return 0x2d; case .o: return 0x1f
            case .p: return 0x23; case .q: return 0x0c; case .r: return 0x0f
            case .s: return 0x01; case .t: return 0x11; case .u: return 0x20
            case .v: return 0x09; case .w: return 0x0d; case .x: return 0x07
            case .y: return 0x10; case .z: return 0x06
            case .d0: return 0x1d; case .d1: return 0x12; case .d2: return 0x13
            case .d3: return 0x14; case .d4: return 0x15; case .d5: return 0x17
            case .d6: return 0x16; case .d7: return 0x1a; case .d8: return 0x1c
            case .d9: return 0x19
            case .minus: return 0x1b; case .equal: return 0x18
            case .bracketLeft: return 0x21; case .bracketRight: return 0x1e
            case .backslash: return 0x2a; case .semicolon: return 0x29
            case .quote: return 0x27; case .backquote: return 0x32
            case .comma: return 0x2b; case .period: return 0x2f; case .slash: return 0x2c
            case .escape: return 0x35; case .tab: return 0x30; case .enter: return 0x24
            case .backspace: return 0x33; case .delete: return 0x75; case .space: return 0x31
            case .up: return 0x7e; case .down: return 0x7d; case .left: return 0x7b
            case .right: return 0x7c; case .home: return 0x73; case .end: return 0x77
            case .pageUp: return 0x74; case .pageDown: return 0x79; case .insert: return 0x72
            case .f1: return 0x7a; case .f2: return 0x78; case .f3: return 0x63
            case .f4: return 0x76; case .f5: return 0x60; case .f6: return 0x61
            case .f7: return 0x62; case .f8: return 0x64; case .f9: return 0x65
            case .f10: return 0x6d; case .f11: return 0x67; case .f12: return 0x6f
            }
        }

        var cKey: ghostty_input_key_e {
            switch self {
            case .a: return GHOSTTY_KEY_A; case .b: return GHOSTTY_KEY_B
            case .c: return GHOSTTY_KEY_C; case .d: return GHOSTTY_KEY_D
            case .e: return GHOSTTY_KEY_E; case .f: return GHOSTTY_KEY_F
            case .g: return GHOSTTY_KEY_G; case .h: return GHOSTTY_KEY_H
            case .i: return GHOSTTY_KEY_I; case .j: return GHOSTTY_KEY_J
            case .k: return GHOSTTY_KEY_K; case .l: return GHOSTTY_KEY_L
            case .m: return GHOSTTY_KEY_M; case .n: return GHOSTTY_KEY_N
            case .o: return GHOSTTY_KEY_O; case .p: return GHOSTTY_KEY_P
            case .q: return GHOSTTY_KEY_Q; case .r: return GHOSTTY_KEY_R
            case .s: return GHOSTTY_KEY_S; case .t: return GHOSTTY_KEY_T
            case .u: return GHOSTTY_KEY_U; case .v: return GHOSTTY_KEY_V
            case .w: return GHOSTTY_KEY_W; case .x: return GHOSTTY_KEY_X
            case .y: return GHOSTTY_KEY_Y; case .z: return GHOSTTY_KEY_Z
            case .d0: return GHOSTTY_KEY_DIGIT_0; case .d1: return GHOSTTY_KEY_DIGIT_1
            case .d2: return GHOSTTY_KEY_DIGIT_2; case .d3: return GHOSTTY_KEY_DIGIT_3
            case .d4: return GHOSTTY_KEY_DIGIT_4; case .d5: return GHOSTTY_KEY_DIGIT_5
            case .d6: return GHOSTTY_KEY_DIGIT_6; case .d7: return GHOSTTY_KEY_DIGIT_7
            case .d8: return GHOSTTY_KEY_DIGIT_8; case .d9: return GHOSTTY_KEY_DIGIT_9
            case .minus: return GHOSTTY_KEY_MINUS; case .equal: return GHOSTTY_KEY_EQUAL
            case .bracketLeft: return GHOSTTY_KEY_BRACKET_LEFT
            case .bracketRight: return GHOSTTY_KEY_BRACKET_RIGHT
            case .backslash: return GHOSTTY_KEY_BACKSLASH
            case .semicolon: return GHOSTTY_KEY_SEMICOLON; case .quote: return GHOSTTY_KEY_QUOTE
            case .backquote: return GHOSTTY_KEY_BACKQUOTE; case .comma: return GHOSTTY_KEY_COMMA
            case .period: return GHOSTTY_KEY_PERIOD; case .slash: return GHOSTTY_KEY_SLASH
            case .escape: return GHOSTTY_KEY_ESCAPE; case .tab: return GHOSTTY_KEY_TAB
            case .enter: return GHOSTTY_KEY_ENTER; case .backspace: return GHOSTTY_KEY_BACKSPACE
            case .delete: return GHOSTTY_KEY_DELETE; case .space: return GHOSTTY_KEY_SPACE
            case .up: return GHOSTTY_KEY_ARROW_UP; case .down: return GHOSTTY_KEY_ARROW_DOWN
            case .left: return GHOSTTY_KEY_ARROW_LEFT; case .right: return GHOSTTY_KEY_ARROW_RIGHT
            case .home: return GHOSTTY_KEY_HOME; case .end: return GHOSTTY_KEY_END
            case .pageUp: return GHOSTTY_KEY_PAGE_UP; case .pageDown: return GHOSTTY_KEY_PAGE_DOWN
            case .insert: return GHOSTTY_KEY_INSERT
            case .f1: return GHOSTTY_KEY_F1; case .f2: return GHOSTTY_KEY_F2
            case .f3: return GHOSTTY_KEY_F3; case .f4: return GHOSTTY_KEY_F4
            case .f5: return GHOSTTY_KEY_F5; case .f6: return GHOSTTY_KEY_F6
            case .f7: return GHOSTTY_KEY_F7; case .f8: return GHOSTTY_KEY_F8
            case .f9: return GHOSTTY_KEY_F9; case .f10: return GHOSTTY_KEY_F10
            case .f11: return GHOSTTY_KEY_F11; case .f12: return GHOSTTY_KEY_F12
            }
        }
    }

    /// A key event that can be sent to a surface via `ghostty_surface_key`.
    struct KeyEvent {
        var key: Key
        var action: KeyAction = .press
        var mods: Mods = .none
        var text: String? = nil

        /// Build the C struct and run `body` with it. The text pointer is only
        /// valid for the duration of `body`.
        func withCValue<T>(_ body: (ghostty_input_key_s) -> T) -> T {
            var ev = ghostty_input_key_s()
            ev.action = action.cAction
            ev.keycode = UInt32(key.macKeyCode)
            ev.mods = mods.cMods
            ev.consumed_mods = Ghostty.Mods.none.cMods
            ev.unshifted_codepoint = text?.unicodeScalars.first.map { $0.value } ?? 0
            ev.composing = false
            if let text {
                return text.withCString { ptr in
                    ev.text = ptr
                    return body(ev)
                }
            } else {
                ev.text = nil
                return body(ev)
            }
        }
    }
}
