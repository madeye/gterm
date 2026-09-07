import Foundation

/// Maps the per-connection Herdr option onto SSH PTY start and terminal tap
/// delivery. Foundation-only so `gtermTests` can drive the same functions the
/// session and surface use, without UIKit or a live host.
enum HerdrSupport {
    /// SSH exec uses a non-login shell, which often lacks ~/.local/bin or
    /// ~/.cargo/bin. Load the user's login and interactive shell environment
    /// just as a manual SSH login would, then replace the shell with Herdr.
    static let command = "exec \"$SHELL\" -ilc 'exec herdr'"

    /// How the SSH session channel should be started.
    enum PTYStart: Equatable {
        /// Today's path: request a login shell.
        case loginShell
        /// Exec `herdr` on the remote (with the already-requested PTY).
        case exec(String)
    }

    static func ptyStart(attachHerdr: Bool) -> PTYStart {
        attachHerdr ? .exec(command) : .loginShell
    }

    /// Command to send as an SSH exec request, or `nil` for a login shell.
    static func execCommand(attachHerdr: Bool) -> String? {
        switch ptyStart(attachHerdr: attachHerdr) {
        case .loginShell: return nil
        case .exec(let command): return command
        }
    }

    /// How a completed tap on the terminal surface should be delivered.
    enum TapDecision: Equatable {
        /// Keep the existing tap path (super-modified link probe; selection and
        /// scroll gestures are unchanged).
        case existingGestures
        /// Unmodified left press+release at the tap point so a mouse-native TUI
        /// (Herdr tabs, panes, menus) can receive the click.
        case mouseLeftClick(x: Double, y: Double)
    }

    static func tapDecision(attachHerdr: Bool, x: Double, y: Double) -> TapDecision {
        attachHerdr ? .mouseLeftClick(x: x, y: y) : .existingGestures
    }

    // MARK: Pinch (font size vs Herdr pane zoom)

    /// Matches the existing font-size pinch step (~12%).
    static let pinchStep = 1.12

    enum PinchPhase: Equatable {
        /// Continuous update; used for font-size stepping.
        case changed
        /// Gesture finished; used for one-shot Herdr pane zoom.
        case ended
    }

    enum PinchAction: Equatable {
        /// Existing path: bump ghostty font size (reflows the grid).
        case changeFontSize(increase: Bool)
        /// Send Herdr pane zoom (`prefix+z`): pinch-out zooms in, pinch-in zooms out.
        case herdrPaneZoom(zoomIn: Bool)
        case none
    }

    /// When Herdr is on, a completed pinch maps to pane zoom instead of font
    /// size — reflowing cols/rows mid-session fights Herdr's layout. When off,
    /// pinch-changed still steps the font size as today.
    /// A PTY grid size to send as an SSH window-change.
    struct GridSize: Equatable {
        var cols: Int
        var rows: Int
    }

    /// After the app returns from the background, Herdr (and other full-screen
    /// TUIs) need a SIGWINCH to emit a complete frame — live updates were
    /// frozen with the process. Same-size window-change is often ignored, so
    /// Herdr gets a one-row bump then restore. A login shell just resends the
    /// current size.
    static func windowChangesForForeground(attachHerdr: Bool, cols: Int, rows: Int) -> [GridSize] {
        let cols = max(cols, 1)
        let rows = max(rows, 1)
        if attachHerdr {
            let bumped = rows > 1 ? rows - 1 : rows + 1
            return [GridSize(cols: cols, rows: bumped), GridSize(cols: cols, rows: rows)]
        }
        return [GridSize(cols: cols, rows: rows)]
    }

    static func pinchAction(attachHerdr: Bool, scale: Double, phase: PinchPhase) -> PinchAction {
        if attachHerdr {
            guard phase == .ended else { return .none }
            if scale >= pinchStep { return .herdrPaneZoom(zoomIn: true) }
            if scale <= 1 / pinchStep { return .herdrPaneZoom(zoomIn: false) }
            return .none
        }
        guard phase == .changed else { return .none }
        if scale >= pinchStep { return .changeFontSize(increase: true) }
        if scale <= 1 / pinchStep { return .changeFontSize(increase: false) }
        return .none
    }

