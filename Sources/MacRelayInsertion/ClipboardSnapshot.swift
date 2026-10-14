import AppKit

/// Snapshot only an empty or plain-text-only clipboard. Never load binary or rich-text flavors.
/// The 8 MiB limit applies to retained text data, not its initial pasteboard allocation.
@MainActor
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int
    init(_ pasteboard: NSPasteboard) throws {
        changeCount = pasteboard.changeCount
        let offered = (pasteboard.pasteboardItems ?? []).map { (item: $0, types: $0.types) }
        // Preflight every item before requesting any data, including lazily provided flavors.
        // A retained temporary-insertion marker also refuses a new, possibly overlapping paste.
        guard offered.allSatisfy({ $0.types.allSatisfy { $0 == .string } }) else {
            throw AutomationError.clipboardUnsupported
        }
        var result: [[NSPasteboard.PasteboardType: Data]] = []
        var total = 0
        for (item, types) in offered {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in types {
                guard let data = item.data(forType: type) else { throw AutomationError.clipboardUnavailable }
                total += data.count
                guard total <= 8 * 1024 * 1024 else { throw AutomationError.clipboardUnavailable }
                values[type] = data
            }
            result.append(values)
        }
        guard changeCount == pasteboard.changeCount else { throw AutomationError.clipboardChanged }
        items = result
    }
    @discardableResult
    func restore(_ pasteboard: NSPasteboard, ifUnchanged expectedCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedCount else { return false }
        let restored = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        return restored.isEmpty || pasteboard.writeObjects(restored)
    }
}
