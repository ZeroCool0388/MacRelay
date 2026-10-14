import Foundation
import MacRelayCore
import SQLite3

public enum WisprStoreError: Error, LocalizedError {
    case unavailable, schemaChanged, queryFailed, replaced
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Wispr's local dictation data is unavailable. Automatic mode is off."
        case .schemaChanged: return "Wispr's data layout is unsupported. Automatic mode is off."
        case .queryFailed: return "Wispr's local data could not be checked. Automatic mode is off."
        case .replaced:
            return "Wispr's data was reset or replaced. Enable automatic mode again to start fresh."
        }
    }
}

public struct WisprRecord: Equatable {
    public let rowID: Int64
    public let entityID: String
    public let app: String
    public let status: String
    public let text: String?
    public init(rowID: Int64, entityID: String, app: String, status: String, text: String?) {
        self.rowID = rowID
        self.entityID = entityID
        self.app = app
        self.status = status
        self.text = text
    }
}

/// Undocumented Wispr adapter. Read-only, exact columns, only rows newer than enable-time.
/// No audio, screenshots, clipboard, settings or account tables are accessed.
public final class WisprStore {
    public static let targetApp = "com.apple.ScreenSharing"
    private var db: OpaquePointer?
    private let url: URL
    private let fileID: UInt64
    public private(set) var baseline: Int64 = 0
    var isReadOnly: Bool { db.map { sqlite3_db_readonly($0, "main") == 1 } ?? false }

    public init(url: URL) throws {
        self.url = url
        guard let id = Self.identity(url) else { throw WisprStoreError.unavailable }
        fileID = id
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
            let db
        else {
            if let db { sqlite3_close(db) }
            self.db = nil
            throw WisprStoreError.unavailable
        }
        sqlite3_busy_timeout(db, 100)
        do {
            let statement = try prepare("SELECT name FROM pragma_table_info('History')")
            defer { sqlite3_finalize(statement) }
            var fields = Set<String>()
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                fields.insert(Self.string(statement, 0))
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE,
                Set(["transcriptEntityId", "status", "app", "pastedText", "formattedText"]).isSubset(
                    of: fields)
            else { throw WisprStoreError.schemaChanged }
            baseline = try Self.tip(db)
        } catch {
            sqlite3_close(db)
            self.db = nil
            throw error
        }
    }
    deinit { if let db { sqlite3_close(db) } }
    public func latestRowID() throws -> Int64 {
        guard Self.identity(url) == fileID, let db else { throw WisprStoreError.replaced }
        return try Self.tip(db)
    }
    public func records(after watermark: Int64, pending: [Int64]) throws -> [WisprRecord] {
        guard pending.count <= 8, pending.allSatisfy({ $0 > baseline }), watermark >= baseline else {
            throw WisprStoreError.queryFailed
        }
        guard try latestRowID() >= watermark else { throw WisprStoreError.replaced }
        let placeholders = pending.map { _ in "?" }.joined(separator: ",")
        let wherePending = pending.isEmpty ? "" : " OR rowid IN (\(placeholders))"
        // Never materialize unfinished text or bodies intended for other apps.
        let body = "COALESCE(NULLIF(pastedText,''), formattedText,'')"
        let sql = """
            SELECT rowid, substr(transcriptEntityId,1,128), substr(app,1,128), substr(status,1,32),
                CASE WHEN app=? AND status='formatted'
                    AND length(CAST(\(body) AS BLOB)) BETWEEN 1 AND \(TextPolicy.maximumBytes)
                    THEN \(body) ELSE NULL END
            FROM History WHERE rowid>?\(wherePending) ORDER BY rowid LIMIT 16
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(Self.targetApp, index: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, watermark)
        for (index, row) in pending.enumerated() { sqlite3_bind_int64(statement, Int32(index + 3), row) }
        var result: [WisprRecord] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            result.append(
                WisprRecord(
                    rowID: sqlite3_column_int64(statement, 0), entityID: Self.string(statement, 1),
                    app: Self.string(statement, 2), status: Self.string(statement, 3),
                    text: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Self.string(statement, 4)))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw WisprStoreError.queryFailed }
        return result
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw WisprStoreError.unavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw WisprStoreError.queryFailed
        }
        return statement
    }
    private static func tip(_ db: OpaquePointer) throws -> Int64 {
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(rowid),0) FROM History", -1, &statement, nil)
                == SQLITE_OK,
            let statement
        else { throw WisprStoreError.queryFailed }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw WisprStoreError.queryFailed }
        return sqlite3_column_int64(statement, 0)
    }
    private static func identity(_ url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }
    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }
    private func bind(_ value: String, index: Int32, statement: OpaquePointer) {
        value.withCString {
            _ = sqlite3_bind_text(
                statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}
