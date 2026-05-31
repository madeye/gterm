import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Connection parameters for an SSH session.
struct SSHConnection: Identifiable {
    var id = UUID()
    var host: String
    var port: Int = 22
    var username: String
    var password: String = ""
    /// PEM/OpenSSH private key texts to try for public-key auth, in order.
    var privateKeys: [String] = []
    var term: String = "xterm-256color"
    /// The owning `SavedConnection.id`, if this runtime connection came from a
    /// saved host. Not persisted; rides along so the UI can resolve persisted
    /// port forwards for this connection.
    var savedID: UUID? = nil
}

/// High-level lifecycle of an SSH session, surfaced to the UI.
enum SSHSessionState: Equatable {
    case idle
    case connecting
    case authenticating
    case connected
    case failed(String)
    case closed
}

/// Drives an interactive SSH shell over a PTY using swift-nio-ssh and feeds it
/// into a TerminalSurfaceView. It is the surface's delegate: user input flows
/// out to the channel, server output flows into the surface, and resizes are
/// forwarded as window-change requests.
final class SSHSession: TerminalSession {
    private let connection: SSHConnection
    private weak var view: TerminalSurfaceView?
    private let onStateChange: (SSHSessionState) -> Void
    private let onHostKeyPrompt: TOFUHostKeyDelegate.Prompt?

    private let group: EventLoopGroup
    private var channel: Channel?
    private var childChannel: Channel?
    private var ptyHandler: PTYChannelHandler?

    private var forwardManager: PortForwardManager?
    private let forwards: [PortForward]
    private let onForwardChange: ((UUID, PortForwardStatus) -> Void)?

