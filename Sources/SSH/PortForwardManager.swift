import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import os

/// Live runtime state of a single port forward, surfaced to the UI.
enum PortForwardStatus: Equatable {
    case stopped
    case starting
    case listening
    case failed(String)
}

/// Errors raised by the port-forwarding mechanism.
enum PortForwardError: Error {
    case invalidData
    case badType
    case noOriginator
    case invalidPort
}

/// The NIO mechanism behind SSH local port forwarding (`ssh -L` semantics).
///
/// Owned by `SSHSession`, this reuses the session's authenticated parent channel
/// and its single-thread `EventLoopGroup`. For each enabled forward it binds a
/// `ServerBootstrap` listener on `127.0.0.1:localPort`; every inbound TCP
/// connection opens a `directTCPIP` child channel via the parent's `NIOSSHHandler`
/// and glues the two byte streams with `SSHWrapperHandler` + `GlueHandler`.
///
/// THREADING INVARIANT: this relies on `numberOfThreads == 1`. All mutations of
/// `listeners` happen on `group.next()`, and `glue(inbound:to:)` adds handlers to
/// both the inbound TCP child and the SSH child via `syncOperations` on the
/// assumption that they share one event loop. If the group ever becomes
/// multi-threaded, the cross-channel `syncOperations` would crash.
final class PortForwardManager {
    private let parentChannel: Channel
    private let group: EventLoopGroup
    private let onChange: (UUID, PortForwardStatus) -> Void

    /// Live listener (ServerChannel) per forward id. Mutated only on the loop.
    private var listeners: [UUID: Channel] = [:]

    /// Live inbound TCP child channels per forward id, keyed by ObjectIdentifier.
    /// Tracked so `stop(id)`/`stopAll()` can tear down in-flight tunnels, not just
    /// the listener. Mutated only on the loop. Closing the inbound channel triggers
    /// GlueHandler.channelInactive, which closes the glued SSH child too.
    private var tunnels: [UUID: [ObjectIdentifier: Channel]] = [:]

    /// Forward ids whose bind is currently in flight, so a second `start` (e.g.
    /// autoStart racing a manual toggle) is a no-op instead of a duplicate bind.
    private var starting: Set<UUID> = []

    /// The close future of the most recently stopped listener per id. A re-`start`
    /// waits on it before re-binding: on Darwin SO_REUSEADDR does NOT permit a
    /// second bind while the previous listener socket is still open, so a quick
    /// off->on toggle would otherwise fail with EADDRINUSE.
    private var closing: [UUID: EventLoopFuture<Void>] = [:]

    /// Set by `stopAll()`. An in-flight bind that completes afterwards must
    /// close the new listener instead of putting it back into `listeners`.
    private var tearingDown = false

    private let log = Logger(subsystem: "io.github.madeye.gterm", category: "PortForward")

    init(parentChannel: Channel,
         group: EventLoopGroup,
         onChange: @escaping (UUID, PortForwardStatus) -> Void) {
        self.parentChannel = parentChannel
        self.group = group
        self.onChange = onChange
    }

    /// Dispatch a status change to the main thread for SwiftUI consumption.
    private func emit(_ id: UUID, _ status: PortForwardStatus) {
        DispatchQueue.main.async { [onChange] in onChange(id, status) }
    }

    // MARK: Public API (hops to the loop internally)

    /// Bind a listener for `forward`. Idempotent: no-op if one already exists.
    func start(_ forward: PortForward) {
        group.next().execute { [weak self] in
            guard let self else { return }
            if self.tearingDown { return }
            let id = forward.id
            // Idempotent: already listening, or a bind is already in flight.
            if self.listeners[id] != nil || self.starting.contains(id) { return }
            self.starting.insert(id)
            self.emit(id, .starting)
            // Wait for any in-flight close of a prior listener for this id before
            // re-binding, so a quick off->on toggle doesn't hit EADDRINUSE.
            let prior = self.closing[id] ?? self.group.next().makeSucceededVoidFuture()
            prior.hop(to: self.group.next()).whenComplete { [weak self] _ in
                self?.performBind(forward)
            }
        }
    }

