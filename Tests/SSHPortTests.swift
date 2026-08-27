import XCTest

final class SSHPortTests: XCTestCase {
    func testAcceptsTypicalPorts() {
        XCTAssertEqual(SSHPort.parse("22"), 22)
        XCTAssertEqual(SSHPort.parse("2222"), 2222)
        XCTAssertEqual(SSHPort.parse("65535"), 65535)
        XCTAssertEqual(SSHPort.parse(" 443 "), 443)
    }

    func testRejectsOutOfRangeAndJunk() {
        XCTAssertNil(SSHPort.parse("0"))
        XCTAssertNil(SSHPort.parse("-1"))
        XCTAssertNil(SSHPort.parse("65536"))
        XCTAssertNil(SSHPort.parse("999999"))
        XCTAssertNil(SSHPort.parse(""))
        XCTAssertNil(SSHPort.parse("ssh"))
        XCTAssertNil(SSHPort.parse("22a"))
    }
}
