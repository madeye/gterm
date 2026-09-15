import XCTest

/// Helpers shared by the iPad and iPhone UI suites.
extension XCTestCase {
    func connectTestHost(_ app: XCUIApplication, username: String) {
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

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
