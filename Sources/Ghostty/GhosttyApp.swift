import UIKit
import GhosttyKit
import os

extension Ghostty {
    static let logger = Logger(subsystem: "io.github.madeye.gterm", category: "ghostty")

    /// Owns the single `ghostty_app_t`. `ghostty_init` is called once at
    /// startup; the app is created with the runtime callbacks libghostty uses
    /// to talk back to us (wakeup, actions, clipboard).
    final class App: ObservableObject {
        let config: Config
        private(set) var app: ghostty_app_t?
        private var displayLink: CADisplayLink?

        init() {
            // ghostty_init must be called exactly once before ghostty_app_new.
            if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
                Ghostty.logger.critical("ghostty_init failed")
            }

            self.config = Config()

            var runtime = ghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                supports_selection_clipboard: false,
                wakeup_cb: { ud in App.wakeup(ud) },
                action_cb: { app, target, action in App.action(app, target, action) },
                read_clipboard_cb: { ud, loc, state in App.readClipboard(ud, loc, state) },
                confirm_read_clipboard_cb: { ud, str, state, req in
                    App.confirmReadClipboard(ud, str, state, req)
                },
                write_clipboard_cb: { ud, loc, content, len, confirm in
                    App.writeClipboard(ud, loc, content, len, confirm)
                },
                close_surface_cb: { ud, alive in App.closeSurface(ud, alive) }
            )

            guard let app = ghostty_app_new(&runtime, config.c) else {
                Ghostty.logger.critical("ghostty_app_new failed")
                return
            }
            self.app = app
            ghostty_app_set_focus(app, true)
            startDisplayLink()
        }

        deinit {
            displayLink?.invalidate()
            if let app { ghostty_app_free(app) }
        }

        func tick() {
            guard let app else { return }
            ghostty_app_tick(app)
        }

        /// Drive `ghostty_app_tick` once per display refresh so animations
        /// (cursor blink, etc.) advance smoothly, in addition to the on-demand
        /// wakeup callback. A weak proxy avoids the CADisplayLink→target retain
        /// cycle so the app can still be torn down.
        private func startDisplayLink() {
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private final class DisplayLinkProxy {
            weak var app: App?
            init(_ app: App) { self.app = app }
            @objc func step() { app?.tick() }
        }

        func setColorScheme(_ scheme: ghostty_color_scheme_e) {
            guard let app else { return }
            ghostty_app_set_color_scheme(app, scheme)
        }

        // MARK: - Runtime callbacks (C, no capture; recover self/view via userdata)

        private static func from(_ ud: UnsafeMutableRawPointer?) -> App? {
            guard let ud else { return nil }
            return Unmanaged<App>.fromOpaque(ud).takeUnretainedValue()
        }

        private static func surfaceView(_ surface: ghostty_surface_t?) -> TerminalSurfaceView? {
            guard let surface, let ud = ghostty_surface_userdata(surface) else { return nil }
            return Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
        }

        /// Clipboard and close callbacks receive the *surface* userdata, which
        /// we set to the TerminalSurfaceView, so recover it directly.
        private static func viewFromSurfaceUserdata(
            _ ud: UnsafeMutableRawPointer?
        ) -> TerminalSurfaceView? {
            guard let ud else { return nil }
            return Unmanaged<TerminalSurfaceView>.fromOpaque(ud).takeUnretainedValue()
        }

        static func wakeup(_ ud: UnsafeMutableRawPointer?) {
            guard let app = from(ud) else { return }
            // Wakeup can be called from any thread; tick on main.
            DispatchQueue.main.async { app.tick() }
        }

        static func action(
            _ app: ghostty_app_t?,
            _ target: ghostty_target_s,
            _ action: ghostty_action_s
        ) -> Bool {
            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                guard target.tag == GHOSTTY_TARGET_SURFACE,
                      let view = surfaceView(target.target.surface),
                      let cstr = action.action.set_title.title else { return false }
                let title = String(cString: cstr)
                DispatchQueue.main.async { view.didChangeTitle(title) }
                return true

            case GHOSTTY_ACTION_RING_BELL:
                guard target.tag == GHOSTTY_TARGET_SURFACE,
                      let view = surfaceView(target.target.surface) else { return false }
                DispatchQueue.main.async { view.didRingBell() }
                return true

            case GHOSTTY_ACTION_PWD:
                guard target.tag == GHOSTTY_TARGET_SURFACE,
                      let view = surfaceView(target.target.surface),
                      let cstr = action.action.pwd.pwd else { return false }
                let pwd = String(cString: cstr)
                DispatchQueue.main.async { view.didChangePwd(pwd) }
                return true

            default:
                // Many actions are macOS/window-manager specific and don't
                // apply on iOS. Returning false marks them unperformed.
                return false
            }
        }

        // Clipboard: iOS uses a single UIPasteboard (no selection clipboard).
        static func readClipboard(
            _ ud: UnsafeMutableRawPointer?,
            _ loc: ghostty_clipboard_e,
            _ state: UnsafeMutableRawPointer?
        ) -> Bool {
            guard let view = viewFromSurfaceUserdata(ud) else { return false }
            let str = UIPasteboard.general.string ?? ""
            view.completeClipboardRequest(str, state: state)
            return true
        }

        static func confirmReadClipboard(
            _ ud: UnsafeMutableRawPointer?,
            _ str: UnsafePointer<CChar>?,
            _ state: UnsafeMutableRawPointer?,
            _ req: ghostty_clipboard_request_e
        ) {
            // No confirmation prompt yet; complete the request directly.
            guard let view = viewFromSurfaceUserdata(ud), let str else { return }
            view.completeClipboardRequest(String(cString: str), state: state, confirmed: true)
        }

        static func writeClipboard(
            _ ud: UnsafeMutableRawPointer?,
            _ loc: ghostty_clipboard_e,
            _ content: UnsafePointer<ghostty_clipboard_content_s>?,
            _ len: Int,
            _ confirm: Bool
        ) {
            guard let content, len > 0 else { return }
            // Write the first text entry to the pasteboard.
            for i in 0..<len {
                guard let dataPtr = content[i].data else { continue }
                UIPasteboard.general.string = String(cString: dataPtr)
                break
            }
        }

        static func closeSurface(_ ud: UnsafeMutableRawPointer?, _ alive: Bool) {
            guard let view = viewFromSurfaceUserdata(ud) else { return }
            DispatchQueue.main.async { view.requestClose() }
        }
    }
}
