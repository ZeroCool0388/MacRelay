import CryptoKit
import Foundation
import MacRelayCore
import SQLite3
import Testing

@testable import MacRelayWispr

private final class Fixture {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    var db: OpaquePointer?
    init(schema: Bool = true) throws {
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        if schema {
            try execute(
                "CREATE TABLE History (transcriptEntityId TEXT, app TEXT, status TEXT, formattedText TEXT, pastedText TEXT)"
            )
        }
    }
    func execute(_ sql: String) throws { #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK) }
    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite struct WisprTests {
    @Test func onlyNewFinishedScreenSharingBodiesAreRead() throws {
        let fixture = try Fixture()
        try fixture.execute(
            "INSERT INTO History VALUES ('old', 'com.apple.ScreenSharing', 'formatted', 'old private text', NULL)"
        )
        let store = try WisprStore(url: fixture.url)
        #expect(store.isReadOnly)
        #expect(store.baseline == 1)
        #expect(try store.records(after: store.baseline, pending: []).isEmpty)
        try fixture.execute(
            "INSERT INTO History VALUES ('new', 'com.apple.ScreenSharing', 'processing', 'unfinished', NULL)")
        try fixture.execute(
            "INSERT INTO History VALUES ('other', 'com.apple.TextEdit', 'formatted', 'other private text', NULL)"
        )
        let rows = try store.records(after: store.baseline, pending: [])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.text == nil })
        try fixture.execute(
            "UPDATE History SET status='formatted', formattedText='formatted words', pastedText='actual pasted words' WHERE rowid=2"
        )
        let updated = try store.records(after: 3, pending: [2])
        #expect(updated.count == 1)
        #expect(updated[0].text == "actual pasted words")
        #expect(throws: WisprStoreError.queryFailed) { try store.records(after: 3, pending: [1]) }
        // The adapter cannot write, even though its test fixture uses a writable connection.
        #expect(try store.latestRowID() == 3)
    }
    @Test func unsupportedSchemaOversizeAndDatabaseResetFailClosed() throws {
        let absent = try Fixture(schema: false)
        #expect(throws: WisprStoreError.schemaChanged) { try WisprStore(url: absent.url) }
        let fixture = try Fixture()
        let store = try WisprStore(url: fixture.url)
        try fixture.execute(
            "INSERT INTO History VALUES ('huge', 'com.apple.ScreenSharing', 'formatted', CAST(zeroblob(65537) AS TEXT), NULL)"
        )
        #expect(try store.records(after: 0, pending: [])[0].text == nil)
        try fixture.execute("DELETE FROM History")
        #expect(throws: WisprStoreError.replaced) { try store.records(after: 1, pending: []) }
    }
    @Test func cursorRequiresSingleStableNewRecordAndNeverReplays() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 10)
        let record = WisprRecord(
            rowID: 11, entityID: "fresh", app: WisprStore.targetApp, status: "formatted", text: "Hello")
        try cursor.observe([record], eligible: true, now: now)
        #expect(try cursor.ready(now: now) == nil)
        #expect(try cursor.ready(now: now.addingTimeInterval(0.3)) == record)
        cursor.consume(record)
        try cursor.observe([record], eligible: true, now: now.addingTimeInterval(0.4))
        #expect(try cursor.ready(now: now.addingTimeInterval(1)) == nil)
        let duplicated = WisprRecord(
            rowID: 12, entityID: "fresh", app: WisprStore.targetApp, status: "formatted", text: "Hello")
        try cursor.observe([duplicated], eligible: true, now: now)
        #expect(cursor.pendingIDs.isEmpty)
    }
    @Test func recordMustMatchTheStoppedWisprPaste() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 0)
        let record = WisprRecord(
            rowID: 1, entityID: "fresh", app: WisprStore.targetApp, status: "formatted", text: "Fresh words")
        try cursor.observe([record], eligible: true, now: now)
        let freshHash = Data(SHA256.hash(data: Data("Fresh words".utf8)))
        let oldHash = Data(SHA256.hash(data: Data("Old clipboard".utf8)))
        #expect(try cursor.ready(matchingDigest: oldHash, now: now.addingTimeInterval(1)) == nil)
        #expect(try cursor.ready(matchingDigest: freshHash, now: now.addingTimeInterval(1)) == record)
    }

    @Test func cursorDropsOtherAppsExpiredAndInactiveRecords() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 1)
        let other = WisprRecord(
            rowID: 2, entityID: "other", app: "com.apple.TextEdit", status: "formatted", text: nil)
        try cursor.observe([other], eligible: true, now: now)
        #expect(cursor.pendingIDs.isEmpty)
        let fresh = WisprRecord(
            rowID: 3, entityID: "fresh", app: WisprStore.targetApp, status: "formatted", text: "Words")
        try cursor.observe([fresh], eligible: false, now: now)
        #expect(cursor.pendingIDs.isEmpty)
        try cursor.observe([fresh], eligible: true, now: now)
        #expect(cursor.pendingIDs.isEmpty)
        let later = WisprRecord(
            rowID: 4, entityID: "later", app: WisprStore.targetApp, status: "formatted", text: "Later")
        try cursor.observe([later], eligible: true, now: now)
        #expect(try cursor.ready(now: now.addingTimeInterval(60)) == nil)
        cursor.skip(to: 20)
        #expect(cursor.pendingIDs.isEmpty)
        #expect(cursor.watermark == 20)
    }
    @Test func pasteEvidenceSelectsOnlyOneMatchingStableCompletion() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 0)
        let unfinished = WisprRecord(
            rowID: 1, entityID: "unfinished", app: "", status: "processing", text: nil)
        let unrelated = WisprRecord(
            rowID: 2, entityID: "different", app: WisprStore.targetApp,
            status: "formatted", text: "Different words")
        let matched = WisprRecord(
            rowID: 3, entityID: "matched", app: WisprStore.targetApp,
            status: "formatted", text: "Fresh words")
        let digest = Data(SHA256.hash(data: Data("Fresh words".utf8)))
        try cursor.observe([unfinished, unrelated], eligible: true, now: now)
        try cursor.observe([matched], eligible: true, now: now.addingTimeInterval(1))
        #expect(throws: RelayError.insertionRejected) {
            try cursor.ready(now: now.addingTimeInterval(1.3))
        }
        #expect(try cursor.ready(matchingDigest: digest, now: now.addingTimeInterval(1.1)) == nil)
        #expect(try cursor.ready(matchingDigest: digest, now: now.addingTimeInterval(1.3)) == matched)
        #expect(
            cursor.selectionDetails(matchingDigest: digest, now: now.addingTimeInterval(1.3)) == [
                "dictationPendingCount": "3", "dictationFinishedCount": "2", "dictationMatchingCount": "1",
            ])
    }
    @Test func duplicatePasteMatchesAreRefusedEvenWhenOneIsNotStable() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 0)
        let first = WisprRecord(
            rowID: 1, entityID: "first", app: WisprStore.targetApp, status: "formatted", text: "Same words")
        let second = WisprRecord(
            rowID: 2, entityID: "second", app: WisprStore.targetApp, status: "formatted", text: "Same words")
        let digest = Data(SHA256.hash(data: Data("Same words".utf8)))
        try cursor.observe([first], eligible: true, now: now)
        try cursor.observe([second], eligible: true, now: now.addingTimeInterval(1))
        #expect(throws: RelayError.insertionRejected) {
            try cursor.ready(matchingDigest: digest, now: now.addingTimeInterval(1.1))
        }
        #expect(throws: RelayError.insertionRejected) {
            try cursor.ready(matchingDigest: digest, now: now.addingTimeInterval(1.3))
        }
    }
    @Test func consumingMatchRetiresOlderEntriesAndPreservesNewerOnes() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 0)
        let old = WisprRecord(rowID: 1, entityID: "old", app: "", status: "processing", text: nil)
        let first = WisprRecord(
            rowID: 2, entityID: "first", app: WisprStore.targetApp, status: "formatted", text: "First")
        let later = WisprRecord(rowID: 3, entityID: "later", app: "", status: "processing", text: nil)
        try cursor.observe([old, first, later], eligible: true, now: now)
        cursor.consume(first)
        #expect(cursor.pendingIDs == [3])
        let reused = WisprRecord(
            rowID: 4, entityID: "old", app: WisprStore.targetApp, status: "formatted", text: "Old words")
        try cursor.observe([reused], eligible: true, now: now.addingTimeInterval(1))
        #expect(cursor.pendingIDs == [3])
        #expect(!cursor.hasUnguardedCompletion(now: now.addingTimeInterval(6)))
    }
    @Test func twoDatabaseDictationsConfirmWithoutReplayingLateOlderEntries() throws {
        let fixture = try Fixture()
        try fixture.execute(
            "INSERT INTO History VALUES ('baseline', 'com.apple.ScreenSharing', 'formatted', 'Earlier', NULL)"
        )
        let store = try WisprStore(url: fixture.url)
        var cursor = WisprCursor(baseline: store.baseline)
        let now = Date(timeIntervalSince1970: 1000)
        try fixture.execute("INSERT INTO History VALUES ('late', '', 'processing', NULL, NULL)")
        try fixture.execute(
            "INSERT INTO History VALUES ('first', 'com.apple.ScreenSharing', 'formatted', 'First sentence.', NULL)"
        )
        try cursor.observe(
            store.records(after: cursor.watermark, pending: cursor.pendingIDs), eligible: true, now: now)
        let firstHash = Data(SHA256.hash(data: Data("First sentence.".utf8)))
        let first = try #require(
            try cursor.ready(matchingDigest: firstHash, now: now.addingTimeInterval(0.3)))
        cursor.consume(first)
        try fixture.execute(
            "UPDATE History SET app='com.apple.ScreenSharing', status='formatted', formattedText='Late older words' WHERE transcriptEntityId='late'"
        )
        try fixture.execute("INSERT INTO History VALUES ('second', '', 'processing', NULL, NULL)")
        try cursor.observe(
            store.records(after: cursor.watermark, pending: cursor.pendingIDs), eligible: true,
            now: now.addingTimeInterval(1))
        try fixture.execute(
            "UPDATE History SET app='com.apple.ScreenSharing', status='formatted', pastedText='Second sentence.' WHERE transcriptEntityId='second'"
        )
        try cursor.observe(
            store.records(after: cursor.watermark, pending: cursor.pendingIDs), eligible: true,
            now: now.addingTimeInterval(2))
        let secondHash = Data(SHA256.hash(data: Data("Second sentence.".utf8)))
        #expect(try cursor.ready(matchingDigest: secondHash, now: now.addingTimeInterval(2.1)) == nil)
        let second = try #require(
            try cursor.ready(matchingDigest: secondHash, now: now.addingTimeInterval(2.3)))
        #expect(second.rowID > first.rowID)
        cursor.consume(second)
        #expect(cursor.pendingIDs.isEmpty)
        #expect(try cursor.ready(matchingDigest: firstHash, now: now.addingTimeInterval(3)) == nil)
        #expect(try cursor.ready(matchingDigest: secondHash, now: now.addingTimeInterval(3)) == nil)
        #expect(!cursor.hasUnguardedCompletion(now: now.addingTimeInterval(10)))
    }
    @Test func ambiguityAndMissingFinalTextNeverSend() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var cursor = WisprCursor(baseline: 0)
        let missing = WisprRecord(
            rowID: 1, entityID: "first", app: WisprStore.targetApp, status: "formatted", text: nil)
        try cursor.observe([missing], eligible: true, now: now)
        #expect(throws: RelayError.invalidText) { try cursor.ready(now: now.addingTimeInterval(1)) }
        let other = WisprRecord(
            rowID: 2, entityID: "second", app: WisprStore.targetApp, status: "formatted", text: "Second")
        try cursor.observe([other], eligible: true, now: now)
        #expect(throws: RelayError.insertionRejected) { try cursor.ready(now: now.addingTimeInterval(1)) }
        cursor.discardCandidates()
        #expect(cursor.pendingIDs.isEmpty)
    }
}
