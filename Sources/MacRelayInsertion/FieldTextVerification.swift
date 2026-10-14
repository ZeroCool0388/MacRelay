import CryptoKit
import Foundation
import MacRelayCore

/// Pin the text representation before insertion. Never switch readers to accept a mismatch.
struct FieldTextVerification {
    enum Match: String {
        case exact
        case chatBoundaryWhitespace = "chat-boundary-whitespace"
    }
    let source: String
    private let expected: Data
    private let expectedText: String
    private let formattedExpected: Data?
    init(
        value: String, fullRangeText: String?, selection: NSRange, inserting text: String,
        appBundleIdentifier: String? = nil
    ) throws {
        source = fullRangeText == nil ? "value" : "full-range"
        let body = fullRangeText ?? value
        let replacement = try InsertionPolicy.replacingSelection(in: body, range: selection, text: text)
        expectedText = replacement
        expected = Self.digest(replacement)
        let formatted = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // This compatibility rule applies only to Codex's complete editable-text reader.
        // It changes confirmation, never the pasted payload. Existing content must actually change.
        formattedExpected =
            source == "full-range" && appBundleIdentifier == "com.openai.codex"
                && !formatted.isEmpty && Self.digest(formatted) != Self.digest(previous)
            ? Self.digest(formatted) : nil
    }
    func matches(value: String, fullRangeText: String?) -> Bool {
        match(value: value, fullRangeText: fullRangeText) != nil
    }
    func match(value: String, fullRangeText: String?) -> Match? {
        let observed = source == "full-range" ? fullRangeText : value
        guard let observed,
            observed.utf8.count <= InsertionPolicy.maximumFieldBytes + TextPolicy.maximumBytes
        else { return nil }
        if Self.digest(observed) == expected { return .exact }
        if let formattedExpected,
            Self.digest(observed.trimmingCharacters(in: .whitespacesAndNewlines)) == formattedExpected
        {
            return .chatBoundaryWhitespace
        }
        return nil
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
            "verificationMatchesIgnoringOnlyOuterWhitespace": String(
                Self.digest(observed.trimmingCharacters(in: .whitespacesAndNewlines))
                    == Self.digest(expectedText.trimmingCharacters(in: .whitespacesAndNewlines))),
        ]
    }
    static func digest(_ value: String) -> Data { Data(SHA256.hash(data: Data(value.utf8))) }
}
