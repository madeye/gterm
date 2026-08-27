import Foundation
import Crypto
import NIOCore
import NIOSSH

enum SSHKeyError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case encrypted
    case malformed(String)
    case notAPrivateKey

    var description: String {
        switch self {
        case .unsupportedType(let t):
            return "Unsupported key type \"\(t)\". gterm supports Ed25519 and ECDSA (P-256/384/521); RSA is not supported."
        case .encrypted:
            return "This private key is passphrase-encrypted, which isn't supported yet. Remove the passphrase with `ssh-keygen -p -f <key>` and re-import."
        case .malformed(let why):
            return "Couldn't parse the private key: \(why)."
        case .notAPrivateKey:
            return "That doesn't look like a private key (it may be a public key)."
        }
    }
}

/// A parsed private key plus a human-readable type label.
struct ParsedKey {
    let key: NIOSSHPrivateKey
    let type: String
}

/// Parses SSH private keys (modern OpenSSH format and ECDSA PEM) into a
/// `NIOSSHPrivateKey`. Supports Ed25519 and ECDSA P-256/384/521, unencrypted.
enum SSHKeyParser {
    static func parse(_ text: String) throws -> ParsedKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SSHKeyError.malformed("empty") }

        if trimmed.contains("BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSH(trimmed)
        }
        if trimmed.contains("BEGIN RSA PRIVATE KEY") {
            throw SSHKeyError.unsupportedType("ssh-rsa")
        }
        if trimmed.contains("ENCRYPTED") {
            throw SSHKeyError.encrypted
        }
        if trimmed.contains("BEGIN EC PRIVATE KEY") || trimmed.contains("BEGIN PRIVATE KEY") {
            return try parsePEMECDSA(trimmed)
        }
        if trimmed.contains("PUBLIC KEY") || trimmed.hasPrefix("ssh-") || trimmed.hasPrefix("ecdsa-") {
            throw SSHKeyError.notAPrivateKey
        }
        throw SSHKeyError.malformed("unrecognized format")
    }

    /// Parse every non-empty key blob, skipping ones that fail. The first
    /// parse error is returned so the caller can surface it when *nothing*
    /// usable remains (no valid key and no password).
    static func parseUsable(_ texts: [String]) -> (keys: [ParsedKey], firstError: Error?) {
        var keys: [ParsedKey] = []
        var firstError: Error?
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            do {
                keys.append(try parse(trimmed))
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return (keys, firstError)
    }

    private static func friendlyType(_ sshName: String) -> String {
        switch sshName {
        case "ssh-ed25519": return "Ed25519"
        case "ecdsa-sha2-nistp256": return "ECDSA P-256"
        case "ecdsa-sha2-nistp384": return "ECDSA P-384"
        case "ecdsa-sha2-nistp521": return "ECDSA P-521"
        default: return sshName
        }
    }

    // MARK: OpenSSH binary format ("openssh-key-v1")

    private static func parseOpenSSH(_ armored: String) throws -> ParsedKey {
        let body = armored
            .split(whereSeparator: \.isNewline)
            .filter { !$0.contains("BEGIN") && !$0.contains("END") }
            .joined()
        guard let raw = Data(base64Encoded: body) else {
            throw SSHKeyError.malformed("invalid base64")
        }

        var buf = ByteBuffer(bytes: raw)
        guard let magic = buf.readString(length: 15), magic == "openssh-key-v1\u{0}" else {
            throw SSHKeyError.malformed("bad magic")
        }

        let cipher = try readText(&buf)
        let kdf = try readText(&buf)
        _ = try readString(&buf) // kdfoptions
        guard let nKeys = buf.readInteger(endianness: .big, as: UInt32.self), nKeys == 1 else {
            throw SSHKeyError.malformed("expected exactly one key")
        }
        _ = try readString(&buf) // public key blob

        guard cipher == "none", kdf == "none" else {
            throw SSHKeyError.encrypted
        }

        var priv = try readString(&buf) // unencrypted private section
        guard let c1 = priv.readInteger(endianness: .big, as: UInt32.self),
              let c2 = priv.readInteger(endianness: .big, as: UInt32.self),
              c1 == c2 else {
            throw SSHKeyError.malformed("checkint mismatch")
        }

        let keytype = try readText(&priv)
        switch keytype {
        case "ssh-ed25519":
            _ = try readString(&priv) // public key (32 bytes)
            let secret = try readData(&priv) // 64 bytes: seed(32) || pub(32)
            guard secret.count >= 32 else { throw SSHKeyError.malformed("short ed25519 key") }
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Array(secret.prefix(32)))
            return ParsedKey(key: NIOSSHPrivateKey(ed25519Key: key), type: friendlyType(keytype))

        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            _ = try readText(&priv)   // curve identifier ("nistp256" ...)
            _ = try readString(&priv) // public point Q
            let scalar = try readData(&priv)
            return try ecdsaKey(type: keytype, scalar: scalar)

        default:
            throw SSHKeyError.unsupportedType(keytype)
        }
    }

    private static func ecdsaKey(type: String, scalar raw: [UInt8]) throws -> ParsedKey {
        // mpint may carry a leading 0x00 sign byte; strip leading zeros.
        var d = raw
        while d.first == 0 { d.removeFirst() }

        let size: Int
        switch type {
        case "ecdsa-sha2-nistp256": size = 32
        case "ecdsa-sha2-nistp384": size = 48
        case "ecdsa-sha2-nistp521": size = 66
        default: throw SSHKeyError.unsupportedType(type)
        }
        guard d.count <= size else { throw SSHKeyError.malformed("oversized scalar") }
        let padded = [UInt8](repeating: 0, count: size - d.count) + d

        switch type {
        case "ecdsa-sha2-nistp256":
            return ParsedKey(key: NIOSSHPrivateKey(p256Key: try .init(rawRepresentation: padded)), type: friendlyType(type))
        case "ecdsa-sha2-nistp384":
            return ParsedKey(key: NIOSSHPrivateKey(p384Key: try .init(rawRepresentation: padded)), type: friendlyType(type))
        default:
            return ParsedKey(key: NIOSSHPrivateKey(p521Key: try .init(rawRepresentation: padded)), type: friendlyType(type))
        }
    }

    // MARK: PEM (ECDSA only; Ed25519 PEM isn't supported by swift-crypto)

    private static func parsePEMECDSA(_ pem: String) throws -> ParsedKey {
        if let k = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return ParsedKey(key: NIOSSHPrivateKey(p256Key: k), type: "ECDSA P-256")
        }
        if let k = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
            return ParsedKey(key: NIOSSHPrivateKey(p384Key: k), type: "ECDSA P-384")
        }
        if let k = try? P521.Signing.PrivateKey(pemRepresentation: pem) {
            return ParsedKey(key: NIOSSHPrivateKey(p521Key: k), type: "ECDSA P-521")
        }
        throw SSHKeyError.malformed("unsupported PEM key (only ECDSA P-256/384/521 PEM is supported)")
    }

    // MARK: SSH wire readers

    private static func readString(_ buf: inout ByteBuffer) throws -> ByteBuffer {
        guard let len = buf.readInteger(endianness: .big, as: UInt32.self),
              let slice = buf.readSlice(length: Int(len)) else {
            throw SSHKeyError.malformed("truncated")
        }
        return slice
    }

    private static func readText(_ buf: inout ByteBuffer) throws -> String {
        var slice = try readString(&buf)
        return slice.readString(length: slice.readableBytes) ?? ""
    }

    private static func readData(_ buf: inout ByteBuffer) throws -> [UInt8] {
        var slice = try readString(&buf)
        return slice.readBytes(length: slice.readableBytes) ?? []
    }
}