    /// Bind the listener for `forward`. Runs on the loop; assumes `starting`
    /// already contains the id (cleared here when the bind settles).
    private func performBind(_ forward: PortForward) {
        let id = forward.id
        if tearingDown {
            starting.remove(id)
            return
        }
        let bootstrap = ServerBootstrap(group: self.group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            // NOTE: autoRead is left ON (default). GlueHandler provides backpressure
            // by gating those automatic reads in read(context:) — turning autoRead
            // off instead breaks the data pump (reads are never re-issued).
            .childChannelInitializer { [weak self] inbound in
                self?.glue(inbound: inbound, to: forward)
                    ?? inbound.eventLoop.makeSucceededVoidFuture()
            }

        bootstrap.bind(host: "127.0.0.1", port: forward.localPort).whenComplete { [weak self] result in
            guard let self else { return }
            self.starting.remove(id)
            if self.tearingDown {
                if case .success(let serverChannel) = result {
                    serverChannel.close(promise: nil)
                }
                return
            }
            switch result {
            case .success(let serverChannel):
                self.listeners[id] = serverChannel
                self.closing[id] = nil
                self.log.info("Listening on 127.0.0.1:\(forward.localPort, privacy: .public)")
                self.emit(id, .listening)
            case .failure(let error):
                self.log.error("Bind failed on 127.0.0.1:\(forward.localPort, privacy: .public): \(String(describing: error), privacy: .public)")
                self.emit(id, .failed(Self.describe(error, port: forward.localPort)))
            }
        }
    }

    func stop(_ id: UUID) {
        group.next().execute { [weak self] in
            guard let self else { return }
            if let listener = self.listeners[id] {
                // Record the close future so a subsequent start() waits for the
                // socket to be fully released before re-binding the same port.
                self.closing[id] = listener.close()
            }
            self.listeners[id] = nil
            // Tear down every in-flight tunnel for this forward; closing the inbound
            // channel cascades to its glued SSH child via GlueHandler.channelInactive.
            self.tunnels[id]?.values.forEach { $0.close(promise: nil) }
            self.tunnels[id] = nil
            self.emit(id, .stopped)
        }
    }

    /// Close all listeners and every in-flight tunnel child channel. Used on
    /// session teardown; does NOT emit per-forward `.stopped` since the whole
    /// session is going away.
    /// Close every listener and in-flight tunnel; the returned future completes
    /// only once they are all actually closed (sockets released). Callers must
    /// await this before shutting the event-loop group down, otherwise a listener
    /// can linger and the next session's bind fails with EADDRINUSE.
    @discardableResult
    func stopAll() -> EventLoopFuture<Void> {
        let loop = group.next()
        let promise = loop.makePromise(of: Void.self)
        loop.execute { [weak self] in
            guard let self else { return promise.succeed(()) }
            self.tearingDown = true
            var closes: [EventLoopFuture<Void>] = []
            for ch in self.listeners.values { closes.append(ch.close().recover { _ in () }) }
            self.listeners.removeAll()
            for channels in self.tunnels.values {
                for ch in channels.values { closes.append(ch.close().recover { _ in () }) }
            }
            self.tunnels.removeAll()
            self.starting.removeAll()
            self.closing.removeAll()
            EventLoopFuture.andAllComplete(closes, on: loop).cascade(to: promise)
        }
        return promise.futureResult
    }

    // MARK: Glue: inbound TCP child <-> SSH directTCPIP child

    private func glue(inbound: Channel, to forward: PortForward) -> EventLoopFuture<Void> {
        guard (1...65535).contains(forward.remotePort) else {
            inbound.close(promise: nil)
            return inbound.eventLoop.makeFailedFuture(PortForwardError.invalidPort)
        }

        // Re-fetch the NIOSSHHandler off the parent pipeline per inbound connection.
        // Cheap, and avoids holding a strong ref that could outlive the channel.
        return parentChannel.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
            guard let origin = inbound.remoteAddress else {
                return inbound.eventLoop.makeFailedFuture(PortForwardError.noOriginator)
            }

            let promise = inbound.eventLoop.makePromise(of: Channel.self)
            let direct = SSHChannelType.DirectTCPIP(
                targetHost: forward.remoteHost,
                targetPort: forward.remotePort,
                originatorAddress: origin
            )

            sshHandler.createChannel(promise, channelType: .directTCPIP(direct)) { child, type in
                guard case .directTCPIP = type else {
                    return child.eventLoop.makeFailedFuture(PortForwardError.badType)
                }
                return child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
                    // inbound and child share the single event loop (numberOfThreads == 1),
                    // so syncOperations on both is safe here.
                    child.eventLoop.makeCompletedFuture {
                        let (ours, theirs) = GlueHandler.matchedPair()
                        let cs = child.pipeline.syncOperations
                        try cs.addHandler(SSHWrapperHandler())
                        try cs.addHandler(ours)
                        let isync = inbound.pipeline.syncOperations
                        try isync.addHandler(theirs)
                    }
                }
            }

            return promise.futureResult.flatMap { child -> EventLoopFuture<Void> in
                // Track this tunnel so stop(id)/stopAll() can tear it down; drop it
                // from the set once the inbound channel closes.
                let key = ObjectIdentifier(inbound)
                self.tunnels[forward.id, default: [:]][key] = inbound
                inbound.closeFuture.whenComplete { [weak self] _ in
                    self?.tunnels[forward.id]?[key] = nil
                }
                // autoRead stays ON; GlueHandler pulls data continuously and gates
                // for backpressure. No manual read kicks needed.
                return inbound.eventLoop.makeSucceededVoidFuture()
            }.flatMapError { err in
                // On any failure wiring the tunnel, close the inbound TCP so the
                // client sees a refused/closed connection.
                inbound.close(promise: nil)
                return inbound.eventLoop.makeFailedFuture(err)
            }
        }
    }

    // MARK: Helpers

    private static func describe(_ error: Error, port: Int? = nil) -> String {
        let p = port.map(String.init) ?? "?"
        if let io = error as? IOError {
            switch io.errnoCode {
            case EADDRINUSE:
                return "Local port \(p) is already in use — another app (or another forward) may have it. Pick a different local port."
            case EACCES, EPERM:
                return "Local port \(p) isn't allowed on iOS — use a port of 1024 or higher."
            case EADDRNOTAVAIL:
                return "Local address isn't available for port \(p)."
            default:
                return "\(io.localizedDescription) (errno \(io.errnoCode))"
            }
        }
        if let channelError = error as? ChannelError {
            return "\(channelError)"
        }
        return error.localizedDescription
    }
}
