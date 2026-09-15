import XCTest
import UIKit

final class iPadWorkspaceTests: XCTestCase {
    func testWorkspaceNavigationAndRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        try launchWorkspace(app)
        XCTAssertTrue(app.staticTexts["Select a Host"].exists)
        capture("iPad landscape workspace")

        app.buttons["Keys"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Select a Host"].waitForExistence(timeout: 5))

        app.buttons["Add host"].tap()
        XCTAssertTrue(app.textFields["host"].waitForExistence(timeout: 5))
        capture("iPad host editor")
        app.buttons["Cancel"].tap()

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 5))
        capture("iPad portrait workspace")
        app.buttons["Settings"].tap()
        app.buttons["Get Started Guide"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Select a Host"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testMagicKeyboardCommandsKeepFocusWhenSoftwareKeyboardIsHidden() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        try launchWorkspace(app)
        connectTestHost(app, username: "test")
        XCTAssertTrue(app.buttons["Toggle keyboard"].waitForExistence(timeout: 5))
        app.buttons["Toggle keyboard"].tap()
        let status = app.descendants(matching: .any)["connectionStatus"]
        let connected = expectation(for: NSPredicate(format: "value == 'Connected'"), evaluatedWith: status)
        wait(for: [connected], timeout: 5)
        // The simulator's first synthetic key enables hardware input and
        // may omit modifiers; prime that transition with an unmodified key.
        app.typeKey("x", modifierFlags: [])
        app.typeKey("c", modifierFlags: .control)
        app.typeKey("d", modifierFlags: .control)
        app.typeKey("x", modifierFlags: .option)
        app.typeKey("=", modifierFlags: .command)
        app.typeKey("0", modifierFlags: .command)
        let terminal = app.descendants(matching: .any)["terminalSurface"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 5))
        // XCUITest synthesizes pointer events only on iPad.
        if UIDevice.current.userInterfaceIdiom == .pad {
            terminal.hover()
            terminal.scroll(byDeltaX: 0, deltaY: -300)
            capture("Magic Keyboard scrolled history")
            let selectionStart = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
            let selectionEnd = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3))
            selectionStart.click(forDuration: 0.1, thenDragTo: selectionEnd)
            capture("Magic Keyboard pointer selection")
        }
        app.typeKey("c", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        capture("Magic Keyboard terminal with software keyboard hidden")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Toggle keyboard"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Select a Host"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        connectTestHost(app, username: "test2")
        XCTAssertTrue(app.staticTexts["test2@127.0.0.1"].waitForExistence(timeout: 5))
        app.typeKey("x", modifierFlags: [])
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["test@127.0.0.1"].waitForExistence(timeout: 5))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["test2@127.0.0.1"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testWindowResizingKeepsHostsReachable() throws {
        // Window corner drags and the title-edge double-tap are iPadOS-only.
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        try launchWorkspace(app)
        let originalFrame = mainWindow(app).frame
        let corner = mainWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.99))
        let target = mainWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        corner.click(forDuration: 0.2, thenDragTo: target)
        capture("iPad narrow window")
        XCTAssertLessThan(mainWindow(app).frame.width, originalFrame.width * 0.8)
        XCTAssertTrue(app.buttons["Add host"].exists)
        connectTestHost(app, username: "test")
        XCTAssertTrue(app.buttons["Toggle keyboard"].waitForExistence(timeout: 5))
        capture("iPad narrow terminal")
        app.typeKey("x", modifierFlags: [])
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 5))
        maximizeWindow(app)
        capture("iPad restored window")
        XCTAssertTrue(waitForWindowWidth(app, atLeast: originalFrame.width * 0.8),
                      "window width \(mainWindow(app).frame.width) after restoring from \(originalFrame.width)")
    }

    /// Launches into the sidebar workspace, or skips on devices that show the
    /// tab layout (every shipping iPhone). The iPhone Duo's inner display is
    /// regular in both axes and runs these tests like an iPad.
    private func launchWorkspace(_ app: XCUIApplication) throws {
        app.launch()
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 10))
        try XCTSkipIf(app.tabBars.buttons["Hosts"].exists, "tab layout: workspace tests need a regular-by-regular window")
        maximizeWindow(app)
    }

    /// The app owns several windows (keyboard, text effects) whose frames can
    /// be reported in a different orientation. Target the one hosting Hosts.
    private func mainWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.containing(.button, identifier: "Add host").firstMatch
    }

    private func maximizeWindow(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 10))
        let wide = UIScreen.main.bounds.width * 0.9
        if mainWindow(app).frame.width < wide {
            // iPadOS 26 retains window sizes across app launches. Double-tap
            // the window's top edge to restore full size before wide tests.
            mainWindow(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.005)).doubleTap()
            waitForWindowWidth(app, atLeast: wide)
        }
    }

    /// The zoom animates, so require two consecutive wide reads.
    @discardableResult
    private func waitForWindowWidth(_ app: XCUIApplication, atLeast minWidth: CGFloat, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var wideReads = 0
        while Date() < deadline {
            if mainWindow(app).frame.width >= minWidth {
                wideReads += 1
                if wideReads >= 2 { return true }
            } else {
                wideReads = 0
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return mainWindow(app).frame.width >= minWidth
    }
}
