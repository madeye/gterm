import UIKit
import GhosttyKit

/// Receives terminal output and lifecycle events from a TerminalSurfaceView.
/// Output/resize callbacks originate on libghostty's IO thread — implementers
/// must hop to their own queue and must not block.
protocol TerminalSurfaceViewDelegate: AnyObject {
    /// Bytes the terminal wants to send to the "pty" (keyboard input, query
    /// responses, etc.). Forward these to the transport (e.g. SSH channel).
    func terminalSurface(_ view: TerminalSurfaceView, didProduceOutput data: Data)

    /// The terminal grid was resized; notify the remote (SSH window-change).
    func terminalSurface(_ view: TerminalSurfaceView, didResizeToCols cols: Int, rows: Int)

    /// The terminal title changed (OSC 0/2).
    func terminalSurface(_ view: TerminalSurfaceView, didChangeTitle title: String)
}

extension TerminalSurfaceViewDelegate {
    func terminalSurface(_ view: TerminalSurfaceView, didChangeTitle title: String) {}
}

/// A UIView that hosts a libghostty terminal surface (rendered into its
/// CAMetalLayer) driven by the passthru IO backend. Input is sent via the
/// ghostty key/text C API; received bytes are pushed in via `receive(_:)`.
final class TerminalSurfaceView: UIView {
    weak var delegate: TerminalSurfaceViewDelegate?

    private weak var ghostty: Ghostty.App?
    private var surface: ghostty_surface_t?

    private(set) var title: String = "gterm"

    // MARK: Init

    init(ghostty: Ghostty.App) {
        self.ghostty = ghostty
        // Non-zero initial frame so the Metal layer has a drawable size.
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        backgroundColor = .black
        isOpaque = true
        contentMode = .redraw

        // Pinch (two-finger) to change the font size, which reflows the grid.
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        // Track software-keyboard visibility so a tap can re-summon a keyboard
        // dismissed with the iPadOS hide key (which hides the keyboard without
        // necessarily resigning first responder). Selector-based observers are
        // auto-removed on dealloc.
        let nc = NotificationCenter.default
        nc.addObserver(
            self, selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification, object: nil
        )
        nc.addObserver(
            self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )

        guard let app = ghostty.app else {
            Ghostty.logger.error("TerminalSurfaceView created without a ghostty app")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_IOS
        cfg.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(uiview: selfPtr))
        cfg.userdata = selfPtr
        cfg.scale_factor = Double(window?.screen.scale ?? UIScreen.main.scale)
        cfg.font_size = 0
        cfg.io_backend = GHOSTTY_IO_BACKEND_PASSTHRU
        cfg.pty_write_cb = { ud, ptr, len in
            guard let ud, let ptr, len > 0 else { return }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
            view.handlePtyWrite(Data(bytes: ptr, count: Int(len)))
        }
        cfg.pty_resize_cb = { ud, cols, rows, _, _ in
            guard let ud else { return }
            let view = Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
            view.handlePtyResize(cols: Int(cols), rows: Int(rows))
        }

        guard let surface = ghostty_surface_new(app, &cfg) else {
            Ghostty.logger.error("ghostty_surface_new failed")
            return
        }
        self.surface = surface
        setupSelectionGestures()
        setupScrollGesture()
        setupLinkTapGesture()
    }

    // MARK: Link opening

    /// Called when the user taps a URL in the terminal; the SwiftUI layer routes
    /// it to the in-app browser. Set by the hosting view.
    var onOpenURL: ((URL) -> Void)?