    // MARK: Accessory keyboard (phone path)

    /// One key event. `character` is the unshifted or shifted glyph ("b", "q",
    /// "-", "?"); modifiers are applied on top. Foundation-only so tests can
    /// assert the sequence without Ghostty types.
    struct Keystroke: Equatable {
        var character: String
        var ctrl: Bool = false
        var shift: Bool = false
        var alt: Bool = false
    }

    /// A one-tap Herdr action on the accessory bar. Chords are sequential:
    /// prefix (`ctrl+b`) is sent and released, then the follow-up key — the
    /// same model as typing `ctrl+b` then `q` on a hardware keyboard.
    struct Shortcut: Equatable {
        var id: ShortcutID
        var title: String
        var accessibilityLabel: String
        var strokes: [Keystroke]
    }

    enum ShortcutID: String, Equatable, CaseIterable {
        case prefix
        case detach
        case workspace
        case goto
        case newTab
        case previousTab
        case nextTab
        case splitRight
        case splitDown
        case paneLeft
        case paneDown
        case paneUp
        case paneRight
        case zoom
        case sidebar
        case help
    }

    /// Default Herdr prefix: `ctrl+b`.
    static let prefixStroke = Keystroke(character: "b", ctrl: true)

    /// Shortcuts shown on the accessory bar when the Herdr option is on.
    /// Empty when the option is off so the regular key bar is unchanged.
    static func keyboardShortcuts(attachHerdr: Bool) -> [Shortcut] {
        attachHerdr ? phoneShortcuts : []
    }

    static func shortcut(_ id: ShortcutID) -> Shortcut? {
        phoneShortcuts.first { $0.id == id }
    }

    /// The documented first-five bindings plus the phone-path extras
    /// (workspace picker, tab cycle, zoom, help, sidebar).
    private static let phoneShortcuts: [Shortcut] = [
        Shortcut(id: .prefix, title: "Prefix", accessibilityLabel: "Herdr prefix Control-B",
                 strokes: [prefixStroke]),
        chord(.detach, title: "Detach", label: "Detach Herdr session", then: "q"),
        chord(.workspace, title: "Space", label: "Workspace picker", then: "w"),
        chord(.goto, title: "Go", label: "Goto picker", then: "g"),
        chord(.newTab, title: "Tab+", label: "New tab", then: "c"),
        chord(.previousTab, title: "Tab<", label: "Previous tab", then: "p"),
        chord(.nextTab, title: "Tab>", label: "Next tab", then: "n"),
        chord(.splitRight, title: "Split", label: "Split pane right", then: "v"),
        chord(.splitDown, title: "Split-", label: "Split pane down", then: "-"),
        chord(.paneLeft, title: "H", label: "Focus pane left", then: "h"),
        chord(.paneDown, title: "J", label: "Focus pane down", then: "j"),
        chord(.paneUp, title: "K", label: "Focus pane up", then: "k"),
        chord(.paneRight, title: "L", label: "Focus pane right", then: "l"),
        chord(.zoom, title: "Zoom", label: "Zoom focused pane", then: "z"),
        chord(.sidebar, title: "Bar", label: "Toggle sidebar", then: "b"),
        chord(.help, title: "?", label: "Show keybindings", then: "?"),
    ]

    private static func chord(
        _ id: ShortcutID,
        title: String,
        label: String,
        then character: String
    ) -> Shortcut {
        Shortcut(
            id: id,
            title: title,
            accessibilityLabel: label,
            strokes: [prefixStroke, Keystroke(character: character)]
        )
    }
}

/// Encode/decode the saved-connection list. `ConnectionStore` persist/load uses
/// this so tests drive the same codec as the app.
enum SavedConnectionCodec {
    static func encode(_ connections: [SavedConnection]) throws -> Data {
        try JSONEncoder().encode(connections)
    }

    static func decode(_ data: Data) throws -> [SavedConnection] {
        try JSONDecoder().decode([SavedConnection].self, from: data)
    }
}
