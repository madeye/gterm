import XCTest
import Crypto

final class SSHKeyParserTests: XCTestCase {
    /// Throwaway Ed25519 OpenSSH key generated for this test; never used for auth.
    private let ed25519OpenSSH = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACBZHk1Mmj8CN6vhzOqitLP8J1QcpfdpW/bQiNUxVxtbEwAAAJD5i5Nx+YuT
    cQAAAAtzc2gtZWQyNTUxOQAAACBZHk1Mmj8CN6vhzOqitLP8J1QcpfdpW/bQiNUxVxtbEw
    AAAECIjXJdhOXvBQSWN+Sqwz/BlSf7I/TX+18zUiqBe/s2TlkeTUyaPwI3q+HM6qK0s/wn
    VByl92lb9tCI1TFXG1sTAAAACmd0ZXJtLXRlc3QBAgM=
    -----END OPENSSH PRIVATE KEY-----
    """

    /// Same algorithm, passphrase-protected (cipher is aes256-ctr, not "none").
    private let ed25519Encrypted = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCrIkFwQm
    hXWHjae1Qp+2p2AAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIMyWguNQ0g3osSDR
    XQU2rjiEjlt6AXm90mkkBMvxgMhXAAAAkPTlcygrVo7VOKt7LDwfo9oglQYRTWcslEhn/2
    C7h+6ZU5X3VaD5214RAf+xO/gfsdcdhY4+gTey1nhgB+gtjmpyJC1FC7DNtiJxECr7gIQq
    DINVSBE90wpthbbRU0R4jLmb9FjdzJPQ6tiq6mElm3/tp7wh7FJsDjRPDzcxqim9b2yGEO
    /cFjQcYTsjymgDOg==
    -----END OPENSSH PRIVATE KEY-----
    """

    private let ecdsaP256OpenSSH = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQTqH89eLhVZfNBi53Uv8eRe0ftx3EAQ
    uUiKh99TbODk/BLv8912+p9V4h60xMKvXOk7hDw9iqoXK4E9a49+4WMYAAAAqHCR8Ahwkf
    AIAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOofz14uFVl80GLn
    dS/x5F7R+3HcQBC5SIqH31Ns4OT8Eu/z3Xb6n1XiHrTEwq9c6TuEPD2KqhcrgT1rj37hYx
    gAAAAhAMp+NnVZlln1HtBxI3pQJu3vgCvnNJrJk4F3E6EYKytPAAAAC2d0ZXJtLWVjZHNh
    AQIDBA==
    -----END OPENSSH PRIVATE KEY-----
    """

    func testParsesEd25519OpenSSH() throws {
        let parsed = try SSHKeyParser.parse(ed25519OpenSSH)
        XCTAssertEqual(parsed.type, "Ed25519")
    }

    func testParsesECDSAP256OpenSSH() throws {
        let parsed = try SSHKeyParser.parse(ecdsaP256OpenSSH)
        XCTAssertEqual(parsed.type, "ECDSA P-256")
    }

    func testEncryptedOpenSSHThrows() {
        XCTAssertThrowsError(try SSHKeyParser.parse(ed25519Encrypted)) { error in
            XCTAssertEqual(error as? SSHKeyError, .encrypted)
        }
    }

    func testRSAThrowsUnsupported() {
        let rsa = "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----"
        XCTAssertThrowsError(try SSHKeyParser.parse(rsa)) { error in
            XCTAssertEqual(error as? SSHKeyError, .unsupportedType("ssh-rsa"))
        }
    }

    func testPublicKeyThrows() {
        XCTAssertThrowsError(try SSHKeyParser.parse("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFkeTUyaPwI3q+HM6qK0s/wnVByl92lb9tCI1TFXG1sT comment")) { error in
            XCTAssertEqual(error as? SSHKeyError, .notAPrivateKey)
        }
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try SSHKeyParser.parse("  \n ")) { error in
            XCTAssertEqual(error as? SSHKeyError, .malformed("empty"))
        }
    }

    func testPEMECDSAAllowsSurroundingWhitespace() throws {
        let key = P256.Signing.PrivateKey()
        let pem = "\n\n" + key.pemRepresentation + "\n\n"
        let parsed = try SSHKeyParser.parse(pem)
        XCTAssertEqual(parsed.type, "ECDSA P-256")
    }

    func testParseUsableSkipsBadKeysButKeepsGood() throws {
        let texts = [
            "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----",
            ed25519OpenSSH,
            "",
            "not a key",
        ]
        let result = SSHKeyParser.parseUsable(texts)
        XCTAssertEqual(result.keys.count, 1)
        XCTAssertEqual(result.keys[0].type, "Ed25519")
        XCTAssertNotNil(result.firstError)
    }

    func testParseUsableAllBadReportsFirstError() {
        let result = SSHKeyParser.parseUsable([
            "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----",
            "ssh-ed25519 AAAA public",
        ])
        XCTAssertTrue(result.keys.isEmpty)
        XCTAssertEqual(result.firstError as? SSHKeyError, .unsupportedType("ssh-rsa"))
    }
}

extension SSHKeyError: Equatable {
    static func == (lhs: SSHKeyError, rhs: SSHKeyError) -> Bool {
        switch (lhs, rhs) {
        case (.encrypted, .encrypted), (.notAPrivateKey, .notAPrivateKey):
            return true
        case (.unsupportedType(let a), .unsupportedType(let b)):
            return a == b
        case (.malformed(let a), .malformed(let b)):
            return a == b
        default:
            return false
        }
    }
}
