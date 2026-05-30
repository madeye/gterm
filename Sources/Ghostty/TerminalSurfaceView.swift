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
    }

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

    // MARK: Accessory keyboard + sticky modifiers

    /// Modifiers "armed" by the accessory bar, applied to the next keypress.
    private(set) var stickyMods: Ghostty.Mods = .none

    private lazy var accessory = AccessoryKeyboardView(target: self)

    override var inputAccessoryView: UIView? { accessory }

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
            sendText(s)
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

    /// Send printable text (bypasses key encoding). Use for IME / pasted text.
    func sendText(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        let len = text.utf8.count
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len))
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
