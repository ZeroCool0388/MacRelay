import CryptoKit
import Foundation
import Testing

@testable import MacRelayCore

@Suite
struct ProtocolTests {
    @Test
    func testPairingCodesRoundTripAndRejectInvalidCodes() throws {
        let key = PairingKey()
        #expect(key.code.count == 47)
        #expect(try PairingKey(code: " \(key.code)\n").raw == key.raw)
        for code in [
            "123456", "MR1-" + String(repeating: "a", count: 42),
            "MR1-" + String(repeating: "!", count: 43), "MR2-" + String(key.code.dropFirst(4)),
        ] {
            #expect(throws: (any Error).self) { try PairingKey(code: code) }
        }
    }

    @Test
    func testAuthenticatedHandshakeAndBidirectionalEncryption() throws {
        let key = PairingKey()
        let receiver = ReceiverHandshake(pairing: key)
        let sender = try SenderHandshake(server: receiver.hello, pairing: key)
        let receiverKeys = try receiver.accept(sender.hello)
        let transfer = try Transfer(text: "Hello 🏌️\nSecond line\t\"quoted\"")
        let sealed = try sender.keys.sealTransfer(transfer)
        #expect(!(sealed.range(of: Data(transfer.text!.utf8)) != nil))
        #expect(try receiverKeys.openTransfer(sealed) == transfer)
        let ack = Acknowledgement(id: transfer.id, status: .accepted)
        #expect(try sender.keys.openAcknowledgement(receiverKeys.sealAcknowledgement(ack)) == ack)
        try ack.validate(for: transfer)
    }

    @Test
    func testWrongPairingKeyFailsOnBothSides() throws {
        let key = PairingKey()
        let receiver = ReceiverHandshake(pairing: key)
        #expect(throws: (any Error).self) {
            try SenderHandshake(server: receiver.hello, pairing: PairingKey())
        }
        let otherKey = PairingKey()
        let other = ReceiverHandshake(pairing: otherKey)
        let sender = try SenderHandshake(server: other.hello, pairing: otherKey)
        #expect(throws: (any Error).self) { try receiver.accept(sender.hello) }
    }

    @Test
    func testClientProofIsBoundToReceiverAndEphemeralKeys() throws {
        let key = PairingKey()
        let first = ReceiverHandshake(pairing: key)
        let sender = try SenderHandshake(server: first.hello, pairing: key)
        let second = ReceiverHandshake(pairing: key)
        #expect(throws: (any Error).self) { try second.accept(sender.hello) }
        let altered = ClientHello(
            publicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            proof: sender.hello.proof)
        #expect(throws: (any Error).self) { try first.accept(altered) }
        let short = ClientHello(publicKey: Data(), proof: Data())
        #expect(throws: (any Error).self) { try first.accept(short) }
    }

    @Test
    func testTamperingVersionReflectionAndCrossSessionReplayFail() throws {
        let key = PairingKey()
        let receiver = ReceiverHandshake(pairing: key)
        let sender = try SenderHandshake(server: receiver.hello, pairing: key)
        let keys = try receiver.accept(sender.hello)
        let transfer = try Transfer(text: "Only the paired receiver can read this.")
        var sealed = try sender.keys.sealTransfer(transfer)
        sealed[sealed.count - 1] ^= 1
        #expect(throws: (any Error).self) { try keys.openTransfer(sealed) }
        let original = try sender.keys.sealTransfer(transfer)
        #expect(throws: (any Error).self) { try keys.openAcknowledgement(original) }
        let next = ReceiverHandshake(pairing: key)
        let nextSender = try SenderHandshake(server: next.hello, pairing: key)
        let nextKeys = try next.accept(nextSender.hello)
        #expect(throws: (any Error).self) { try nextKeys.openTransfer(original) }
        let modified = ServerHello(
            version: 2, challenge: receiver.hello.challenge,
            publicKey: receiver.hello.publicKey, proof: receiver.hello.proof)
        #expect(throws: (any Error).self) { try SenderHandshake(server: modified, pairing: key) }
        #expect(try original != sender.keys.sealTransfer(transfer), "AES-GCM uses fresh nonces")
    }

    @Test
    func testAcknowledgementMustMatchMessageAndKind() throws {
        let transfer = try Transfer(text: "text")
        #expect(throws: (any Error).self) {
            try Acknowledgement(id: UUID(), status: .accepted).validate(for: transfer)
        }
        #expect(throws: (any Error).self) {
            try Acknowledgement(id: transfer.id, status: .paired).validate(for: transfer)
        }
        #expect(throws: (any Error).self) {
            try Acknowledgement(id: transfer.id, status: .busy).validate(for: transfer)
        }
        let probe = Transfer()
        try Acknowledgement(id: probe.id, status: .paired).validate(for: probe)
        #expect(throws: (any Error).self) {
            try Acknowledgement(id: probe.id, status: .accepted).validate(for: probe)
        }
    }

    @Test
    func testTextLimitsUseUTF8BytesAndPreserveWhitespace() throws {
        #expect(throws: (any Error).self) { try Transfer(text: "") }
        _ = try Transfer(text: " \n\t")
        _ = try Transfer(text: String(repeating: "a", count: TextPolicy.maximumBytes))
        #expect(throws: (any Error).self) {
            try Transfer(text: String(repeating: "a", count: TextPolicy.maximumBytes + 1))
        }
        #expect(throws: (any Error).self) {
            try Transfer(text: String(repeating: "🏌️", count: TextPolicy.maximumBytes / 2))
        }
    }

    @Test
    func testFramingRejectsInvalidSizesAndHandlesEscapingExpansion() throws {
        for count in [1, 2048, Framing.maximumBytes] {
            #expect(try Framing.length(from: Framing.header(forLength: count)) == count)
        }
        #expect(throws: (any Error).self) { try Framing.header(forLength: 0) }
        #expect(throws: (any Error).self) { try Framing.header(forLength: Framing.maximumBytes + 1) }
        #expect(throws: (any Error).self) { try Framing.length(from: Data([0, 0, 0, 0])) }
        #expect(throws: (any Error).self) { try Framing.length(from: Data([255, 255, 255, 255])) }
        #expect(throws: (any Error).self) { try Framing.length(from: Data([0, 1, 0])) }
        #expect(throws: (any Error).self) {
            try Framing.length(from: Framing.header(forLength: 2049), maximum: 2048)
        }
        let key = PairingKey()
        let receiver = ReceiverHandshake(pairing: key)
        let sender = try SenderHandshake(server: receiver.hello, pairing: key)
        let message = try Transfer(text: String(repeating: "\u{1}", count: TextPolicy.maximumBytes))
        let frame = try sender.keys.sealTransfer(message)
        #expect(frame.count < Framing.maximumBytes)
        #expect(try receiver.accept(sender.hello).openTransfer(frame) == message)
    }
}
