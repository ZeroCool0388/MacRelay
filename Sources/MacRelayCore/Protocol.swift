import CryptoKit
import Foundation

public enum RelayError: Error, LocalizedError, Equatable {
    case invalidPairingCode, authenticationFailed, invalidMessage, invalidFrame, invalidText
    case disconnected, timedOut, busy, acknowledgementMismatch
    case insertionRejected, insertionUnconfirmed

    public var errorDescription: String? {
        switch self {
        case .invalidPairingCode: return "Enter the complete MR1 pairing code from the receiver."
        case .authenticationFailed:
            return "Pairing could not be authenticated. Check the receiver and pairing code."
        case .invalidMessage: return "The other Mac sent an unsupported or invalid message."
        case .invalidFrame: return "The connection sent an invalid or oversized frame."
        case .invalidText: return "Clipboard text must be non-empty and at most 64 KiB in UTF-8."
        case .disconnected:
            return "Connection closed. Delivery is unconfirmed; check the receiver before resending."
        case .timedOut:
            return "Connection timed out. Delivery is unconfirmed; check the receiver before resending."
        case .busy: return "The receiver already has text waiting. Copy or discard it before sending again."
        case .acknowledgementMismatch:
            return "Delivery acknowledgement could not be verified. Check the receiver."
        case .insertionRejected:
            return "Insertion was stopped. Check the receiver's focused field and automatic mode."
        case .insertionUnconfirmed:
            return
                "Insertion was attempted but could not be confirmed. Check the field before dictating again."
        }
    }
}

public struct PairingKey {
    public let raw: Data
    public init() {
        raw = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
    public init(code: String) throws {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix("MR1-"), code.count == 47 else { throw RelayError.invalidPairingCode }
        let encoded = String(code.dropFirst(4))
        let base64 =
            encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "="
        guard let decoded = Data(base64Encoded: base64), decoded.count == 32 else {
            throw RelayError.invalidPairingCode
        }
        raw = decoded
        guard self.code == code else { throw RelayError.invalidPairingCode }
    }
    public var code: String {
        "MR1-"
            + raw.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    var symmetric: SymmetricKey { SymmetricKey(data: raw) }
}

public struct ServerHello: Codable {
    public let version: Int
    public let challenge: Data
    public let publicKey: Data
    public let proof: Data
}
public struct ClientHello: Codable {
    public let publicKey: Data
    public let proof: Data
}

/// One ephemeral handshake per TCP connection. Pairing keys never go on the wire.
public struct ReceiverHandshake {
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private let pairing: PairingKey
    public let hello: ServerHello

    public init(pairing: PairingKey) {
        self.pairing = pairing
        let challenge = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let publicKey = privateKey.publicKey.rawRepresentation
        let transcript = serverTranscript(challenge: challenge, publicKey: publicKey)
        hello = ServerHello(
            version: 1, challenge: challenge, publicKey: publicKey,
            proof: authenticate(transcript, pairing: pairing))
    }
    public func accept(_ client: ClientHello) throws -> SessionKeys {
        guard client.publicKey.count == 32, client.proof.count == 32 else {
            throw RelayError.authenticationFailed
        }
        let transcript = fullTranscript(server: hello, clientPublicKey: client.publicKey)
        guard
            HMAC<SHA256>.isValidAuthenticationCode(
                client.proof, authenticating: transcript,
                using: pairing.symmetric)
        else {
            throw RelayError.authenticationFailed
        }
        return try derive(privateKey: privateKey, remote: client.publicKey, transcript: transcript)
    }
}

public struct SenderHandshake {
    public let hello: ClientHello
    public let keys: SessionKeys

    public init(server: ServerHello, pairing: PairingKey) throws {
        guard server.version == 1, server.challenge.count == 32, server.publicKey.count == 32,
            server.proof.count == 32
        else { throw RelayError.authenticationFailed }
        guard
            HMAC<SHA256>.isValidAuthenticationCode(
                server.proof,
                authenticating: serverTranscript(challenge: server.challenge, publicKey: server.publicKey),
                using: pairing.symmetric)
        else { throw RelayError.authenticationFailed }
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let transcript = fullTranscript(server: server, clientPublicKey: publicKey)
        hello = ClientHello(publicKey: publicKey, proof: authenticate(transcript, pairing: pairing))
        keys = try derive(privateKey: privateKey, remote: server.publicKey, transcript: transcript)
    }
}

private func serverTranscript(challenge: Data, publicKey: Data) -> Data {
    Data("MacRelay/v1/server\0".utf8) + challenge + publicKey
}
private func fullTranscript(server: ServerHello, clientPublicKey: Data) -> Data {
    Data("MacRelay/v1/client\0".utf8) + server.challenge + server.publicKey + clientPublicKey
}
private func authenticate(_ data: Data, pairing: PairingKey) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: pairing.symmetric))
}
private func derive(
    privateKey: Curve25519.KeyAgreement.PrivateKey, remote: Data,
    transcript: Data
) throws -> SessionKeys {
    do {
        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remote)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: remoteKey)
        let salt = Data(SHA256.hash(data: transcript))
        let outbound = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt,
            sharedInfo: Data("MacRelay/v1/transfer".utf8), outputByteCount: 32)
        let inbound = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt,
            sharedInfo: Data("MacRelay/v1/ack".utf8), outputByteCount: 32)
        return SessionKeys(transfer: outbound, acknowledgement: inbound, context: salt)
    } catch { throw RelayError.authenticationFailed }
}

