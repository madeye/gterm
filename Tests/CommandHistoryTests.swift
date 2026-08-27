import XCTest

final class CommandHistoryPolicyTests: XCTestCase {
    func testAcceptsOrdinaryCommands() {
        XCTAssertTrue(CommandHistoryPolicy.shouldRecord("ls -la"))
        XCTAssertTrue(CommandHistoryPolicy.shouldRecord("git status"))
        XCTAssertTrue(CommandHistoryPolicy.shouldRecord("cd /tmp"))
    }

    func testRejectsBlankAndShort() {
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord(""))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("  "))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("x"))
    }

    func testRejectsPasswdAndSshpass() {
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("passwd"))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("passwd alice"))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("sshpass -p secret ssh host"))
    }

    func testRejectsSecretAssignments() {
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("export AWS_SECRET_ACCESS_KEY=abc"))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("PASSWORD=hunter2"))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("MY_API_KEY=xyz"))
        XCTAssertFalse(CommandHistoryPolicy.shouldRecord("token=abcd"))
    }

    func testKeepsAssignmentsThatAreNotSecrets() {
        XCTAssertTrue(CommandHistoryPolicy.shouldRecord("FOO=bar make test"))
        XCTAssertTrue(CommandHistoryPolicy.shouldRecord("echo password is not an assignment"))
    }
}

final class CommandHistoryTests: XCTestCase {
    private func makeHistory() -> (CommandHistory, String, UserDefaults) {
        let suite = "gterm.tests.commandHistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CommandHistory(defaults: defaults), suite, defaults)
    }

    func testRecordSkipsSecretsAndStoresCommands() {
        let (history, suite, defaults) = makeHistory()
        defer { defaults.removePersistentDomain(forName: suite) }

        history.record("ls -la")
        history.record("passwd")
        history.record("export TOKEN=shh")
        history.record("git status")

        XCTAssertEqual(history.recent(), ["git status", "ls -la"])
        XCTAssertEqual(history.suggestions(prefix: "git"), ["git status"])
        XCTAssertEqual(history.suggestions(prefix: "pass"), [])
    }

    func testDedupMovesToFront() {
        let (history, suite, defaults) = makeHistory()
        defer { defaults.removePersistentDomain(forName: suite) }

        history.record("ls")
        history.record("cd /tmp")
        history.record("ls")
        XCTAssertEqual(history.recent(), ["ls", "cd /tmp"])
    }
}
