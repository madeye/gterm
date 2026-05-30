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

        /// Map a printable character to a physical key, so modifier combos
        /// (e.g. Ctrl-C) can be encoded correctly when the user types on the
        /// system keyboard with a sticky modifier armed.
        init?(character: Character) {
            switch character.lowercased().first {
            case "a": self = .a; case "b": self = .b; case "c": self = .c
            case "d": self = .d; case "e": self = .e; case "f": self = .f
            case "g": self = .g; case "h": self = .h; case "i": self = .i
            case "j": self = .j; case "k": self = .k; case "l": self = .l
            case "m": self = .m; case "n": self = .n; case "o": self = .o
            case "p": self = .p; case "q": self = .q; case "r": self = .r
            case "s": self = .s; case "t": self = .t; case "u": self = .u
            case "v": self = .v; case "w": self = .w; case "x": self = .x
            case "y": self = .y; case "z": self = .z
            case "0": self = .d0; case "1": self = .d1; case "2": self = .d2
            case "3": self = .d3; case "4": self = .d4; case "5": self = .d5
            case "6": self = .d6; case "7": self = .d7; case "8": self = .d8
            case "9": self = .d9
            case "-": self = .minus; case "=": self = .equal
            case "[": self = .bracketLeft; case "]": self = .bracketRight
            case "\\": self = .backslash; case ";": self = .semicolon
            case "'": self = .quote; case "`": self = .backquote
            case ",": self = .comma; case ".": self = .period
            case "/": self = .slash; case " ": self = .space
            default: return nil
            }
        }

        /// Map a printable character to its physical key *plus* whether Shift is
        /// needed to produce it on a US layout. This lets modifier combos with
        /// shifted symbols (Ctrl-_, Alt-|, Ctrl-^) be encoded as real key
        /// events, where `init?(character:)` alone would drop the Shift.
        static func physical(for character: Character) -> (key: Key, shift: Bool)? {
            if let base = Key(character: character) { return (base, false) }
            switch character {
            case "|": return (.backslash, true);    case "~": return (.backquote, true)
            case ":": return (.semicolon, true);    case "_": return (.minus, true)
            case "!": return (.d1, true);           case "@": return (.d2, true)
            case "#": return (.d3, true);           case "$": return (.d4, true)
            case "%": return (.d5, true);           case "^": return (.d6, true)
            case "&": return (.d7, true);           case "*": return (.d8, true)
            case "(": return (.d9, true);           case ")": return (.d0, true)
            case "{": return (.bracketLeft, true);  case "}": return (.bracketRight, true)
            case "+": return (.equal, true);        case "\"": return (.quote, true)
            case "<": return (.comma, true);        case ">": return (.period, true)
            case "?": return (.slash, true)
            default: return nil
            }
        }

        /// True for keys that must be sent as key events (not text) because the
        /// terminal encodes them mode-dependently (arrows, function keys, etc.).
        var isSpecial: Bool {
            switch self {
            case .escape, .tab, .enter, .backspace, .delete,
                 .up, .down, .left, .right, .home, .end, .pageUp, .pageDown, .insert,
                 .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
                return true
            default:
                return false
            }
        }

        /// The character this key produces with no modifiers (US layout), for
        /// keys that map to a single printable character; nil for named/special
        /// keys (escape, tab, arrows, function keys, …).
        ///
        /// ghostty's KeyEncoder derives control/alt sequences (e.g. the tmux
        /// prefix Ctrl-B -> 0x02) from the event's text / unshifted codepoint —
        /// just like the macOS apprt. Supplying this for printable keys is what
        /// makes Ctrl-/Alt-<letter> combos encode correctly.
        var unshiftedScalar: Unicode.Scalar? {
            switch self {
            case .a: return "a"; case .b: return "b"; case .c: return "c"
            case .d: return "d"; case .e: return "e"; case .f: return "f"
            case .g: return "g"; case .h: return "h"; case .i: return "i"
            case .j: return "j"; case .k: return "k"; case .l: return "l"
            case .m: return "m"; case .n: return "n"; case .o: return "o"
            case .p: return "p"; case .q: return "q"; case .r: return "r"
            case .s: return "s"; case .t: return "t"; case .u: return "u"
            case .v: return "v"; case .w: return "w"; case .x: return "x"
            case .y: return "y"; case .z: return "z"
            case .d0: return "0"; case .d1: return "1"; case .d2: return "2"
            case .d3: return "3"; case .d4: return "4"; case .d5: return "5"
            case .d6: return "6"; case .d7: return "7"; case .d8: return "8"
            case .d9: return "9"
            case .minus: return "-"; case .equal: return "="
            case .bracketLeft: return "["; case .bracketRight: return "]"
            case .backslash: return "\\"; case .semicolon: return ";"
            case .quote: return "'"; case .backquote: return "`"
            case .comma: return ","; case .period: return "."
            case .slash: return "/"; case .space: return " "
            case .escape, .tab, .enter, .backspace, .delete,
                 .up, .down, .left, .right, .home, .end, .pageUp, .pageDown, .insert,
                 .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
                return nil
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
            ev.composing = false

            // Supply the key's unmodified character as both `text` and
            // `unshifted_codepoint` (matching the macOS apprt) so ghostty's
            // KeyEncoder can encode Ctrl-/Alt-<key> combos such as the tmux
            // prefix Ctrl-B. Named keys (arrows, enter, …) have no scalar, so
            // they keep text == nil and encode as key events.
            let scalar = text?.unicodeScalars.first ?? key.unshiftedScalar
            ev.unshifted_codepoint = scalar?.value ?? 0
            let effectiveText = text ?? key.unshiftedScalar.map { String($0) }
            if let effectiveText {
                return effectiveText.withCString { ptr in
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
