import AppKit
import Testing

@testable import MacRelayInsertion

// Private named pasteboards only; never read or change the user's general clipboard.
@Suite(.serialized) @MainActor struct ClipboardTests {
    private func board() -> NSPasteboard {
        NSPasteboard(name: .init("org.macrelay.test." + UUID().uuidString))
    }
    @Test func restoresEveryItemAndTypeAfterOwnedWrite() throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("org.macrelay.test.binary")
        let first = NSPasteboardItem()
        first.setString("Original", forType: .string)
        first.setData(Data([0, 1, 255]), forType: custom)
        let second = NSPasteboardItem()
        second.setString("Second", forType: .string)
        #expect(pasteboard.writeObjects([first, second]))
        let snapshot = try ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("Temporary dictation", forType: .string)
        let restored = snapshot.restore(pasteboard, ifUnchanged: pasteboard.changeCount)
        #expect(restored)
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(pasteboard.pasteboardItems?.first?.string(forType: .string) == "Original")
        #expect(pasteboard.pasteboardItems?.first?.data(forType: custom) == Data([0, 1, 255]))
        #expect(pasteboard.pasteboardItems?.last?.string(forType: .string) == "Second")
    }
    @Test func neverRestoresOverAnotherClipboardWriter() throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Original", forType: .string)
        let snapshot = try ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("Temporary", forType: .string)
        let owned = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("User's newer copy", forType: .string)
        #expect(!snapshot.restore(pasteboard, ifUnchanged: owned))
        #expect(pasteboard.string(forType: .string) == "User's newer copy")
    }
    @Test func oversizedClipboardRefusesInsertionAndEmptyClipboardRestores() throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let empty = try ClipboardSnapshot(pasteboard)
        pasteboard.setString("Temporary", forType: .string)
        #expect(empty.restore(pasteboard, ifUnchanged: pasteboard.changeCount))
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
        pasteboard.setData(
            Data(repeating: 0, count: 8 * 1024 * 1024 + 1), forType: .init("org.macrelay.test.large"))
        #expect(throws: AutomationError.clipboardUnavailable) { try ClipboardSnapshot(pasteboard) }
    }
}
