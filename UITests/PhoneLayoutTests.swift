import XCTest
import UIKit

/// Phone-idiom layout rules. Run on an iPhone 17 Pro Max simulator, whose
/// landscape window is regular-width but compact-height: the size-class rule
/// in RootView must keep tabs there and reserve the workspace for windows that
/// are regular in both axes (the iPhone Duo's inner display).
final class PhoneLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
    }

    func testRegularWidthLandscapeKeepsTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Hosts"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Select a Host"].exists)
        capture("iPhone landscape tabs")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.tabBars.buttons["Hosts"].waitForExistence(timeout: 5))
    }

    /// Exercises the workspace branch on the phone idiom ahead of the iPhone
    /// Duo simulator: sidebar, utility sheet, connect, and Command-W back.
    func testForcedWorkspaceLayoutOnPhone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenWelcome", "YES", "-gtermForceWorkspaceLayout", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["Add host"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Select a Host"].exists)
        XCTAssertFalse(app.tabBars.buttons["Hosts"].exists)
        capture("iPhone forced workspace")

        app.buttons["Keys"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Select a Host"].waitForExistence(timeout: 5))

        connectTestHost(app, username: "test")
        XCTAssertTrue(app.buttons["Toggle keyboard"].waitForExistence(timeout: 5))
        capture("iPhone forced workspace terminal")
        app.typeKey("x", modifierFlags: [])
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Select a Host"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
    }
}