public struct Transfer: Codable, Equatable {
    public enum Kind: String, Codable { case text, probe, arm, insert, cancel }
    public let id: UUID
    public let kind: Kind
    public let text: String?
    public let token: UUID?
    public init(text: String) throws {
        try TextPolicy.validate(text)
        id = UUID()
        kind = .text
        self.text = text
        token = nil
    }
    public init(probeID: UUID = UUID()) {
        id = probeID
        kind = .probe
        text = nil
        token = nil
    }
    public init(armID: UUID) {
        id = armID
        kind = .arm
        text = nil
        token = nil
    }
    public init(inserting text: String, token: UUID) throws {
        try TextPolicy.validate(text)
        id = UUID()
        kind = .insert
        self.text = text
        self.token = token
    }
    public init(cancelling token: UUID) {
        id = UUID()
        kind = .cancel
        text = nil
        self.token = token
    }
    public func validate() throws {
        switch kind {
        case .text:
            guard let text, token == nil else { throw RelayError.invalidMessage }
            try TextPolicy.validate(text)
        case .probe, .arm:
            guard text == nil, token == nil else { throw RelayError.invalidMessage }
        case .insert:
            guard let text, token != nil else { throw RelayError.invalidMessage }
            try TextPolicy.validate(text)
        case .cancel:
            guard text == nil, token != nil else { throw RelayError.invalidMessage }
        }
    }
}
public struct Acknowledgement: Codable, Equatable {
    public enum Status: String, Codable {
        case accepted, busy, paired, armed, inserted, rejected, unconfirmed
    }
    public let id: UUID
    public let status: Status
    public let token: UUID?
    public let capabilities: [String]?
    public let receiverNames: [String]?
    public static let automaticInsertion = "wispr-insertion-v1"
    public init(
        id: UUID, status: Status, token: UUID? = nil, capabilities: [String]? = nil,
        receiverNames: [String]? = nil
    ) {
        self.id = id
        self.status = status
        self.token = token
        self.capabilities = capabilities
        self.receiverNames = receiverNames
    }
    public func validate(for transfer: Transfer) throws {
        guard id == transfer.id else { throw RelayError.acknowledgementMismatch }
        switch (transfer.kind, status) {
        case (.probe, .paired), (.text, .accepted), (.insert, .inserted), (.cancel, .accepted):
            guard token == nil else { throw RelayError.acknowledgementMismatch }
            return
        case (.arm, .armed):
            guard token != nil else { throw RelayError.acknowledgementMismatch }
            return
        case (.arm, .rejected), (.insert, .rejected): throw RelayError.insertionRejected
        case (.insert, .unconfirmed): throw RelayError.insertionUnconfirmed
        case (.text, .busy): throw RelayError.busy
        default: throw RelayError.acknowledgementMismatch
        }
    }
}

public struct SessionKeys {
    private let transfer: SymmetricKey
    private let acknowledgement: SymmetricKey
    private let context: Data
    fileprivate init(transfer: SymmetricKey, acknowledgement: SymmetricKey, context: Data) {
        self.transfer = transfer
        self.acknowledgement = acknowledgement
        self.context = context
    }
    public func sealTransfer(_ value: Transfer) throws -> Data {
        try value.validate()
        return try seal(value, key: transfer, role: "transfer")
    }
    public func openTransfer(_ data: Data) throws -> Transfer {
        let value: Transfer = try open(data, key: transfer, role: "transfer")
        try value.validate()
        return value
    }
    public func sealAcknowledgement(_ value: Acknowledgement) throws -> Data {
        try seal(value, key: acknowledgement, role: "ack")
    }
    public func openAcknowledgement(_ data: Data) throws -> Acknowledgement {
        try open(data, key: acknowledgement, role: "ack")
    }
    private func seal<T: Encodable>(_ value: T, key: SymmetricKey, role: String) throws -> Data {
        let plaintext = try JSONEncoder().encode(value)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: context + Data(role.utf8))
        guard let combined = box.combined else { throw RelayError.invalidMessage }
        return combined
    }
    private func open<T: Decodable>(_ data: Data, key: SymmetricKey, role: String) throws -> T {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: context + Data(role.utf8))
            return try JSONDecoder().decode(T.self, from: plaintext)
        } catch { throw RelayError.authenticationFailed }
    }
}

public enum TextPolicy {
    public static let maximumBytes = 64 * 1024
    public static func validate(_ text: String) throws {
        guard !text.isEmpty, text.utf8.count <= maximumBytes else { throw RelayError.invalidText }
    }
}

public enum Framing {
    // JSON escaping can expand a control character to six bytes before encryption.
    public static let maximumBytes = 512 * 1024
    public static func header(forLength count: Int) throws -> Data {
        guard count > 0, count <= maximumBytes else { throw RelayError.invalidFrame }
        let size = UInt32(count)
        return Data([
            UInt8((size >> 24) & 255), UInt8((size >> 16) & 255),
            UInt8((size >> 8) & 255), UInt8(size & 255),
        ])
    }
    public static func length(from header: Data, maximum: Int = maximumBytes) throws -> Int {
        guard header.count == 4 else { throw RelayError.invalidFrame }
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= maximum, size <= maximumBytes else { throw RelayError.invalidFrame }
        return Int(size)
    }
}
