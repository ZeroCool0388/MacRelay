import AppKit

/// Complete, bounded in-memory snapshot. Never touches clipboard history or disk.
@MainActor
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int
    init(_ pasteboard: NSPasteboard) throws {
        changeCount = pasteboard.changeCount
        var result: [[NSPasteboard.PasteboardType: Data]] = []
        var total = 0
        for item in pasteboard.pasteboardItems ?? [] {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
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
