import Foundation

/// A single volatile slot. Receiving while occupied returns busy, never replaces text.
public struct Inbox {
    public static let lifetime: TimeInterval = 120
    public private(set) var text: String?
    public private(set) var expiresAt: Date?
    public init() {}
    public mutating func receive(_ transfer: Transfer, now: Date = Date()) throws -> Acknowledgement {
        try transfer.validate()
        expire(now: now)
        if transfer.kind == .probe { return Acknowledgement(id: transfer.id, status: .paired) }
        guard text == nil else { return Acknowledgement(id: transfer.id, status: .busy) }
        text = transfer.text
        expiresAt = now.addingTimeInterval(Self.lifetime)
        return Acknowledgement(id: transfer.id, status: .accepted)
    }
    public mutating func expire(now: Date = Date()) {
        if let expiresAt, now >= expiresAt { clear() }
    }
    public mutating func clear() {
        text = nil
        expiresAt = nil
    }
}
