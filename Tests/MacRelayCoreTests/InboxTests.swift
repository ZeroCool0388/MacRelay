import Foundation
import Testing

@testable import MacRelayCore

@Suite
struct InboxTests {
    @Test
    func testOnePendingItemNeverGetsReplaced() throws {
        var inbox = Inbox()
        let now = Date(timeIntervalSince1970: 100)
        let first = try Transfer(text: "first")
        #expect(try inbox.receive(first, now: now).status == .accepted)
        #expect(try inbox.receive(Transfer(text: "second"), now: now).status == .busy)
        #expect(inbox.text == "first")
        #expect(inbox.expiresAt == now.addingTimeInterval(120))
    }
    @Test
    func testExpiryAndExplicitDiscardRemoveWaitingText() throws {
        var inbox = Inbox()
        let now = Date(timeIntervalSince1970: 100)
        _ = try inbox.receive(Transfer(text: "temporary"), now: now)
        inbox.expire(now: now.addingTimeInterval(119))
        #expect(inbox.text != nil)
        inbox.expire(now: now.addingTimeInterval(120))
        #expect(inbox.text == nil)
        #expect(inbox.expiresAt == nil)
        _ = try inbox.receive(Transfer(text: "new"), now: now.addingTimeInterval(121))
        inbox.clear()
        #expect(inbox.text == nil)
        #expect(inbox.expiresAt == nil)
    }
    @Test
    func testProbeDoesNotTouchPendingTextOrExtendLifetime() throws {
        var inbox = Inbox()
        let now = Date(timeIntervalSince1970: 100)
        _ = try inbox.receive(Transfer(text: "pending"), now: now)
        #expect(try inbox.receive(Transfer(), now: now.addingTimeInterval(10)).status == .paired)
        #expect(inbox.text == "pending")
        #expect(inbox.expiresAt == now.addingTimeInterval(120))
    }
    @Test
    func testExpiredSlotAcceptsNewText() throws {
        var inbox = Inbox()
        let now = Date(timeIntervalSince1970: 100)
        _ = try inbox.receive(Transfer(text: "old"), now: now)
        #expect(
            try inbox.receive(Transfer(text: "new"), now: now.addingTimeInterval(120)).status == .accepted)
        #expect(inbox.text == "new")
    }
}