    init(
        connection: SSHConnection,
        view: TerminalSurfaceView,
        forwards: [PortForward] = [],
        onHostKeyPrompt: TOFUHostKeyDelegate.Prompt? = nil,
        onForwardChange: ((UUID, PortForwardStatus) -> Void)? = nil,
        onStateChange: @escaping (SSHSessionState) -> Void
    ) {
        self.connection = connection
        self.view = view
        self.forwards = forwards
        self.onHostKeyPrompt = onHostKeyPrompt
        self.onForwardChange = onForwardChange
        self.onStateChange = onStateChange
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: TerminalSession

    func start() {
        notify(.connecting)

        // Build authentication offers in preference order: private key (if
        // provided), then password (if provided).
        var offers: [NIOSSHUserAuthenticationOffer.Offer] = []
        for keyText in connection.privateKeys where !keyText.isEmpty {
            do {
                let parsed = try SSHKeyParser.parse(keyText)
                offers.append(.privateKey(.init(privateKey: parsed.key)))
            } catch {
                notify(.failed(Self.describe(error)))
                return
            }
        }
        if !connection.password.isEmpty {
            offers.append(.password(.init(password: connection.password)))
        }
        guard !offers.isEmpty else {
            notify(.failed("No authentication method provided."))
            return
        }

        let authDelegate = OrderedAuthDelegate(username: connection.username, offers: offers)
        let hostKeyDelegate = TOFUHostKeyDelegate(
            hostID: "\(connection.host):\(connection.port)",
            prompt: onHostKeyPrompt
        )

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(.init(
                        userAuthDelegate: authDelegate,
                        serverAuthDelegate: hostKeyDelegate
                    )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )
                return channel.pipeline.addHandler(sshHandler)
            }

        notify(.authenticating)
        bootstrap.connect(host: connection.host, port: connection.port).whenComplete { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.notify(.failed(Self.describe(error)))
            case .success(let channel):
                self.channel = channel
                self.openShellChannel(on: channel)
            }
        }
    }

    func stop() {
        let group = self.group
        // Close port-forward listeners + tunnels FIRST and wait for them to be
        // fully released, THEN close the channels and shut the group down. Shutting
        // the group down concurrently can leave a listener lingering bound, so the
        // next session's bind fails with EADDRINUSE.
        let cleanup = forwardManager?.stopAll() ?? group.next().makeSucceededVoidFuture()
        forwardManager = nil
        let child = childChannel
        let parent = channel
        childChannel = nil
        channel = nil
        ptyHandler = nil
        cleanup.whenComplete { _ in
            child?.close(promise: nil)
            parent?.close(promise: nil)
            group.shutdownGracefully { _ in }
        }
    }

    // MARK: Open the PTY shell child channel

    private func openShellChannel(on channel: Channel) {
        let (cols, rows) = view?.gridSize ?? (80, 24)

        channel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.notify(.failed(Self.describe(error)))

            case .success(let sshHandler):
                let promise = channel.eventLoop.makePromise(of: Channel.self)
                sshHandler.createChannel(promise, channelType: .session) { childChannel, _ in
                    let pty = PTYChannelHandler(
                        term: self.connection.term,
                        cols: cols,
                        rows: rows,
                        onOutput: { [weak self] buf in
                            self?.deliverOutput(buf)
                        },
                        onClose: { [weak self] error in
                            self?.handleChannelClose(error)
                        }
                    )
                    self.ptyHandler = pty
                    return childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                        .flatMap {
                            childChannel.pipeline.addHandler(pty)
                        }
                }

                promise.futureResult.whenComplete { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .failure(let error):
                        self.notify(.failed(Self.describe(error)))
                    case .success(let childChannel):
                        self.childChannel = childChannel
                        // The parent `channel` is the authenticated connection;
                        // the forward manager reuses it and the shared group.
                        let mgr = PortForwardManager(
                            parentChannel: channel,
                            group: self.group,
                            onChange: { [weak self] id, st in self?.onForwardChange?(id, st) }
                        )
                        self.forwardManager = mgr
                        for f in self.forwards where f.autoStart { mgr.start(f) }
                        self.notify(.connected)
                    }
                }
            }
        }
    }

    // MARK: Port forwarding

    /// Start the listener for the forward with `id` (looked up in the stored
    /// configs). The manager hops to the event loop internally.
    func startForward(_ id: UUID) {
        guard let f = forwards.first(where: { $0.id == id }) else { return }
        forwardManager?.start(f)
    }

    func stopForward(_ id: UUID) {
        forwardManager?.stop(id)
    }

    private func deliverOutput(_ buf: ByteBuffer) {
        guard let view else { return }
        var buf = buf
        if let bytes = buf.readBytes(length: buf.readableBytes) {
            view.receive(Data(bytes))
        }
    }

    private func handleChannelClose(_ error: Error?) {
        if let error {
            notify(.failed(Self.describe(error)))
        } else {
            notify(.closed)
        }
    }

    // MARK: TerminalSurfaceViewDelegate

    func terminalSurface(_ view: TerminalSurfaceView, didProduceOutput data: Data) {
        guard let childChannel else { return }
        var buf = childChannel.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        childChannel.eventLoop.execute {
            childChannel.writeAndFlush(buf, promise: nil)
        }
    }

    func terminalSurface(_ view: TerminalSurfaceView, didResizeToCols cols: Int, rows: Int) {
        guard let childChannel, let ptyHandler else { return }
        childChannel.eventLoop.execute {
            ptyHandler.sendWindowChange(cols: cols, rows: rows)
        }
    }

    // MARK: Helpers

    private func notify(_ state: SSHSessionState) {
        DispatchQueue.main.async { [onStateChange] in onStateChange(state) }
    }

    private static func describe(_ error: Error) -> String {
        if let keyError = error as? SSHKeyError {
            return keyError.description
        }
        if let hostKey = error as? HostKeyError {
            return hostKey.description
        }
        if let sshError = error as? NIOSSHError {
            return "\(sshError)"
        }
        return error.localizedDescription
    }
}

// MARK: - Auth delegate

/// Offers a fixed, ordered list of authentication methods (e.g. private key
/// then password), skipping any the server doesn't advertise.
private final class OrderedAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let offers: [NIOSSHUserAuthenticationOffer.Offer]
    private var index = 0

    init(username: String, offers: [NIOSSHUserAuthenticationOffer.Offer]) {
        self.username = username
        self.offers = offers
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        while index < offers.count {
            let offer = offers[index]
            index += 1
            if isAdvertised(offer, in: availableMethods) {
                nextChallengePromise.succeed(
                    NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: offer)
                )
                return
            }
        }
        nextChallengePromise.succeed(nil)
    }

    private func isAdvertised(
        _ offer: NIOSSHUserAuthenticationOffer.Offer,
        in methods: NIOSSHAvailableUserAuthenticationMethods
    ) -> Bool {
        switch offer {
        case .privateKey: return methods.contains(.publicKey)
        case .password: return methods.contains(.password)
        default: return true
        }
    }
}
