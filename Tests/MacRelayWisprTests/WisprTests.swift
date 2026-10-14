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
