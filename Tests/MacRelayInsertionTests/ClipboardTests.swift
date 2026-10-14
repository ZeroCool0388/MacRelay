import AppKit
import Testing

@testable import MacRelayInsertion

// Private named pasteboards only; never read or change the user's general clipboard.
final class ClipboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    var requestedTypes: [NSPasteboard.PasteboardType] = []
    func pasteboard(
        _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        requestedTypes.append(type)
        item.setData(Data([0]), forType: type)
    }
}

@Suite(.serialized) @MainActor struct ClipboardTests {
    private func board() -> NSPasteboard {
        NSPasteboard(name: .init("org.macrelay.test." + UUID().uuidString))
    }
    @Test func restoresEveryPlainTextItemAfterOwnedWrite() throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("Original", forType: .string)
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
        #expect(pasteboard.pasteboardItems?.last?.string(forType: .string) == "Second")
    }
    @Test func nonPlainFlavorsAreRefusedBeforeLoadingAnyItem() throws {
        for type in [
            NSPasteboard.PasteboardType.pdf, .tiff, .rtf, .fileURL,
            .init("org.macrelay.test.binary"),
        ] {
            let pasteboard = board()
            defer { pasteboard.releaseGlobally() }
            let provider = ClipboardDataProvider()
            let plain = NSPasteboardItem()
            plain.setDataProvider(provider, forTypes: [.string])
            let unsupported = NSPasteboardItem()
            unsupported.setDataProvider(provider, forTypes: [type])
            #expect(pasteboard.writeObjects([plain, unsupported]))
            let originalCount = pasteboard.changeCount
            #expect(throws: AutomationError.clipboardUnsupported) { try ClipboardSnapshot(pasteboard) }
            #expect(provider.requestedTypes.isEmpty)
            #expect(pasteboard.changeCount == originalCount)
        }
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
        pasteboard.setString(String(repeating: "a", count: 8 * 1024 * 1024 + 1), forType: .string)
        #expect(throws: AutomationError.clipboardUnavailable) { try ClipboardSnapshot(pasteboard) }
    }
}