    /// Invoked from libghostty's OPEN_URL action (via Ghostty.App) when a clicked
    /// link is followed. Parses and forwards the URL on the main thread.
    func didRequestOpenURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        onOpenURL?(url)
    }

    // MARK: Selection / clipboard gesture state (see TerminalSurfaceView+Selection)

    /// Where the active long-press began, and whether it has moved far enough to
    /// count as a selection drag (vs. a stationary hold-to-paste).
    var selectionStart: CGPoint?
    var selectionMoved = false

    // MARK: Scroll gesture state (see TerminalSurfaceView+Scroll)

    /// Cumulative pan translation already converted to scroll, so each `.changed`
    /// only forwards the incremental delta.
    var lastScrollTranslationY: CGFloat = 0

    /// The scroll pan recognizer, disabled while a selection long-press is active
    /// so the two gestures never run together.
    weak var scrollPan: UIPanGestureRecognizer?

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    // MARK: UIView

    // Note: we intentionally do NOT override layerClass. ghostty's iOS Metal
    // renderer creates its own IOSurface-backed CALayer and adds it as a
    // sublayer of this view's layer (it can't replace UIView.layer, which is
    // read-only). We just need a plain CALayer container and to keep that
    // sublayer sized to our bounds (ghostty adds it but never sizes it).

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncSize()
        sizeRenderLayers()
        if window != nil {
            _ = becomeFirstResponder()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncSize()
        sizeRenderLayers()
    }

    /// Keep ghostty's render sublayer(s) filling our bounds. ghostty adds an
    /// IOSurface-backed layer as a sublayer but leaves its frame at zero, so
    /// without this nothing is visible.
    private func sizeRenderLayers() {
        guard let sublayers = layer.sublayers, !sublayers.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sub in sublayers {
            sub.frame = bounds
        }
        CATransaction.commit()
    }

    private func syncSize() {
        guard let surface else { return }
        let scale = window?.screen.scale ?? UIScreen.main.scale
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        let size = bounds.size
        ghostty_surface_set_size(
            surface,
            UInt32(max(size.width, 1) * scale),
            UInt32(max(size.height, 1) * scale)
        )
    }

    // MARK: Focus / keyboard

    override var canBecomeFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if let surface { ghostty_surface_set_focus(surface, true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if let surface { ghostty_surface_set_focus(surface, false) }
        return ok
    }

    /// Whether the software keyboard (or the accessory bar when a hardware
    /// keyboard is attached) is currently on screen.
    private var keyboardVisible = false

    @objc private func keyboardDidShow() { keyboardVisible = true }
    @objc private func keyboardWillHide() { keyboardVisible = false }

    /// Bring the software keyboard back if the user dismissed it (e.g. with the
    /// iPadOS keyboard hide key, or the accessory bar's collapse button). The
    /// single-tap gesture calls this so tapping the terminal expands it again.
    func showKeyboardIfNeeded() {
        if !isFirstResponder {
            _ = becomeFirstResponder()
        } else if !keyboardVisible {
            // Still first responder but the keyboard is hidden: cycle the
            // responder to force the keyboard back up.
            _ = resignFirstResponder()
            _ = becomeFirstResponder()
        }
    }

    /// Collapse the on-screen keyboard (and the accessory bar with it), giving
    /// the whole screen to the terminal. Tapping the terminal or the status-bar
    /// keyboard button expands it again.
    func collapseKeyboard() {
        _ = resignFirstResponder()
    }

    /// Toggle the on-screen keyboard: collapse when visible, expand otherwise.
    func toggleKeyboard() {
        if isFirstResponder && keyboardVisible {
            collapseKeyboard()
        } else {
            showKeyboardIfNeeded()
        }
    }

    // MARK: Font size (pinch-to-zoom)

    /// Perform a libghostty keybind action by name (e.g. "increase_font_size:1").
    @discardableResult
    private func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        let len = action.utf8.count
        return action.withCString { ghostty_surface_binding_action(surface, $0, UInt(len)) }
    }

    /// Two-finger pinch adjusts the font size one point at a time. Each ~12%
    /// of pinch crosses a step; we reset the recognizer's scale after stepping
    /// so a continuous pinch keeps zooming. Changing the font size reflows the
    /// grid, which fires the resize callback (-> SSH window-change).
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let step: CGFloat = 1.12
        if gesture.scale >= step {
            performBindingAction("increase_font_size:1")
            gesture.scale = 1
        } else if gesture.scale <= 1 / step {
            performBindingAction("decrease_font_size:1")
            gesture.scale = 1
        }
    }

    // MARK: Accessory keyboard + sticky modifiers

    /// Modifiers "armed" by the accessory bar, applied to the next keypress.
    private(set) var stickyMods: Ghostty.Mods = .none

    lazy var accessory = AccessoryKeyboardView(target: self)

    override var inputAccessoryView: UIView? { accessory }

    /// LLM autocompletion engine (lazy: only built when first needed).
    lazy var completionEngine = CompletionEngine()

    /// Internal accessors for the completion extension (in another file).
    var ghosttySurface: ghostty_surface_t? { surface }
    var liveCurrentLine: String { currentLine }

    @discardableResult func toggleCtrl() -> Bool {
        if stickyMods.contains(.ctrl) { stickyMods.remove(.ctrl) } else { stickyMods.insert(.ctrl) }
        return stickyMods.contains(.ctrl)
    }

    @discardableResult func toggleAlt() -> Bool {
        if stickyMods.contains(.alt) { stickyMods.remove(.alt) } else { stickyMods.insert(.alt) }
        return stickyMods.contains(.alt)
    }

    func clearStickyMods() {
        guard !stickyMods.isEmpty else { return }
        stickyMods = .none
        accessory.updateModifierState(ctrl: false, alt: false)
    }

    /// Send a special key (esc, arrows, tab, ...) with any armed modifiers,
    /// then clear them.
    func pressSpecial(_ key: Ghostty.Key) {
        sendKey(key, mods: stickyMods)
        clearStickyMods()
    }

    /// Insert a printable symbol from the accessory bar, applying armed
    /// modifiers if any (e.g. Ctrl-/, Alt-|).
    func insertSymbol(_ s: String) {
        guard !stickyMods.isEmpty else {
            sendCharacter(s) // typed input: avoid bracketed-paste wrapping
            return
        }
        if let ch = s.first, let (key, shift) = Ghostty.Key.physical(for: ch) {
            sendKey(key, mods: shift ? stickyMods.union(.shift) : stickyMods)
        } else {
            // Can't encode as a key event; send as text but still consume the
            // armed modifiers so the accessory bar doesn't show a stuck state.
            sendText(s)
        }
        clearStickyMods()
    }

    // MARK: Command-line autosuggest (local input mirror)

    /// Best-effort mirror of the command line the user is currently typing, used
    /// to drive history-based autocomplete in the accessory bar. It is updated
    /// from the input we send and reset whenever the line state becomes
    /// unpredictable (control combos, cursor movement, tab completion). It can
    /// drift from the real shell line, so suggestions only ever append a suffix.
    private var currentLine = ""

    /// Feed printable text into the line mirror; newlines commit the line.
    private func noteInputText(_ text: String) {
        var appended = false
        for ch in text {
            if ch.isNewline {
                commitLine()
                appended = false
            } else if Self.isPrintable(ch) {
                currentLine.append(ch)
                appended = true
            }
        }
        if appended { refreshSuggestions() }
    }

    /// Feed a key event into the line mirror.
    private func noteInputKey(_ key: Ghostty.Key, mods: Ghostty.Mods) {
        // A Ctrl/Alt/Cmd combo edits or interrupts the line in ways we can't
        // model (Ctrl-C, Ctrl-U, Alt-b, …) — drop the mirror.
        if !mods.subtracting(.shift).isEmpty {
            resetLine()
            return
        }
        switch key {
        case .enter:
            commitLine()
        case .backspace:
            if !currentLine.isEmpty {
                currentLine.removeLast()
                refreshSuggestions()
            }
        default:
            // Arrows, tab, esc, del, home/end, page, function keys: the line
            // contents become unpredictable, so stop mirroring until the next
            // fresh line. (Printable keys never reach here without a modifier.)
            if key.isSpecial { resetLine() }
        }
    }

    /// Apply a chosen autosuggestion by sending only the characters beyond what
    /// the user has already typed.
    func applySuggestion(_ full: String) {
        guard full.count > currentLine.count, full.hasPrefix(currentLine) else { return }
        sendText(String(full.dropFirst(currentLine.count)))
    }

    private func commitLine() {
        CommandHistory.shared.record(currentLine)
        currentLine = ""
        refreshSuggestions()
    }

    private func resetLine() {
        guard !currentLine.isEmpty else { return }
        currentLine = ""
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        let suggestions = currentLine.isEmpty
            ? []
            : CommandHistory.shared.suggestions(prefix: currentLine)
        accessory.setHistorySuggestions(suggestions)
        requestAICompletion(currentLine: currentLine)
    }

    private static func isPrintable(_ ch: Character) -> Bool {
        if let ascii = ch.asciiValue { return ascii >= 0x20 && ascii != 0x7f }
        return !ch.isNewline // keep non-ASCII letters / symbols
    }

    /// Current terminal grid size (columns, rows). Falls back to 80x24 before
    /// the surface has been laid out.
    var gridSize: (cols: Int, rows: Int) {
        guard let surface else { return (80, 24) }
        let sz = ghostty_surface_size(surface)
        return (sz.columns > 0 ? Int(sz.columns) : 80, sz.rows > 0 ? Int(sz.rows) : 24)
    }

    // MARK: Incoming data (transport -> terminal)

    /// Push bytes received from the transport (SSH) into the terminal. Safe to
    /// call from any thread.
    func receive(_ data: Data) {
        guard let surface, !data.isEmpty else { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            ghostty_surface_pty_data(surface, base, UInt(data.count))
        }
    }

    // MARK: Outgoing input (terminal <- user)

    /// Send pasted text. This is `ghostty_surface_text`, which applies bracketed
    /// paste (ESC[200~ … ESC[201~) when the program enables DECSET 2004 —
    /// correct for a paste, WRONG for typing. Use `sendCharacter` for typed input.
    func sendText(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        noteInputText(text)
        let len = text.utf8.count
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len))
        }
    }

    /// Send typed (soft keyboard) characters as key events. Unlike `sendText`,
    /// this is NOT wrapped in bracketed paste, so a keystroke after the tmux
    /// prefix (Ctrl-B :) reaches the program as a bare byte rather than a paste.
    /// Each printable character is sent through ghostty's key encoder carrying
    /// the literal text with its physical keycode; anything without a known key
    /// (CJK/emoji IME commits) falls back to the text path.
    func sendCharacter(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        noteInputText(text)
        for ch in text {
            let s = String(ch)
            guard let key = Ghostty.Key.physical(for: ch)?.key else {
                let len = s.utf8.count
                s.withCString { ptr in ghostty_surface_text(surface, ptr, UInt(len)) }
                continue
            }
            var ev = ghostty_input_key_s()
            ev.action = Ghostty.KeyAction.press.cAction
            ev.keycode = UInt32(key.macKeyCode)
            ev.mods = Ghostty.Mods.none.cMods
            ev.consumed_mods = Ghostty.Mods.none.cMods
            ev.unshifted_codepoint = s.unicodeScalars.first?.value ?? 0
            ev.composing = false
            s.withCString { ptr in
                ev.text = ptr
                _ = ghostty_surface_key(surface, ev)
            }
        }
    }

    /// Type a command into the terminal and run it. Multi-line input is sent
    /// line by line, each followed by Enter. Used by the AI command assistant;
    /// goes through the typed-key path so it is never bracketed-paste wrapped.
    func runCommand(_ command: String) {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sendCharacter(trimmed) }
            sendKey(.enter)
        }
    }

    /// Send a key press through ghostty's encoder (mode-aware). Use for special
    /// keys (arrows, esc, tab, enter, ...) and control combos (Ctrl-C).
    func sendKey(
        _ key: Ghostty.Key,
        mods: Ghostty.Mods = .none,
        action: Ghostty.KeyAction = .press,
        text: String? = nil
    ) {
        guard let surface else { return }
        if action == .press { noteInputKey(key, mods: mods) }
        let ev = Ghostty.KeyEvent(key: key, action: action, mods: mods, text: text)
        ev.withCValue { c in
            _ = ghostty_surface_key(surface, c)
        }
    }

    // MARK: Callbacks from libghostty (IO thread)

    fileprivate func handlePtyWrite(_ data: Data) {
        delegate?.terminalSurface(self, didProduceOutput: data)
    }

    fileprivate func handlePtyResize(cols: Int, rows: Int) {
        delegate?.terminalSurface(self, didResizeToCols: cols, rows: rows)
    }

    func didChangeTitle(_ title: String) {
        self.title = title
        delegate?.terminalSurface(self, didChangeTitle: title)
    }

    func didRingBell() {
        // Light haptic for the bell.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func didChangePwd(_ pwd: String) {}

    func requestClose() {}

    // MARK: Clipboard

    func completeClipboardRequest(
        _ str: String,
        state: UnsafeMutableRawPointer?,
        confirmed: Bool = true
    ) {
        guard let surface else { return }
        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
        }
    }
}
