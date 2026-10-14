import Foundation
import Testing

@testable import MacRelayCore

@Suite struct InsertionTests {
    @Test func permitsExpireAndAreConsumedOnce() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var permit = InsertionPermit()
        let first = try permit.arm(now: now)
        #expect(throws: RelayError.busy) { try permit.arm(now: now) }
        let wrong = permit.consume(UUID(), now: now)
        #expect(!wrong)
        let consumed = permit.consume(first, now: now)
        #expect(consumed)
        let replay = permit.consume(first, now: now)
        #expect(!replay)
        let expired = try permit.arm(now: now)
        let tooLate = permit.consume(expired, now: now.addingTimeInterval(15))
        #expect(!tooLate)
        let cleared = try permit.arm(now: now)
        permit.clear()
        let afterClear = permit.consume(cleared, now: now)
        #expect(!afterClear)
    }
    @Test func clearedReservationStaysInvalidAfterRearming() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var permit = InsertionPermit()
        let stale = try permit.arm(now: now)
        // Listener failure clears the reservation before automatic mode can be enabled again.
        permit.clear()
        let afterFailure = permit.consume(stale, now: now)
        #expect(!afterFailure)
        let fresh = try permit.arm(now: now)
        let afterRearming = permit.consume(stale, now: now)
        #expect(!afterRearming)
        let consumed = permit.consume(fresh, now: now)
        #expect(consumed)
    }
    @Test func cancellationAllowsImmediateRearmingAndOnlyClearsMatchingToken() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var permit = InsertionPermit()
        let abandoned = try permit.arm(now: now)
        let wrong = permit.cancel(UUID())
        #expect(!wrong)
        #expect(throws: RelayError.busy) { try permit.arm(now: now) }
        let cancelled = permit.cancel(abandoned)
        #expect(cancelled)
        let fresh = try permit.arm(now: now)
        let delayedCancellation = permit.cancel(abandoned)
        #expect(!delayedCancellation)
        let staleInsertion = permit.consume(abandoned, now: now)
        #expect(!staleInsertion)
        let freshInsertion = permit.consume(fresh, now: now)
        #expect(freshInsertion)
    }
    @Test func utf16SelectionPreservesUnicodeAndRefusesInvalidRanges() throws {
        #expect(
            try InsertionPolicy.replacingSelection(
                in: "A😀B", range: NSRange(location: 1, length: 2), text: "🏌️\n") == "A🏌️\nB")
        #expect(
            try InsertionPolicy.replacingSelection(
                in: "hello", range: NSRange(location: 5, length: 0), text: " world") == "hello world")
        for range in [
            NSRange(location: 2, length: 1), NSRange(location: NSNotFound, length: 0),
            NSRange(location: 100, length: 0),
        ] {
            #expect(throws: (any Error).self) {
                try InsertionPolicy.replacingSelection(in: "A😀B", range: range, text: "x")
            }
        }
    }
    @Test func pasteGuardOnlySuppressesWisprVInScreenSharing() {
        let known: Set<Int32> = [100, 101]
        #expect(
            PasteGuardPolicy.shouldSuppress(
                keyCode: 9, sourcePID: 100, wisprPIDs: known, frontmostApp: "com.apple.ScreenSharing"))
        #expect(
            !PasteGuardPolicy.shouldSuppress(
                keyCode: 9, sourcePID: 0, wisprPIDs: known, frontmostApp: "com.apple.ScreenSharing"))
        #expect(
            !PasteGuardPolicy.shouldSuppress(
                keyCode: 9, sourcePID: 200, wisprPIDs: known, frontmostApp: "com.apple.ScreenSharing"))
        #expect(
            !PasteGuardPolicy.shouldSuppress(
                keyCode: 1, sourcePID: 100, wisprPIDs: known, frontmostApp: "com.apple.ScreenSharing"))
        #expect(
            !PasteGuardPolicy.shouldSuppress(
                keyCode: 9, sourcePID: 100, wisprPIDs: known, frontmostApp: "com.apple.TextEdit"))
    }
    @Test func screenSharingTitleMustMatchPairedReceiver() {
        #expect(PasteGuardPolicy.remoteTitle("Receiver’s Mac", matches: "Receiver's Mac"))
        #expect(PasteGuardPolicy.remoteTitle("receiver-test.local", matches: "receiver-test.local"))
        #expect(PasteGuardPolicy.remoteTitle("Test Mac (High Performance)", matches: "Test Mac"))
        #expect(!PasteGuardPolicy.remoteTitle("Test Mac Extra", matches: "Test Mac"))
        #expect(!PasteGuardPolicy.remoteTitle("Other Mac", matches: "Test Mac"))
        #expect(!PasteGuardPolicy.remoteTitle("Anything", matches: ""))
    }
    @Test func automaticMessagesAreAuthenticatedAndLegacyInboxRefusesThem() throws {
        let key = PairingKey()
        let receiver = ReceiverHandshake(pairing: key)
        let sender = try SenderHandshake(server: receiver.hello, pairing: key)
        let keys = try receiver.accept(sender.hello)
        let arm = Transfer(armID: UUID())
        #expect(try keys.openTransfer(sender.keys.sealTransfer(arm)) == arm)
        let token = UUID()
        let armed = Acknowledgement(id: arm.id, status: .armed, token: token)
        try sender.keys.openAcknowledgement(keys.sealAcknowledgement(armed)).validate(for: arm)
        #expect(throws: RelayError.acknowledgementMismatch) {
            try Acknowledgement(id: arm.id, status: .armed).validate(for: arm)
        }
        let insertion = try Transfer(inserting: "spoken words", token: token)
        #expect(try keys.openTransfer(sender.keys.sealTransfer(insertion)) == insertion)
        let cancellation = Transfer(cancelling: token)
        #expect(try keys.openTransfer(sender.keys.sealTransfer(cancellation)) == cancellation)
        try sender.keys.openAcknowledgement(
            keys.sealAcknowledgement(Acknowledgement(id: cancellation.id, status: .accepted))
        ).validate(for: cancellation)
        try Acknowledgement(id: insertion.id, status: .inserted).validate(for: insertion)
        #expect(throws: RelayError.insertionUnconfirmed) {
            try Acknowledgement(id: insertion.id, status: .unconfirmed).validate(for: insertion)
        }
        #expect(throws: RelayError.insertionRejected) {
            try Acknowledgement(id: insertion.id, status: .rejected).validate(for: insertion)
        }
        var inbox = Inbox()
        #expect(throws: RelayError.invalidMessage) { try inbox.receive(insertion) }
        #expect(throws: RelayError.invalidMessage) { try inbox.receive(cancellation) }
        #expect(inbox.text == nil)
        // A v0.1 acknowledgement still decodes; it advertises no automatic capability.
        let oldJSON = "{\"id\":\"\(UUID())\",\"status\":\"paired\"}"
        #expect(try JSONDecoder().decode(Acknowledgement.self, from: Data(oldJSON.utf8)).capabilities == nil)
    }
}
