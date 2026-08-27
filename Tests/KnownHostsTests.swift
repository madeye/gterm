import XCTest

final class SSHFingerprintTests: XCTestCase {
    /// Public half of the throwaway Ed25519 fixture in SSHKeyParserTests.
    private let ed25519Pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFkeTUyaPwI3q+HM6qK0s/wnVByl92lb9tCI1TFXG1sT gterm-test"

    /// `ssh-keygen -l -E sha256` of that key.
    private let ed25519Fingerprint = "SHA256:U0RqZRgE0EEoGl1k8PBOeB9pKKmxdKJsZp/ymIsMdZU"

    private let ecdsaPub = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOofz14uFVl80GLndS/x5F7R+3HcQBC5SIqH31Ns4OT8Eu/z3Xb6n1XiHrTEwq9c6TuEPD2KqhcrgT1rj37hYxg= gterm-ecdsa"
    private let ecdsaFingerprint = "SHA256:Or70brQY3Wn6ZyBb6B++Z5hKXLGGwwxWnyS68moCQcE"

    func testFingerprintMatchesOpenSSHAndUnpaddedBlob() {
        XCTAssertEqual(SSHFingerprint.sha256(ofOpenSSH: ed25519Pub), ed25519Fingerprint)
        XCTAssertEqual(SSHFingerprint.sha256(ofOpenSSH: ecdsaPub), ecdsaFingerprint)

        // ECDSA blobs include `=` padding. Stripping it used to make
        // `Data(base64Encoded:)` fail and report SHA256:<unknown>.
        let fields = ecdsaPub.split(separator: " ")
        XCTAssertTrue(fields[1].contains("="), "fixture must include padding so the unpadded path is exercised")
        let unpadded = "\(fields[0]) \(String(fields[1]).replacingOccurrences(of: "=", with: "")) \(fields[2])"
        XCTAssertEqual(SSHFingerprint.sha256(ofOpenSSH: unpadded), ecdsaFingerprint)
    }

    func testUnknownWhenBlobMissing() {
        XCTAssertEqual(SSHFingerprint.sha256(ofOpenSSH: "ssh-ed25519"), "SHA256:<unknown>")
    }
}

final class KnownHostsStoreTests: XCTestCase {
    func testRememberAndLookup() {
        let suite = "gterm.tests.knownHosts.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not create suite")
        }
        defaults.removePersistentDomain(forName: suite)
        let store = KnownHostsStore(defaults: defaults)
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFkeTUyaPwI3q+HM6qK0s/wnVByl92lb9tCI1TFXG1sT"
        store.remember(key, for: "example.com:22")
        XCTAssertEqual(store.key(for: "example.com:22"), key)
        XCTAssertNil(store.key(for: "other:22"))

        let reloaded = KnownHostsStore(defaults: defaults)
        XCTAssertEqual(reloaded.key(for: "example.com:22"), key)
        defaults.removePersistentDomain(forName: suite)
    }
}
