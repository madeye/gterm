import XCTest

final class HerdrSupportTests: XCTestCase {
    func testDefaultConnectionHasHerdrOff() {
        let connection = SavedConnection()
        XCTAssertFalse(connection.attachHerdr)
        XCTAssertEqual(HerdrSupport.ptyStart(attachHerdr: connection.attachHerdr), .loginShell)
        XCTAssertNil(HerdrSupport.execCommand(attachHerdr: connection.attachHerdr))
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: connection.attachHerdr, x: 8, y: 13),
            .existingGestures
        )
    }

    func testOptionOnMapsToHerdrAttachAndMouseLeftClick() {
        var connection = SavedConnection(host: "box.example", username: "me")
        connection.attachHerdr = true

        XCTAssertEqual(HerdrSupport.ptyStart(attachHerdr: connection.attachHerdr), .exec(HerdrSupport.command))
        XCTAssertEqual(HerdrSupport.execCommand(attachHerdr: connection.attachHerdr), HerdrSupport.command)
        XCTAssertEqual(HerdrSupport.command, "exec \"$SHELL\" -ilc 'exec herdr'")
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: connection.attachHerdr, x: 42, y: 17),
            .mouseLeftClick(x: 42, y: 17)
        )
    }

    func testOptionOffMapsToLoginShellAndExistingTapPath() {
        let connection = SavedConnection(host: "box.example", username: "me")
        XCTAssertFalse(connection.attachHerdr)

        XCTAssertEqual(HerdrSupport.ptyStart(attachHerdr: connection.attachHerdr), .loginShell)
        XCTAssertNil(HerdrSupport.execCommand(attachHerdr: connection.attachHerdr))
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: connection.attachHerdr, x: 42, y: 17),
            .existingGestures
        )
    }

    func testCodecPersistReloadOffVsOn() throws {
        var on = SavedConnection(name: "herdr box", host: "h.example", username: "me")
        on.attachHerdr = true
        var off = SavedConnection(name: "plain box", host: "p.example", username: "me")
        off.attachHerdr = false

        let data = try SavedConnectionCodec.encode([on, off])
        let loaded = try SavedConnectionCodec.decode(data)

        XCTAssertEqual(loaded.count, 2)
        let loadedOn = try XCTUnwrap(loaded.first { $0.id == on.id })
        let loadedOff = try XCTUnwrap(loaded.first { $0.id == off.id })
        XCTAssertTrue(loadedOn.attachHerdr)
        XCTAssertFalse(loadedOff.attachHerdr)

        XCTAssertEqual(HerdrSupport.ptyStart(attachHerdr: loadedOn.attachHerdr), .exec(HerdrSupport.command))
        XCTAssertEqual(HerdrSupport.ptyStart(attachHerdr: loadedOff.attachHerdr), .loginShell)
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: loadedOn.attachHerdr, x: 3, y: 9),
            .mouseLeftClick(x: 3, y: 9)
        )
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: loadedOff.attachHerdr, x: 3, y: 9),
            .existingGestures
        )
    }

    func testLegacyPayloadWithoutKeyDefaultsOff() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"old","host":"legacy.example","port":22,"username":"me","keyIDs":[],"savePassword":false}
        """
        let decoded = try JSONDecoder().decode(SavedConnection.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.attachHerdr)
        XCTAssertEqual(decoded.host, "legacy.example")
        XCTAssertEqual(HerdrSupport.ptyStart(attachHerdr: decoded.attachHerdr), .loginShell)
    }

    func testConnectionStorePersistReload() throws {
        let suite = "gterm.tests.connections.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not create suite")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ConnectionStore(defaults: defaults)
        var on = SavedConnection(host: "on.example", username: "me")
        on.attachHerdr = true
        let off = SavedConnection(host: "off.example", username: "me")
        XCTAssertFalse(off.attachHerdr)

        store.save(on, password: nil)
        store.save(off, password: nil)

        let reloaded = ConnectionStore(defaults: defaults)
        let loadedOn = try XCTUnwrap(reloaded.connections.first { $0.id == on.id })
        let loadedOff = try XCTUnwrap(reloaded.connections.first { $0.id == off.id })
        XCTAssertTrue(loadedOn.attachHerdr)
        XCTAssertFalse(loadedOff.attachHerdr)
        XCTAssertEqual(HerdrSupport.execCommand(attachHerdr: loadedOn.attachHerdr), HerdrSupport.command)
        XCTAssertNil(HerdrSupport.execCommand(attachHerdr: loadedOff.attachHerdr))
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: loadedOn.attachHerdr, x: 1, y: 2),
            .mouseLeftClick(x: 1, y: 2)
        )
        XCTAssertEqual(
            HerdrSupport.tapDecision(attachHerdr: loadedOff.attachHerdr, x: 1, y: 2),
            .existingGestures
        )
    }

    func testConnectionEditorExposesOption() throws {
        let source = try repoSource("Sources/UI/AddConnectionView.swift")
        XCTAssertTrue(source.contains("Attach with Herdr"), "connection editor must expose the option")
        XCTAssertTrue(source.contains("$connection.attachHerdr"), "toggle must bind the persisted flag")
    }

    func testSessionWiresHerdrPTYStart() throws {
        let session = try repoSource("Sources/SSH/SSHSession.swift")
        XCTAssertTrue(
            session.contains("HerdrSupport.ptyStart(attachHerdr: self.connection.attachHerdr)"),
            "SSHSession must start the PTY via the shipped mapping"
        )
        let pty = try repoSource("Sources/SSH/PTYChannelHandler.swift")
        XCTAssertTrue(pty.contains("SSHChannelRequestEvent.ExecRequest"), "PTY must be able to exec herdr")
        XCTAssertTrue(pty.contains("SSHChannelRequestEvent.ShellRequest"), "PTY must still request a login shell")
        XCTAssertTrue(pty.contains("case .exec(let command):"), "PTY must branch on the mapping")
    }

    func testKeyboardShortcutsEmptyWhenOptionOff() {
        XCTAssertEqual(HerdrSupport.keyboardShortcuts(attachHerdr: false), [])
        XCTAssertEqual(
            HerdrSupport.keyboardShortcuts(attachHerdr: SavedConnection().attachHerdr),
            []
        )
    }

    func testKeyboardShortcutsArePrefixThenActionWhenOptionOn() throws {
        let shortcuts = HerdrSupport.keyboardShortcuts(attachHerdr: true)
        XCTAssertFalse(shortcuts.isEmpty, "Herdr accessory row must have shortcuts when the option is on")

        let prefix = HerdrSupport.prefixStroke
        XCTAssertEqual(prefix, HerdrSupport.Keystroke(character: "b", ctrl: true))

        let prefixOnly = try XCTUnwrap(shortcuts.first { $0.id == .prefix })
        XCTAssertEqual(prefixOnly.strokes, [prefix])

        let detach = try XCTUnwrap(shortcuts.first { $0.id == .detach })
        XCTAssertEqual(detach.strokes, [prefix, HerdrSupport.Keystroke(character: "q")])

        let newTab = try XCTUnwrap(shortcuts.first { $0.id == .newTab })
        XCTAssertEqual(newTab.strokes, [prefix, HerdrSupport.Keystroke(character: "c")])

        let splitDown = try XCTUnwrap(shortcuts.first { $0.id == .splitDown })
        XCTAssertEqual(splitDown.strokes, [prefix, HerdrSupport.Keystroke(character: "-")])

        let help = try XCTUnwrap(shortcuts.first { $0.id == .help })
        XCTAssertEqual(help.strokes, [prefix, HerdrSupport.Keystroke(character: "?")])

        // Every action except the prefix key itself is ctrl+b then one follow-up.
        for shortcut in shortcuts where shortcut.id != .prefix {
            XCTAssertEqual(shortcut.strokes.first, prefix, "\(shortcut.id) must start with the prefix")
            XCTAssertEqual(shortcut.strokes.count, 2, "\(shortcut.id) must be prefix then one key")
        }
    }

    func testAccessoryBarWiresHerdrShortcuts() throws {
        let accessory = try repoSource("Sources/Ghostty/AccessoryKeyboardView.swift")
        XCTAssertTrue(
            accessory.contains("HerdrSupport.keyboardShortcuts(attachHerdr:"),
            "accessory bar must show shortcuts from the shipped mapping"
        )
        XCTAssertTrue(accessory.contains("sendHerdrShortcut(shortcut)"))
        XCTAssertTrue(accessory.contains("setHerdrEnabled"))

        let surface = try repoSource("Sources/Ghostty/TerminalSurfaceView.swift")
        XCTAssertTrue(surface.contains("func sendHerdrShortcut"))
        XCTAssertTrue(surface.contains("for stroke in shortcut.strokes"))
        XCTAssertTrue(surface.contains("sendKey(key, mods: mods)"))
        XCTAssertTrue(surface.contains("sendCharacter(stroke.character)"))
        XCTAssertTrue(surface.contains("accessory.setHerdrEnabled(attachHerdr)"))
    }

    func testPinchOffStepsFontSizeOnChangedNotEnded() {
        XCTAssertEqual(HerdrSupport.pinchStep, 1.12)
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: false, scale: 1.12, phase: .changed),
            .changeFontSize(increase: true)
        )
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: false, scale: 1 / 1.12, phase: .changed),
            .changeFontSize(increase: false)
        )
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: false, scale: 1.12, phase: .ended),
            .none
        )
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: false, scale: 1.0, phase: .changed),
            .none
        )
    }

    func testPinchOnMapsToHerdrPaneZoomOnEndedNotChanged() {
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: true, scale: 1.12, phase: .changed),
            .none,
            "must not send prefix+z on every pinch tick"
        )
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: true, scale: 1.12, phase: .ended),
            .herdrPaneZoom(zoomIn: true)
        )
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: true, scale: 1 / 1.12, phase: .ended),
            .herdrPaneZoom(zoomIn: false)
        )
        XCTAssertEqual(
            HerdrSupport.pinchAction(attachHerdr: true, scale: 1.0, phase: .ended),
            .none
        )
        let zoom = HerdrSupport.shortcut(.zoom)
        XCTAssertEqual(zoom?.strokes, [
            HerdrSupport.prefixStroke,
            HerdrSupport.Keystroke(character: "z"),
        ])
    }

    func testForegroundWindowChangeBumpsThenRestoresForHerdr() {
        XCTAssertEqual(
            HerdrSupport.windowChangesForForeground(attachHerdr: false, cols: 80, rows: 24),
            [HerdrSupport.GridSize(cols: 80, rows: 24)]
        )
        XCTAssertEqual(
            HerdrSupport.windowChangesForForeground(attachHerdr: true, cols: 80, rows: 24),
            [
                HerdrSupport.GridSize(cols: 80, rows: 23),
                HerdrSupport.GridSize(cols: 80, rows: 24),
            ]
        )
        XCTAssertEqual(
            HerdrSupport.windowChangesForForeground(attachHerdr: true, cols: 40, rows: 1),
            [
                HerdrSupport.GridSize(cols: 40, rows: 2),
                HerdrSupport.GridSize(cols: 40, rows: 1),
            ]
        )
    }

    func testForegroundResumeWiresRefreshAndWindowChange() throws {
        let surface = try repoSource("Sources/Ghostty/TerminalSurfaceView.swift")
        XCTAssertTrue(surface.contains("UIApplication.didBecomeActiveNotification"))
        XCTAssertTrue(surface.contains("UIApplication.willResignActiveNotification"))
        XCTAssertTrue(surface.contains("ghostty_surface_set_occlusion"))
        XCTAssertTrue(surface.contains("ghostty_surface_refresh"))
        XCTAssertTrue(surface.contains("ghostty_surface_draw"))
        XCTAssertTrue(surface.contains("terminalSurfaceDidResume"))

        let session = try repoSource("Sources/SSH/SSHSession.swift")
        XCTAssertTrue(
            session.contains("HerdrSupport.windowChangesForForeground("),
            "resume must send the shipped window-change sequence"
        )
        XCTAssertTrue(session.contains("func terminalSurfaceDidResume"))
    }

    func testPinchPathWiresHerdrPaneZoom() throws {
        let source = try repoSource("Sources/Ghostty/TerminalSurfaceView.swift")
        XCTAssertTrue(
            source.contains("HerdrSupport.pinchAction("),
            "pinch handler must use the shipped decision"
        )
        XCTAssertTrue(source.contains("case .herdrPaneZoom(let zoomIn):"))
        XCTAssertTrue(source.contains("applyHerdrPaneZoom(zoomIn: zoomIn)"))
        XCTAssertTrue(source.contains("HerdrSupport.shortcut(.zoom)"))
        XCTAssertTrue(source.contains("case .changeFontSize(let increase):"))
        XCTAssertTrue(source.contains("increase_font_size:1"))
        XCTAssertTrue(source.contains("decrease_font_size:1"))
    }

    func testTapPathIssuesLeftPressReleaseWhenHerdrOn() throws {
        let source = try repoSource("Sources/Ghostty/TerminalSurfaceView+Link.swift")
        XCTAssertTrue(
            source.contains("HerdrSupport.tapDecision(attachHerdr: attachHerdr"),
            "tap path must use the shipped tap-mode decision"
        )
        XCTAssertTrue(source.contains("case .mouseLeftClick(let x, let y):"))
        XCTAssertTrue(source.contains("GHOSTTY_MOUSE_PRESS"))
        XCTAssertTrue(source.contains("GHOSTTY_MOUSE_RELEASE"))
        XCTAssertTrue(source.contains("GHOSTTY_MOUSE_LEFT"))
        XCTAssertTrue(source.contains("Ghostty.Mods.none.cMods"))
        XCTAssertTrue(source.contains("case .existingGestures:"))
        XCTAssertTrue(source.contains("GHOSTTY_MODS_SUPER"))
    }

    private func repoSource(_ relative: String) throws -> String {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = tests.deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
