import AppKit
import MacRelayCore
import Testing

@testable import MacRelayInsertion

// Exercise the receiver's actual paste transaction using private pasteboards and a fake field.
// No general clipboard, real keyboard event, pairing key or user text is accessed.
@Suite(.serialized) @MainActor struct CheckedPasteTests {
    private func board() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("org.macrelay.test." + UUID().uuidString))
        pasteboard.setString("Previous copy", forType: .string)
        return pasteboard
    }

    @Test func confirmsOneInsertionAndRestoresAfterDelayedVerification() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var field = ""
        var posts = 0
        var report: [String: String] = [:]
        let result = try await CheckedPaste.perform(
            "Sample 🌍", pasteboard: pasteboard, destinationUnchanged: { true },
            post: {
                posts += 1
                field = pasteboard.string(forType: .string) ?? ""
            },
            verify: {
                await Task.yield()
                #expect(pasteboard.string(forType: .string) == "Sample 🌍")
                return field == "Sample 🌍"
            }, report: { report[$0] = $1 })
        #expect(result == .inserted)
        #expect(posts == 1)
        #expect(pasteboard.string(forType: .string) == "Previous copy")
        #expect(report["clipboardRestored"] == "true")
    }

    @Test func uncertainInsertionIsNeverPostedAgain() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var posts = 0
        let result = try await CheckedPaste.perform(
            "Sample", pasteboard: pasteboard, destinationUnchanged: { true },
            post: { posts += 1 }, verify: { false }, report: { _, _ in })
        #expect(result == .unconfirmed)
        #expect(posts == 1)
        #expect(pasteboard.string(forType: .string) == "Previous copy")
    }

    @Test func changedDestinationBeforeWriteLeavesClipboardAlone() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let originalCount = pasteboard.changeCount
        var posts = 0
        do {
            _ = try await CheckedPaste.perform(
                "Sample", pasteboard: pasteboard, destinationUnchanged: { false },
                post: { posts += 1 }, verify: { true }, report: { _, _ in })
            Issue.record("A changed destination must be refused")
        } catch AutomationError.focusChanged {}
        #expect(posts == 0)
        #expect(pasteboard.changeCount == originalCount)
        #expect(pasteboard.string(forType: .string) == "Previous copy")
    }

    @Test func changedDestinationAfterWriteRestoresWithoutPosting() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var checks = 0
        var posts = 0
        let result = try await CheckedPaste.perform(
            "Sample", pasteboard: pasteboard,
            destinationUnchanged: {
                checks += 1
                return checks == 1
            }, post: { posts += 1 }, verify: { true }, report: { _, _ in })
        #expect(result == .rejected)
        #expect(posts == 0)
        #expect(pasteboard.string(forType: .string) == "Previous copy")
    }

    @Test func newerCopyDuringVerificationIsPreserved() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var report: [String: String] = [:]
        let result = try await CheckedPaste.perform(
            "Sample", pasteboard: pasteboard, destinationUnchanged: { true }, post: {},
            verify: {
                pasteboard.clearContents()
                pasteboard.setString("Newer user copy", forType: .string)
                return false
            }, report: { report[$0] = $1 })
        #expect(result == .unconfirmed)
        #expect(pasteboard.string(forType: .string) == "Newer user copy")
        #expect(report["newerClipboardPreserved"] == "true")
    }

    @Test func newerCopyDuringFinalFieldCheckPreventsPaste() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        var checks = 0
        var posts = 0
        let result = try await CheckedPaste.perform(
            "Sample", pasteboard: pasteboard,
            destinationUnchanged: {
                checks += 1
                if checks == 2 {
                    pasteboard.clearContents()
                    pasteboard.setString("Newer user copy", forType: .string)
                }
                return true
            }, post: { posts += 1 }, verify: { true }, report: { _, _ in })
        #expect(result == .rejected)
        #expect(posts == 0)
        #expect(pasteboard.string(forType: .string) == "Newer user copy")
    }
}
