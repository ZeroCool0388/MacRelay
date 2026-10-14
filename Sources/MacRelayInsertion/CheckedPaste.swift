import AppKit
import MacRelayCore

/// Restore the original clipboard only before posting or after verified insertion.
/// The callbacks never activate an app or retry an uncertain insertion.
@MainActor
enum CheckedPaste {
    static func perform(
        _ text: String, pasteboard: NSPasteboard,
        destinationUnchanged: () throws -> Bool,
        post: () -> Void,
        verify: () async -> Bool,
        report: (String, String) -> Void
    ) async throws -> Acknowledgement.Status {
        try TextPolicy.validate(text)
        let snapshot = try ClipboardSnapshot(pasteboard)
        guard try destinationUnchanged(), snapshot.changeCount == pasteboard.changeCount else {
            throw AutomationError.focusChanged
        }
        let ownerType = NSPasteboard.PasteboardType("org.macrelay.temporary-insertion")
        let owner = Data(UUID().uuidString.utf8)
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string), item.setData(owner, forType: ownerType) else {
            return .rejected
        }
        pasteboard.clearContents()
        let cleared = pasteboard.changeCount
        guard pasteboard.writeObjects([item]) else {
            report("clipboardRestored", String(snapshot.restore(pasteboard, ifUnchanged: cleared)))
            return .rejected
        }
        let owned = pasteboard.changeCount
        var mayRestore = true
        defer {
            if pasteboard.changeCount == owned, pasteboard.data(forType: ownerType) == owner {
                report(
                    "clipboardRestored",
                    String(mayRestore && snapshot.restore(pasteboard, ifUnchanged: owned)))
                if !mayRestore { report("temporaryClipboardRetained", "true") }
            } else {
                report("clipboardRestored", "false")
                report("newerClipboardPreserved", "true")
            }
        }
        guard try destinationUnchanged(), pasteboard.changeCount == owned,
            pasteboard.data(forType: ownerType) == owner
        else { return .rejected }
        report("insertionStage", "paste-posted")
        // Posting only queues Cmd-V. Until verification succeeds, it may still read the clipboard.
        mayRestore = false
        post()
        let verified = await verify()
        mayRestore = verified
        return verified ? .inserted : .unconfirmed
    }
}
