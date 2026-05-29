import Foundation
import NIOCore
import NIOSSH

enum HostKeyError: Error, CustomStringConvertible {
    case changed(host: String)
    var description: String {
        switch self {
        case .changed(let host):
            return "Host key for \(host) has CHANGED. This could be a man-in-the-middle attack. Refusing to connect."
        }
    }
}

/// Persists accepted host keys (OpenSSH public-key strings) keyed by host:port,
/// for trust-on-first-use verification.
final class KnownHostsStore {
    private let defaultsKey = "knownHosts"
    private var map: [String: String]

    init() {
        map = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }

    func key(for hostID: String) -> String? { map[hostID] }

    func remember(_ key: String, for hostID: String) {
        map[hostID] = key
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}

/// Trust-on-first-use host-key verification. The first key seen for a host is
/// remembered and accepted; a later mismatch is rejected (the connection fails
/// with HostKeyError.changed). A future enhancement is an interactive prompt on
/// first use / on change.
final class TOFUHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let hostID: String
    private let store: KnownHostsStore

    init(hostID: String, store: KnownHostsStore = KnownHostsStore()) {
        self.hostID = hostID
        self.store = store
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        if let known = store.key(for: hostID) {
            if known == presented {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyError.changed(host: hostID))
            }
        } else {
            store.remember(presented, for: hostID)
            validationCompletePromise.succeed(())
        }
    }
}
