import XCTest

final class CompletionPromptTests: XCTestCase {
    func testPromptIncludesAllContext() {
        let ctx = CompletionContext(
            currentLine: "git st",
            history: ["git status", "git stash pop"],
            terminalText: "user@host:~/proj$ "
        )
        let req = CompletionPromptFactory.request(context: ctx, model: "m")

        XCTAssertEqual(req.model, "m")
        XCTAssertFalse(req.systemPrompt.isEmpty)
        XCTAssertTrue(req.userPrompt.contains("git st"), "should include the current line")
        XCTAssertTrue(req.userPrompt.contains("git status"), "should include history")
        XCTAssertTrue(req.userPrompt.contains("user@host"), "should include terminal text")
    }

    func testPromptBoundsContextSize() {
        let ctx = CompletionContext(
            currentLine: "l",
            history: Array(repeating: "some-command --flag", count: 200),
            terminalText: String(repeating: "x", count: 50_000)
        )
        let req = CompletionPromptFactory.request(context: ctx, model: "m", maxHistory: 20, maxTerminalChars: 2000)
        // Bounded by maxTerminalChars + a small amount of history + scaffolding.
        XCTAssertLessThan(req.userPrompt.count, 6000)
    }

    func testPromptUsesMostRecentTerminalTail() {
        // The relevant context is the bottom of the screen (the prompt line), so
        // truncation must keep the tail, not the head.
        let ctx = CompletionContext(
            currentLine: "x",
            history: [],
            terminalText: String(repeating: "A", count: 5000) + "TAILMARKER"
        )
        let req = CompletionPromptFactory.request(context: ctx, model: "m", maxHistory: 20, maxTerminalChars: 100)
        XCTAssertTrue(req.userPrompt.contains("TAILMARKER"))
    }
}

final class CompletionSanitizerTests: XCTestCase {
    func testStripsEchoedPrefix() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "git status", currentLine: "git st"), "atus")
    }

    func testReturnsSuffixWhenNotEchoed() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "atus", currentLine: "git st"), "atus")
    }

    func testStripsCodeFences() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "```\ngit status\n```", currentLine: "git st"), "atus")
    }

    func testStripsInlineBackticks() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "`git status`", currentLine: "git st"), "atus")
    }

    func testFirstLineOnly() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "git status\necho hi", currentLine: "git st"), "atus")
    }

    func testEmptyWhenEqual() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "git st", currentLine: "git st"), "")
    }

    func testEmptyWhenBlank() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "   \n ", currentLine: "git st"), "")
    }

    func testPreservesLeadingSpaceInSuffix() {
        // currentLine "git" + full "git status" -> suffix " status" (with space).
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "git status", currentLine: "git"), " status")
    }

    func testFallbackSuffixKeepsLeadingSpace() {
        // Model returned only the suffix, including the separator space.
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: " status", currentLine: "git"), " status")
    }

    func testStripsCRLFBeforeMatchingPrefix() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "git status\r\n", currentLine: "git st"), "atus")
    }

    func testUnwrapsSurroundingQuotes() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "\"git status\"", currentLine: "git st"), "atus")
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: "'git status'", currentLine: "git st"), "atus")
    }

    func testPaddedFullLineStillYieldsSuffix() {
        XCTAssertEqual(CompletionSanitizer.suffix(fromOutput: " git status", currentLine: "git st"), "atus")
    }
}

final class CompletionPolicyTests: XCTestCase {
    func testRejectsEmptyAndWhitespace() {
        XCTAssertFalse(CompletionPolicy.shouldRequest(currentLine: ""))
        XCTAssertFalse(CompletionPolicy.shouldRequest(currentLine: "   "))
    }

    func testAcceptsRealInput() {
        XCTAssertTrue(CompletionPolicy.shouldRequest(currentLine: "ls"))
        XCTAssertTrue(CompletionPolicy.shouldRequest(currentLine: "g"))
    }

    func testRejectsOverlyLongLine() {
        XCTAssertFalse(CompletionPolicy.shouldRequest(currentLine: String(repeating: "x", count: 600)))
    }
}
