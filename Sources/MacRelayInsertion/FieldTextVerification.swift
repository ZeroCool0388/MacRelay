import CryptoKit
import Foundation
import MacRelayCore

/// Pin the text representation before insertion. Never switch readers to accept a mismatch.
struct FieldTextVerification {
    let source: String
    private let expected: Data
    private let expectedText: String
    init(value: String, fullRangeText: String?, selection: NSRange, inserting text: String) throws {
        source = fullRangeText == nil ? "value" : "full-range"
        let body = fullRangeText ?? value
        let replacement = try InsertionPolicy.replacingSelection(in: body, range: selection, text: text)
        expectedText = replacement
        expected = Self.digest(replacement)
    }
    func matches(value: String, fullRangeText: String?) -> Bool {
        let observed = source == "full-range" ? fullRangeText : value
        guard let observed,
            observed.utf8.count <= InsertionPolicy.maximumFieldBytes + TextPolicy.maximumBytes
        else { return false }
        return Self.digest(observed) == expected
    }
    /// These comparisons explain mismatches only. They never authorize confirmation.
    func mismatchDetails(value: String, fullRangeText: String?) -> [String: String] {
        guard let observed = source == "full-range" ? fullRangeText : value else {
            return ["verificationReaderUnavailable": "true"]
        }
        return [
            "verificationMatchesWithFinalLineBreak": String(
                Self.digest(observed) == Self.digest(expectedText + "\n")),
            "verificationMatchesIgnoringOuterWhitespace": String(
                observed.trimmingCharacters(in: .whitespacesAndNewlines)
                    == expectedText.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
    }
    static func digest(_ value: String) -> Data { Data(SHA256.hash(data: Data(value.utf8))) }
}
