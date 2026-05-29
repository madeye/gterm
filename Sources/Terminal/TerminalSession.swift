import Foundation

/// A source/sink of terminal bytes for a surface. The session is the surface
/// view's delegate: it receives user input (didProduceOutput) and pushes
/// remote output back into the surface via `view.receive(_:)`.
protocol TerminalSession: TerminalSurfaceViewDelegate {
    func start()
    func stop()
}

/// A local echo session used to validate the terminal pipeline end-to-end
/// without a network. It echoes typed input back into the terminal (translating
/// CR to CRLF so Enter advances a line), proving:
///   keyboard -> ghostty encoder -> passthru queueWrite -> didProduceOutput
///   -> receive() -> ghostty_surface_pty_data -> render.
/// This is replaced by SSHSession once the transport lands.
final class LoopbackSession: TerminalSession {
    private weak var view: TerminalSurfaceView?

    init(view: TerminalSurfaceView) {
        self.view = view
    }

    func start() {
        let banner =
            "\u{1b}[1;32mgterm\u{1b}[0m local echo — ghostty engine is live.\r\n" +
            "SSH transport is not wired yet; type to see the terminal render.\r\n\r\n$ "
        view?.receive(Data(banner.utf8))
    }

    func stop() {}

    // MARK: TerminalSurfaceViewDelegate

    func terminalSurface(_ view: TerminalSurfaceView, didProduceOutput data: Data) {
        // Echo back, converting bare CR to CRLF so Enter moves to a fresh line.
        var out = Data()
        out.reserveCapacity(data.count + 8)
        for byte in data {
            out.append(byte)
            if byte == 0x0d { out.append(0x0a) }
        }
        // Hop to main; receive() is thread-safe but keeps ordering simple here.
        DispatchQueue.main.async { [weak view] in
            view?.receive(out)
        }
    }

    func terminalSurface(_ view: TerminalSurfaceView, didResizeToCols cols: Int, rows: Int) {
        // Nothing to do for loopback.
    }
}
