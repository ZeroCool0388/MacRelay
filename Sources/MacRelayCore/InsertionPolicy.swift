import Foundation

/// A token is consumed before any attempted insertion, including a focus failure.
public struct InsertionPermit {
    public static let lifetime: TimeInterval = 15
    private var pending: (token: UUID, expiry: Date)?
    public init() {}
    public mutating func arm(now: Date = Date()) throws -> UUID {
        if let pending, now < pending.expiry { throw RelayError.busy }
        let token = UUID()
        pending = (token, now.addingTimeInterval(Self.lifetime))
        return token
    }
    public mutating func consume(_ token: UUID, now: Date = Date()) -> Bool {
        guard let current = pending, token == current.token else { return false }
        pending = nil
        return now < current.expiry
    }
    public mutating func clear() { pending = nil }
}

public enum InsertionPolicy {
    public static let maximumFieldBytes = 256 * 1024
    public static func isValidSelection(_ range: NSRange, in value: String) -> Bool {
        let units = Array(value.utf16)
        guard range.location >= 0, range.length >= 0, range.location <= units.count,
            range.length <= units.count - range.location
        else { return false }
        func splitsSurrogate(_ offset: Int) -> Bool {
            offset > 0 && offset < units.count && (0xD800...0xDBFF).contains(units[offset - 1])
                && (0xDC00...0xDFFF).contains(units[offset])
        }
        return !splitsSurrogate(range.location) && !splitsSurrogate(range.location + range.length)
    }
    /// Accessibility ranges use UTF-16. Reject ranges that split a surrogate pair.
    public static func replacingSelection(in value: String, range: NSRange, text: String) throws -> String {
        try TextPolicy.validate(text)
        guard value.utf8.count <= maximumFieldBytes,
            isValidSelection(range, in: value)
        else { throw RelayError.insertionRejected }
        return (value as NSString).replacingCharacters(in: range, with: text)
    }
}
