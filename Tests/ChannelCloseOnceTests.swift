import XCTest

private struct DummyError: Error {}

final class ChannelCloseOnceTests: XCTestCase {
    func testErrorThenInactiveKeepsTheError() {
        var once = ChannelCloseOnce()
        var seen: [String] = []
        once.deliver(DummyError()) { error in
            seen.append(error == nil ? "nil" : "err")
        }
        once.deliver(nil) { error in
            seen.append(error == nil ? "nil" : "err")
        }
        XCTAssertEqual(seen, ["err"])
    }

    func testCleanCloseThenErrorStaysClosed() {
        var once = ChannelCloseOnce()
        var seen: [String] = []
        once.deliver(nil) { error in
            seen.append(error == nil ? "nil" : "err")
        }
        once.deliver(DummyError()) { error in
            seen.append(error == nil ? "nil" : "err")
        }
        XCTAssertEqual(seen, ["nil"])
    }
}
