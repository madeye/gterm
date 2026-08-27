import XCTest

final class CommandPromptTests: XCTestCase {
    func testPromptIncludesInstructionAndContext() {
        let ctx = CommandContext(
            instruction: "make a new tmux window called logs",
            history: ["ls -la", "cd /var/log"],
            terminalText: "mlv@host:~/proj$ "
        )
        let req = CommandPromptFactory.request(context: ctx, model: "m")
        XCTAssertEqual(req.model, "m")
        XCTAssertFalse(req.systemPrompt.isEmpty)
        XCTAssertTrue(req.userPrompt.contains("make a new tmux window called logs"))
        XCTAssertTrue(req.userPrompt.contains("cd /var/log"))
        XCTAssertTrue(req.userPrompt.contains("mlv@host"))
    }

    func testPromptBoundsContext() {
        let ctx = CommandContext(
            instruction: "x",
            history: Array(repeating: "cmd --flag", count: 100),
            terminalText: String(repeating: "A", count: 50_000)
        )
        let req = CommandPromptFactory.request(context: ctx, model: "m", maxHistory: 15, maxTerminalChars: 1500)
        XCTAssertLessThan(req.userPrompt.count, 5000)
    }
}

final class CommandSanitizerTests: XCTestCase {
    func testPlainCommand() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "tmux new-window"), "tmux new-window")
    }

    func testStripsFencedBlock() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "```\ntmux new-window\n```"), "tmux new-window")
    }

    func testStripsLanguageFence() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "```bash\ndf -h\n```"), "df -h")
    }

    func testPrefersFenceWhenProseSurroundsIt() {
        let raw = "Sure, here is the command:\n```\ndf -h\n```\nThis shows disk usage."
        XCTAssertEqual(CommandSanitizer.command(fromOutput: raw), "df -h")
    }

    func testStripsInlineBackticks() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "`ls -la`"), "ls -la")
    }

    func testStripsShellPrompt() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "$ df -h"), "df -h")
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "# whoami"), "whoami")
    }

    func testKeepsMultiLineScript() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "```\ncd /tmp\nls\n```"), "cd /tmp\nls")
    }

    func testEmptyForBlank() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "   \n\n  "), "")
    }

    func testStripsCRLF() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "tmux new-window\r\n"), "tmux new-window")
    }

    func testUnwrapsSurroundingQuotes() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "\"tmux new-window\""), "tmux new-window")
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "'df -h'"), "df -h")
    }

    func testQuotedPromptLine() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "\"$ ls -la\""), "ls -la")
    }

    func testKeepsInternalQuotes() {
        XCTAssertEqual(CommandSanitizer.command(fromOutput: "echo \"hello\""), "echo \"hello\"")
    }
}

final class QuickCommandsTests: XCTestCase {
    func testPresetsNonEmpty() {
        XCTAssertFalse(QuickCommands.tmux.isEmpty)
        XCTAssertFalse(QuickCommands.shell.isEmpty)
    }

    func testTmuxNewWindowCommand() {
        let newWindow = QuickCommands.tmux.first { $0.title == "New Window" }
        XCTAssertEqual(newWindow?.command, "tmux new-window")
    }

    func testCloseWindowIsDestructive() {
        let close = QuickCommands.tmux.first { $0.command.contains("kill-window") }
        XCTAssertEqual(close?.isDestructive, true)
    }

    func testAllCommandsNonEmpty() {
        for cmd in QuickCommands.tmux + QuickCommands.shell {
            XCTAssertFalse(cmd.command.isEmpty, "\(cmd.title) has empty command")
            XCTAssertFalse(cmd.systemImage.isEmpty)
        }
    }
}
