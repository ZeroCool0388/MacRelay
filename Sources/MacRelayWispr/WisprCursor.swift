import CryptoKit
import Foundation
import MacRelayCore

/// An enable-time cursor with a small, expiring set of new records. Nothing is persisted.
public struct WisprCursor {
    private struct Candidate {
        var record: WisprRecord
        let seen: Date
        var changed: Date
    }
    public private(set) var watermark: Int64
    private var candidates: [Int64: Candidate] = [:]
    private var usedEntities: [String] = []
    public var pendingIDs: [Int64] { candidates.keys.sorted() }
    public func hasUnguardedCompletion(now: Date = Date()) -> Bool {
        candidates.values.contains {
            $0.record.status == "formatted" && $0.record.app == WisprStore.targetApp
                && now.timeIntervalSince($0.changed) > 5
        }
    }
    public init(baseline: Int64) { watermark = baseline }
    public mutating func skip(to tip: Int64) {
        watermark = max(watermark, tip)
        candidates.removeAll()
    }
    public mutating func observe(_ records: [WisprRecord], eligible: Bool, now: Date = Date()) throws {
        let previous = watermark
        candidates = candidates.filter { now.timeIntervalSince($0.value.seen) < 60 }
        for record in records {
            watermark = max(watermark, record.rowID)
            guard eligible, !record.entityID.isEmpty, !usedEntities.contains(record.entityID),
                record.app.isEmpty || record.app == WisprStore.targetApp
            else {
                candidates.removeValue(forKey: record.rowID)
                continue
            }
            if var candidate = candidates[record.rowID] {
                if candidate.record != record { candidate.changed = now }
                candidate.record = record
                candidates[record.rowID] = candidate
            } else if record.rowID > previous {
                guard candidates.count < 8 else { throw WisprStoreError.queryFailed }
                candidates[record.rowID] = Candidate(record: record, seen: now, changed: now)
            }
        }
    }
    /// With paste evidence, require one matching completed record, then stable text.
    /// Without evidence, retain the stricter single-candidate rule.
    public func ready(matchingDigest: Data? = nil, now: Date = Date()) throws -> WisprRecord? {
        let possible = candidates.values.filter { now.timeIntervalSince($0.seen) < 60 }
        if let matchingDigest {
            var matching: [Candidate] = []
            for candidate in possible
            where candidate.record.app == WisprStore.targetApp
                && candidate.record.status == "formatted"
            {
                guard let text = candidate.record.text else { throw RelayError.invalidText }
                try TextPolicy.validate(text)
                if Data(SHA256.hash(data: Data(text.utf8))) == matchingDigest { matching.append(candidate) }
            }
            guard matching.count <= 1 else { throw RelayError.insertionRejected }
            guard let candidate = matching.first, now.timeIntervalSince(candidate.changed) >= 0.25 else {
                return nil
            }
            return candidate.record
        }
        guard possible.count <= 1 else { throw RelayError.insertionRejected }
        guard let candidate = possible.first,
            candidate.record.app == WisprStore.targetApp,
            candidate.record.status == "formatted",
            now.timeIntervalSince(candidate.changed) >= 0.25
        else { return nil }
        guard let text = candidate.record.text else { throw RelayError.invalidText }
        try TextPolicy.validate(text)
        return candidate.record
    }
    public mutating func consume(_ record: WisprRecord) {
        // A matched paste establishes progress. Older pending entries must not later become
        // eligible for another utterance or trigger an unguarded-completion stop.
        let retired = candidates.values.filter { $0.record.rowID <= record.rowID }.map { $0.record.entityID }
        candidates = candidates.filter { $0.key > record.rowID }
        for entity in retired + [record.entityID] where !usedEntities.contains(entity) {
            usedEntities.append(entity)
        }
        if usedEntities.count > 64 { usedEntities.removeFirst(usedEntities.count - 64) }
    }
    /// Counts only; never exposes words, entity IDs, row IDs or fingerprints.
    public func selectionDetails(matchingDigest: Data, now: Date = Date()) -> [String: String] {
        let pending = candidates.values.filter { now.timeIntervalSince($0.seen) < 60 }
        let finished = pending.filter {
            $0.record.app == WisprStore.targetApp && $0.record.status == "formatted"
        }
        let matched = finished.filter {
            guard let text = $0.record.text, (try? TextPolicy.validate(text)) != nil else { return false }
            return Data(SHA256.hash(data: Data(text.utf8))) == matchingDigest
        }
        return [
            "dictationPendingCount": String(pending.count),
            "dictationFinishedCount": String(finished.count),
            "dictationMatchingCount": String(matched.count),
        ]
    }
    public mutating func discardCandidates() { candidates.removeAll() }
}
