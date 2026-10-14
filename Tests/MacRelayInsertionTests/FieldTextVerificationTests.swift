import Foundation
import MacRelayCore
import Testing

@testable import MacRelayInsertion

@Suite struct FieldTextVerificationTests {
    @Test func completeRangeConfirmsEvenWhenDisplayedValueIsStale() throws {
        let check = try FieldTextVerification(
            value: "Displayed label", fullRangeText: "", selection: NSRange(location: 0, length: 0),
            inserting: "Sample 🌍")
        #expect(check.source == "full-range")
        #expect(check.matches(value: "Displayed label", fullRangeText: "Sample 🌍"))
        #expect(!check.matches(value: "Sample 🌍", fullRangeText: nil))
        #expect(!check.matches(value: "Sample 🌍", fullRangeText: "Partial"))
    }

    @Test func replacementKeepsExistingTextAndUnicodeSelection() throws {
        let check = try FieldTextVerification(
            value: "A😀B", fullRangeText: "A😀B", selection: NSRange(location: 1, length: 2),
            inserting: "🏌️\n")
        #expect(check.matches(value: "stale", fullRangeText: "A🏌️\nB"))
        #expect(!check.matches(value: "A🏌️\nB", fullRangeText: "🏌️\n"))
        #expect(!check.matches(value: "A🏌️\nB", fullRangeText: "A🏌️\nB🏌️\n"))
    }

    @Test func nativeValueReaderRemainsExactWhenRangeAPIIsUnavailable() throws {
        let check = try FieldTextVerification(
            value: "First", fullRangeText: nil, selection: NSRange(location: 5, length: 0),
            inserting: " second")
        #expect(check.source == "value")
        #expect(check.matches(value: "First second", fullRangeText: nil))
        #expect(!check.matches(value: "First", fullRangeText: "First second"))
    }

    @Test func formattingDiagnosticsNeverAcceptWhitespaceOrExtraLines() throws {
        let check = try FieldTextVerification(
            value: "", fullRangeText: nil, selection: NSRange(location: 0, length: 0),
            inserting: "Sample")
        #expect(!check.matches(value: "Sample\n", fullRangeText: nil))
        #expect(
            check.mismatchDetails(value: "Sample\n", fullRangeText: nil)[
                "verificationMatchesWithFinalLineBreak"] == "true")
        #expect(!check.matches(value: " Sample ", fullRangeText: nil))
        #expect(!check.matches(value: "Sample\nDifferent", fullRangeText: nil))
    }

    @Test func canonicalReaderRejectsInvalidSelectionAndOversizedResult() throws {
        #expect(throws: RelayError.insertionRejected) {
            try FieldTextVerification(
                value: "Long displayed label", fullRangeText: "", selection: NSRange(location: 2, length: 0),
                inserting: "Sample")
        }
        let check = try FieldTextVerification(
            value: "", fullRangeText: "", selection: NSRange(location: 0, length: 0), inserting: "Sample")
        #expect(
            !check.matches(
                value: "Sample", fullRangeText: String(repeating: "a", count: 321 * 1024)))
    }
}
