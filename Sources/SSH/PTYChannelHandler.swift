import Foundation
import NIOCore
import NIOSSH

/// Handles a single SSH "session" child channel running an interactive PTY.
/// On activation it requests a pseudo-terminal, then either a login shell or
/// an exec (e.g. `herdr`), and pipes raw bytes both ways:
///   * inbound  SSHChannelData (server stdout/stderr) -> onOutput (to terminal)
///   * outbound bytes (keyboard/responses)            -> SSHChannelData (write)
/// Window resizes are sent as window-change requests.
final class PTYChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = Never
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let term: String
    private var cols: Int
    private var rows: Int
    /// Called with bytes received from the server. Invoked on the channel's
    /// event loop.
    private let onOutput: (ByteBuffer) -> Void
    /// Called when the shell channel closes / errors.
    private let onClose: (Error?) -> Void
    /// Login shell vs exec (e.g. `herdr`). Mapped by `HerdrSupport.ptyStart`.
    private let start: HerdrSupport.PTYStart

    private var context: ChannelHandlerContext?
    private var closeOnce = ChannelCloseOnce()
    private enum StartupState {
        case idle, awaitingPTY, awaitingProgram, running, closed
    }
    private var startupState = StartupState.idle
    private var exitError: Error?

    private enum StartupError: LocalizedError {
        case ptyRejected
        case programRejected
        case remoteExit(Int)

        var errorDescription: String? {
            switch self {
            case .ptyRejected: return "The SSH server rejected the terminal request."
            case .programRejected: return "The SSH server rejected the shell or Herdr startup request."
            case .remoteExit(let status): return "The remote shell or Herdr exited with status \(status)."
            }
        }
    }

    init(
        term: String,
        cols: Int,
        rows: Int,
        start: HerdrSupport.PTYStart = .loginShell,
        onOutput: @escaping (ByteBuffer) -> Void,
        onClose: @escaping (Error?) -> Void
    ) {
        self.term = term
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        self.start = start
        self.onOutput = onOutput
        self.onClose = onClose
    }

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }

    func channelActive(context: ChannelHandlerContext) {
        // Request a PTY, then a login shell or exec. wantReply so we learn of failures.
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([.ECHO: 1, .ICANON: 1, .ISIG: 1])
        )
        startupState = .awaitingPTY
        sendRequest(ptyRequest, context: context)
        context.fireChannelActive()
    }

    private func startProgram(context: ChannelHandlerContext) {
        startupState = .awaitingProgram
        switch start {
        case .loginShell:
            let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)
            sendRequest(shellRequest, context: context)
        case .exec(let command):
            let execRequest = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
            sendRequest(execRequest, context: context)
        }
    }

    private func sendRequest(_ event: Any, context: ChannelHandlerContext) {
        // This promise only confirms the write. Server acceptance arrives as
        // ChannelSuccessEvent / ChannelFailureEvent on the inbound pipeline.
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenFailure { [weak self] error in
            self?.errorCaught(context: context, error: error)
        }
        context.triggerUserOutboundEvent(event, promise: promise)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            switch startupState {
            case .awaitingPTY: startProgram(context: context)
            case .awaitingProgram: startupState = .running
            default: break
            }
        case is ChannelFailureEvent:
            switch startupState {
            case .awaitingPTY: errorCaught(context: context, error: StartupError.ptyRejected)
            case .awaitingProgram: errorCaught(context: context, error: StartupError.programRejected)
            default: break
            }
        case let status as SSHChannelRequestEvent.ExitStatus:
            if status.exitStatus != 0 {
                exitError = StartupError.remoteExit(status.exitStatus)
            }
            // Keep receiving trailing stderr until the server closes.
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        startupState = .closed
        closeOnce.deliver(exitError, to: onClose)
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buf) = channelData.data else { return }
        // We treat both stdout (.channel) and stderr (.stdErr) as terminal
        // output; a PTY shell normally merges them anyway.
        onOutput(buf)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        startupState = .closed
        closeOnce.deliver(error, to: onClose)
        context.close(promise: nil)
    }

    /// Write outbound bytes to the server as channel data.
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buf = unwrapOutboundIn(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buf))
        context.write(wrapOutboundOut(channelData), promise: promise)
    }

    /// Send a window-change request reflecting a new terminal size. Call on the
    /// channel's event loop.
    func sendWindowChange(cols: Int, rows: Int) {
        guard let context else { return }
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        let event = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: self.cols,
            terminalRowHeight: self.rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        context.triggerUserOutboundEvent(event, promise: nil)
    }
}
