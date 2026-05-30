import Foundation
import Crypto
import NIOCore
import NIOSSH

enum HostKeyError: Error, CustomStringConvertible {
    case changed(host: String)
    case rejected(host: String)
    var description: String {
        switch self {
        case .changed(let host):
            return "Host key for \(host) has CHANGED. This could be a man-in-the-middle attack. Refusing to connect."
        case .rejected(let host):
            return "Host key for \(host) was not trusted. Connection cancelled."
        }
    }
}

/// A request to the user to make a trust decision about a host key.
struct HostKeyPrompt {
    enum Kind: Equatable { case firstUse, changed }
    let kind: Kind
    let host: String
    /// SHA256 fingerprint of the key being presented now.
    let fingerprint: String
    /// SHA256 fingerprint of the previously-trusted key (only for `.changed`).
    let previousFingerprint: String?
}

/// Computes the OpenSSH-style SHA256 fingerprint (`SHA256:base64…`) of a public
/// key from its OpenSSH string form (`ssh-ed25519 AAAA… comment`).
enum SSHFingerprint {
    static func sha256(ofOpenSSH openSSH: String) -> String {
        let fields = openSSH.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])) else {
            return "SHA256:<unknown>"
        }
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:" + b64
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

/// Trust-on-first-use host-key verification with an interactive prompt. The
/// first key seen for a host (and any later *changed* key) is surfaced to the
/// user — with its SHA256 fingerprint — for an explicit accept/reject decision
/// before the connection is allowed to proceed. Accepted keys are persisted and
/// not re-prompted.
final class TOFUHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    /// Asks the UI to make a trust decision. Invoked on the main thread; the
    /// completion may be called from any thread (promise completion is
    /// thread-safe in NIO).
    typealias Prompt = (HostKeyPrompt, @escaping (_ accept: Bool) -> Void) -> Void

    private let hostID: String
    private let store: KnownHostsStore
    private let prompt: Prompt?

    init(hostID: String, store: KnownHostsStore = KnownHostsStore(), prompt: Prompt? = nil) {
        self.hostID = hostID
        self.store = store
        self.prompt = prompt
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        let fingerprint = SSHFingerprint.sha256(ofOpenSSH: presented)

        if let known = store.key(for: hostID) {
            if known == presented {
                validationCompletePromise.succeed(())
                return
            }
            let previous = SSHFingerprint.sha256(ofOpenSSH: known)
            ask(
                HostKeyPrompt(kind: .changed, host: hostID, fingerprint: fingerprint, previousFingerprint: previous),
                onReject: .changed(host: hostID),
                presented: presented,
                promise: validationCompletePromise
            )
        } else {
            ask(
                HostKeyPrompt(kind: .firstUse, host: hostID, fingerprint: fingerprint, previousFingerprint: nil),
                onReject: .rejected(host: hostID),
                presented: presented,
                promise: validationCompletePromise
            )
        }
    }

    private func ask(
        _ request: HostKeyPrompt,
        onReject: HostKeyError,
        presented: String,
        promise: EventLoopPromise<Void>
    ) {
        // No UI hook (e.g. headless): preserve safe defaults — trust on first
        // use, refuse a changed key.
        guard let prompt else {
            switch request.kind {
            case .firstUse:
                store.remember(presented, for: hostID)
                promise.succeed(())
            case .changed:
                promise.fail(onReject)
            }
            return
        }

        let store = self.store
        let hostID = self.hostID
        DispatchQueue.main.async {
            prompt(request) { accept in
                if accept {
                    store.remember(presented, for: hostID)
                    promise.succeed(())
                } else {
                    promise.fail(onReject)
                }
            }
        }
    }
}
