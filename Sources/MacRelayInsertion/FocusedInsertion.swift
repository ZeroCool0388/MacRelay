import AppKit
import ApplicationServices
import CryptoKit
import MacRelayCore

/// Reserves the actual focused field. Values/selection are checked again just before insertion.
/// No app activation, focus changes, Enter key, or retry. Password fields and terminals are refused.
@MainActor
public final class FocusedInsertion {
    private struct Destination {
        let pid: pid_t
        let field: AXUIElement
        let window: AXUIElement
        let valueHash: Data
        let range: NSRange
    }
    private var permit = InsertionPermit()
    private var destination: Destination?
    private var busy = false
    public private(set) var testDetails: [String: String] = [:]
    public init() {}
    public func clear() {
        permit.clear()
        destination = nil
    }
    public func arm() throws -> UUID {
        guard !busy else { throw RelayError.busy }
        let target = try current()
        let token = try permit.arm()
        destination = target
        return token
    }
    public func insert(_ text: String, token: UUID) async -> Acknowledgement.Status {
        guard !busy, permit.consume(token), let target = destination else { return .rejected }
        destination = nil
        busy = true
        defer { busy = false }
        do {
            let (now, value) = try checkedValue()
            guard same(target, now) else { throw AutomationError.focusChanged }
            let expected = try InsertionPolicy.replacingSelection(in: value, range: target.range, text: text)
            let expectedHash = digest(expected)
            if AccessibilitySupport.isSettable(target.field, kAXSelectedTextAttribute) {
                // A failed or unverified AX write is never followed by a second insertion method.
                let result = AXUIElementSetAttributeValue(
                    target.field, kAXSelectedTextAttribute as CFString, text as CFString)
                guard result == .success else { return .unconfirmed }
                return await verify(target, expectedHash: expectedHash) ? .inserted : .unconfirmed
            }
            let pasteboard = NSPasteboard.general
            let snapshot = try ClipboardSnapshot(pasteboard)
            guard same(target, try current()), snapshot.changeCount == pasteboard.changeCount else {
                throw AutomationError.focusChanged
            }
            // Construct both events before changing the clipboard.
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
            else { return .rejected }
            down.flags = .maskCommand
            up.flags = .maskCommand
            let ownerType = NSPasteboard.PasteboardType("org.macrelay.temporary-insertion")
            let owner = Data(UUID().uuidString.utf8)
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string), item.setData(owner, forType: ownerType) else {
                return .rejected
            }
            pasteboard.clearContents()
            let written = pasteboard.changeCount
            guard pasteboard.writeObjects([item]) else {
                _ = snapshot.restore(pasteboard, ifUnchanged: written)
                return .rejected
            }
            let owned = pasteboard.changeCount
            defer {
                if pasteboard.data(forType: ownerType) == owner {
                    _ = snapshot.restore(pasteboard, ifUnchanged: owned)
                }
            }
            guard pasteboard.data(forType: ownerType) == owner, same(target, try current()) else {
                return .rejected
            }
            down.postToPid(target.pid)
            up.postToPid(target.pid)
            return await verify(target, expectedHash: expectedHash) ? .inserted : .unconfirmed
        } catch { return .rejected }
    }
    private func verify(_ target: Destination, expectedHash: Data) async -> Bool {
        // Read-only verification; never re-post a failed/slow paste.
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, AccessibilitySupport.isTrusted,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                let appWindow = AccessibilitySupport.element(
                    AXUIElementCreateApplication(target.pid), kAXFocusedWindowAttribute),
                CFEqual(appWindow, target.window),
                let appField = AccessibilitySupport.element(
                    AXUIElementCreateApplication(target.pid), kAXFocusedUIElementAttribute),
                CFEqual(appField, target.field),
                let value = AccessibilitySupport.attribute(target.field, kAXValueAttribute) as? String
            else { return false }
            if value.utf8.count <= InsertionPolicy.maximumFieldBytes + TextPolicy.maximumBytes,
                digest(value) == expectedHash
            {
                return true
            }
        }
        return false
    }
    private func current() throws -> Destination { try checkedValue().0 }
    private func checkedValue() throws -> (Destination, String) {
        testDetails = ["accessibilityAllowed": String(AccessibilitySupport.isTrusted)]
        guard AccessibilitySupport.isTrusted else { throw AutomationError.permission }
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else {
            throw AutomationError.noField
        }
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        let blocked = [
            "terminal", "iterm", "warp", "kitty", "wezterm", "alacritty", "ghostty", "hyper", "ssh",
        ]
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
            !blocked.contains(where: { bundle.contains($0) })
        else { throw AutomationError.protectedField }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let field = AccessibilitySupport.element(root, kAXFocusedUIElementAttribute),
            let window = AccessibilitySupport.element(root, kAXFocusedWindowAttribute),
            let role = AccessibilitySupport.attribute(field, kAXRoleAttribute) as? String,
            [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
        else { throw AutomationError.noField }
        testDetails["fieldRole"] = role
        testDetails["selectedTextWritable"] = String(
            AccessibilitySupport.isSettable(field, kAXSelectedTextAttribute))
        testDetails["valueWritable"] = String(AccessibilitySupport.isSettable(field, kAXValueAttribute))
        let subrole = AccessibilitySupport.attribute(field, kAXSubroleAttribute) as? String ?? ""
        guard subrole != kAXSecureTextFieldSubrole,
            AccessibilitySupport.attribute(field, "AXProtectedContent") as? Bool != true,
            AccessibilitySupport.attribute(field, kAXEnabledAttribute) as? Bool != false
        else { throw AutomationError.protectedField }
        testDetails["valueReadable"] = String(
            AccessibilitySupport.attribute(field, kAXValueAttribute) is String)
        testDetails["selectionReadable"] = String(AccessibilitySupport.selection(field) != nil)
        guard
            AccessibilitySupport.isSettable(field, kAXSelectedTextAttribute)
                || AccessibilitySupport.isSettable(field, kAXValueAttribute),
            let value = AccessibilitySupport.attribute(field, kAXValueAttribute) as? String,
            value.utf8.count <= InsertionPolicy.maximumFieldBytes,
            let range = AccessibilitySupport.selection(field),
            InsertionPolicy.isValidSelection(range, in: value)
        else { throw AutomationError.noField }
        return (
            Destination(
                pid: app.processIdentifier, field: field, window: window, valueHash: digest(value),
                range: range), value
        )
    }
    private func same(_ lhs: Destination, _ rhs: Destination) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.field, rhs.field) && CFEqual(lhs.window, rhs.window)
            && lhs.valueHash == rhs.valueHash && lhs.range == rhs.range
    }
    private func digest(_ value: String) -> Data { Data(SHA256.hash(data: Data(value.utf8))) }
}
