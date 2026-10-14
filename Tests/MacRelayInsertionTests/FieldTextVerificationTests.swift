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

    @Test func codexBoundaryFormattingConfirmsWithoutChangingWordsOrInternalSpacing() throws {
        let check = try FieldTextVerification(
            value: "\n", fullRangeText: "\n", selection: NSRange(location: 0, length: 0),
            inserting: "Sample words.", appBundleIdentifier: "com.openai.codex")
        #expect(
            check.match(value: "Sample words.", fullRangeText: "Sample words.") == .chatBoundaryWhitespace)
        #expect(check.match(value: "unused", fullRangeText: "Sample words.\n") == .exact)
        for wrong in [
            "Sample", "Sample words", "Sample  words.", "Different words.", "Sample words.Sample words.",
        ] {
            #expect(!check.matches(value: "unused", fullRangeText: wrong))
        }
        #expect(!check.matches(value: "Sample words.", fullRangeText: nil))
    }

    @Test func formattingExceptionRequiresTheExactCodexAppAndFullRangeReader() throws {
        for bundle in ["com.apple.TextEdit", "com.openai.codex.other", "unknown", ""] {
            let check = try FieldTextVerification(
                value: "\n", fullRangeText: "\n", selection: NSRange(location: 0, length: 0),
                inserting: "Sample", appBundleIdentifier: bundle)
            #expect(!check.matches(value: "Sample", fullRangeText: "Sample"))
        }
        let valueOnly = try FieldTextVerification(
            value: "\n", fullRangeText: nil, selection: NSRange(location: 0, length: 0),
            inserting: "Sample", appBundleIdentifier: "com.openai.codex")
        #expect(!valueOnly.matches(value: "Sample", fullRangeText: "Sample"))
    }

    @Test func formattedConfirmationRefusesUnchangedContentAndWhitespaceOnlyInsertion() throws {
        let unchanged = try FieldTextVerification(
            value: "Sample\n", fullRangeText: "Sample\n", selection: NSRange(location: 0, length: 7),
            inserting: "Sample", appBundleIdentifier: "com.openai.codex")
        #expect(!unchanged.matches(value: "Sample\n", fullRangeText: "Sample\n"))
        let whitespace = try FieldTextVerification(
            value: "", fullRangeText: "", selection: NSRange(location: 0, length: 0),
            inserting: " \n", appBundleIdentifier: "com.openai.codex")
        #expect(!whitespace.matches(value: "\n ", fullRangeText: "\n "))
    }

    @Test func aSecondSentenceKeepsItsSeparatingSpaceAndUnicodeContent() throws {
        let check = try FieldTextVerification(
            value: "First.", fullRangeText: "First.", selection: NSRange(location: 6, length: 0),
            inserting: " Café second.", appBundleIdentifier: "com.openai.codex")
        #expect(check.matches(value: "unused", fullRangeText: "\nFirst. Café second.\n"))
        #expect(!check.matches(value: "unused", fullRangeText: "First.Café second."))
        #expect(!check.matches(value: "unused", fullRangeText: "First. Cafe\u{301} second."))
    }
}
