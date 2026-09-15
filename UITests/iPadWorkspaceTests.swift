import XCTest
import UIKit

final class iPadWorkspaceTests: XCTestCase {
    func testWorkspaceNavigationAndRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        maximizeWindow(app)
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 10))
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
        app.launch()
        maximizeWindow(app)
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 10))
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
        terminal.hover()
        terminal.scroll(byDeltaX: 0, deltaY: -300)
        capture("Magic Keyboard scrolled history")
        let selectionStart = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
        let selectionEnd = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3))
        selectionStart.click(forDuration: 0.1, thenDragTo: selectionEnd)
        capture("Magic Keyboard pointer selection")
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
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        maximizeWindow(app)
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 10))
        let originalFrame = app.windows.firstMatch.frame
        let corner = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.99))
        let target = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        corner.click(forDuration: 0.2, thenDragTo: target)
        capture("iPad narrow window")
        XCTAssertLessThan(app.windows.firstMatch.frame.width, originalFrame.width * 0.8)
        XCTAssertTrue(app.buttons["Add host"].exists)
        connectTestHost(app, username: "test")
        XCTAssertTrue(app.buttons["Toggle keyboard"].waitForExistence(timeout: 5))
        capture("iPad narrow terminal")
        app.typeKey("x", modifierFlags: [])
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 5))
        maximizeWindow(app)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, originalFrame.width * 0.8)
    }

    private func maximizeWindow(_ app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        if app.windows.firstMatch.frame.width < UIScreen.main.bounds.width * 0.9 {
            // iPadOS 26 retains window sizes across app launches. Double-tap
            // the window's top edge to restore full size before wide tests.
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.005)).doubleTap()
        }
    }

    private func connectTestHost(_ app: XCUIApplication, username: String) {
        app.buttons["Add host"].tap()
        let name = "Keyboard test \(UUID().uuidString.prefix(6))"
        for (field, value) in [("name (optional)", name), ("host", "127.0.0.1"), ("username", username)] {
            app.textFields[field].tap()
            app.textFields[field].typeText(value)
        }
        app.textFields["port"].tap()
        app.textFields["port"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "62222")
        // Dismiss iPadOS's floating number-pad popover before tapping Save.
        app.textFields["name (optional)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let host = app.staticTexts[name]
        for _ in 0..<12 {
            if host.isHittable && host.frame.maxY < app.buttons["Keys"].frame.minY - 12 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        XCTAssertTrue(app.alerts["Password"].waitForExistence(timeout: 5))
        app.alerts.secureTextFields.firstMatch.typeText("test")
        app.alerts.buttons["Connect"].tap()
        if app.alerts["Unknown Host"].waitForExistence(timeout: 3) {
            app.alerts.buttons["Trust"].tap()
        } else if app.alerts["Host Key Changed"].exists {
            // The loopback fixture generates an ephemeral key on every run.
            app.alerts.buttons["Accept New Key"].tap()
        }
        // A fresh simulator may still be opening the terminal after the host
        // header appears. Wait for SSH readiness before synthesizing keys.
        let status = app.descendants(matching: .any)["connectionStatus"]
        let connected = expectation(for: NSPredicate(format: "value == 'Connected'"), evaluatedWith: status)
        wait(for: [connected], timeout: 10)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
