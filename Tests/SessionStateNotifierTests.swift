import XCTest

final class SessionStateNotifierTests: XCTestCase {
    func testNotifyDeliversWhenNotStopped() {
        let exp = expectation(description: "delivered")
        var seen: [SSHSessionState] = []
        let notifier = SessionStateNotifier { state in
            seen.append(state)
            exp.fulfill()
        }
        notifier.notify(.connecting)
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(seen, [.connecting])
    }

    /// The skeptic race: `notify(.connected)` hops to main without the stopped
    /// flag set yet; `stop()` then sets it. The main callback must drop the
    /// update so the UI cannot stick on `.connected`.
    func testLateConnectedDroppedAfterStop() {
        let delivered = expectation(description: "must not deliver")
        delivered.isInverted = true
        let notifier = SessionStateNotifier { _ in
            delivered.fulfill()
        }
        notifier.notify(.connected)
        notifier.setStopped(true)
        wait(for: [delivered], timeout: 0.3)
    }

    func testNotifyAfterStopIsDropped() {
        let delivered = expectation(description: "must not deliver")
        delivered.isInverted = true
        let notifier = SessionStateNotifier { _ in
            delivered.fulfill()
        }
        notifier.setStopped(true)
        notifier.notify(.failed("late"))
        notifier.notify(.closed)
        wait(for: [delivered], timeout: 0.3)
    }

    func testFailedDoesNotOverwriteAfterStop() {
        let connecting = expectation(description: "connecting")
        let extra = expectation(description: "no extra after stop")
        extra.expectedFulfillmentCount = 2
        extra.isInverted = true
        var seen: [SSHSessionState] = []
        let notifier = SessionStateNotifier { state in
            seen.append(state)
            if state == .connecting {
                connecting.fulfill()
            } else {
                extra.fulfill()
            }
        }
        notifier.notify(.connecting)
        wait(for: [connecting], timeout: 1)
        XCTAssertEqual(seen, [.connecting])
        notifier.setStopped(true)
        notifier.notify(.connected)
        notifier.notify(.failed("channel closed"))
        wait(for: [extra], timeout: 0.3)
        XCTAssertEqual(seen, [.connecting])
    }
}
