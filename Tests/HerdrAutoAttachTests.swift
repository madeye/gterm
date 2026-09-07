import Foundation
import NIOCore
import NIOEmbedded
import NIOSSH
import XCTest

final class HerdrAutoAttachTests: XCTestCase {
    func testAttachWaitsForPTYAcceptanceThenExecs() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }

        XCTAssertEqual(fixture.requests.events.count, 1)
        let pty = try XCTUnwrap(fixture.requests.events.first as? SSHChannelRequestEvent.PseudoTerminalRequest)
        XCTAssertTrue(pty.wantReply)
        XCTAssertEqual(pty.term, "xterm-256color")
        XCTAssertEqual(pty.terminalCharacterWidth, 80)
        XCTAssertEqual(pty.terminalRowHeight, 24)

        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        XCTAssertEqual(fixture.requests.events.count, 2)
        let exec = try XCTUnwrap(fixture.requests.events.last as? SSHChannelRequestEvent.ExecRequest)
        XCTAssertTrue(exec.wantReply)
        XCTAssertEqual(exec.command, HerdrSupport.execCommand(attachHerdr: true))
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        XCTAssertEqual(fixture.requests.events.count, 2, "success must not start Herdr twice")
        XCTAssertTrue(fixture.closes.isEmpty)
    }

    func testOptionOffRequestsOnlyLoginShell() throws {
        let fixture = try Fixture(attachHerdr: false)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        XCTAssertEqual(fixture.requests.events.count, 2)
        XCTAssertNotNil(fixture.requests.events.last as? SSHChannelRequestEvent.ShellRequest)
        XCTAssertFalse(fixture.requests.events.contains { $0 is SSHChannelRequestEvent.ExecRequest })
    }

    func testPTYRejectionReportsErrorWithoutStartingHerdr() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelFailureEvent())
        XCTAssertEqual(fixture.requests.events.count, 1)
        XCTAssertEqual(fixture.closes.count, 1)
        XCTAssertNotNil(fixture.closes.first ?? nil)
        XCTAssertFalse(fixture.channel.isActive)
    }

    func testExecRejectionReportsErrorOnce() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelFailureEvent())
        XCTAssertEqual(fixture.closes.count, 1)
        XCTAssertNotNil(fixture.closes.first ?? nil)
        XCTAssertFalse(fixture.channel.isActive)
    }

    func testCommandNotFoundExitIsFailureNotCleanDisconnect() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        fixture.channel.pipeline.fireUserInboundEventTriggered(SSHChannelRequestEvent.ExitStatus(exitStatus: 127))
        XCTAssertTrue(fixture.closes.isEmpty, "allow trailing stderr before delivering the exit")
        var stderr = fixture.channel.allocator.buffer(capacity: 32)
        stderr.writeString("herdr: command not found")
        try fixture.channel.writeInbound(SSHChannelData(type: .stdErr, data: .byteBuffer(stderr)))
        XCTAssertEqual(fixture.output, [stderr])
        fixture.channel.pipeline.fireChannelInactive()
        XCTAssertEqual(fixture.closes.count, 1)
        XCTAssertTrue((fixture.closes.first ?? nil)?.localizedDescription.contains("127") == true)
    }

    func testExecWriteFailureReportsErrorOnce() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.requests.failNextRequest = true
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        XCTAssertEqual(fixture.closes.count, 1)
        XCTAssertEqual((fixture.closes.first ?? nil) as? ChannelError, .operationUnsupported)
        XCTAssertFalse(fixture.channel.isActive)
    }

    func testSuccessfulDetachClosesCleanly() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        fixture.channel.pipeline.fireUserInboundEventTriggered(SSHChannelRequestEvent.ExitStatus(exitStatus: 0))
        fixture.channel.pipeline.fireChannelInactive()
        XCTAssertEqual(fixture.closes.count, 1)
        XCTAssertNil(fixture.closes.first ?? nil)
    }

    func testAttachedChannelCarriesTerminalInputAndOutput() throws {
        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        var input = fixture.channel.allocator.buffer(capacity: 2)
        input.writeString("\u{02}c")
        try fixture.channel.writeOutbound(input)
        let sent = try XCTUnwrap(fixture.channel.readOutbound(as: SSHChannelData.self))
        guard case .byteBuffer(let bytes) = sent.data else { return XCTFail("expected terminal bytes") }
        XCTAssertEqual(bytes, input)
        var output = fixture.channel.allocator.buffer(capacity: 32)
        output.writeString("Herdr session ready")
        try fixture.channel.writeInbound(SSHChannelData(type: .channel, data: .byteBuffer(output)))
        XCTAssertEqual(fixture.output, [output])
    }

    #if os(macOS)
    func testAttachFindsHerdrFromLoginProfile() throws {
        try verifyStartup(profile: ".zprofile")
    }

    func testAttachFindsHerdrFromInteractiveShellConfig() throws {
        try verifyStartup(profile: ".zshrc")
    }

    private func verifyStartup(profile: String) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gterm herdr \(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let bin = home.appendingPathComponent("private-bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        // Only shell startup configuration exposes this executable. No user's
        // dotfiles, installed Herdr, credentials, or live sessions are touched.
        try "export PATH=\"$HOME/private-bin:/usr/bin:/bin\"\n".write(
            to: home.appendingPathComponent(profile), atomically: true, encoding: .utf8
        )
        let executable = bin.appendingPathComponent("herdr")
        try "#!/bin/sh\nprintf 'HERDR_ATTACHED\\n'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let baseline = try runRemoteCommand("herdr", home: home)
        XCTAssertEqual(baseline.status, 127, "bare SSH exec must reproduce the missing-PATH failure")

        let fixture = try Fixture(attachHerdr: true)
        defer { _ = try? fixture.channel.finish() }
        fixture.channel.pipeline.fireUserInboundEventTriggered(ChannelSuccessEvent())
        let exec = try XCTUnwrap(fixture.requests.events.last as? SSHChannelRequestEvent.ExecRequest)
        let attached = try runRemoteCommand(exec.command, home: home)
        XCTAssertEqual(attached.status, 0, attached.output)
        XCTAssertTrue(attached.output.contains("HERDR_ATTACHED"), attached.output)
    }

    private func runRemoteCommand(_ command: String, home: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // sshd invokes the user's shell with -c for an exec request.
        process.arguments = ["-c", command]
        process.environment = ["HOME": home.path, "ZDOTDIR": home.path,
                               "SHELL": "/bin/zsh", "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let exited = expectation(description: "remote command exits")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        guard XCTWaiter.wait(for: [exited], timeout: 10) == .completed else {
            process.terminate()
            throw NSError(domain: "HerdrAutoAttachTests.timeout", code: 1)
        }
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
    #endif
}

private final class Fixture {
    let requests = RequestRecorder()
    let channel: EmbeddedChannel
    var closes: [Error?] = []
    var output: [ByteBuffer] = []

    init(attachHerdr: Bool) throws {
        channel = EmbeddedChannel()
        let pty = PTYChannelHandler(
            term: "xterm-256color", cols: 80, rows: 24,
            start: HerdrSupport.ptyStart(attachHerdr: attachHerdr),
            onOutput: { [weak self] in self?.output.append($0) },
            onClose: { [weak self] in self?.closes.append($0) }
        )
        try channel.pipeline.addHandlers(requests, pty).wait()
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 22)).wait()
    }
}

private final class RequestRecorder: ChannelOutboundHandler {
    typealias OutboundIn = SSHChannelData
    var events: [Any] = []
    var failNextRequest = false

    func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        events.append(event)
        if failNextRequest {
            failNextRequest = false
            promise?.fail(ChannelError.operationUnsupported)
        } else {
            promise?.succeed(())
        }
    }
}
