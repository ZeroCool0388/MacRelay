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
        testDetails = ["insertionStage": "checking-field"]
        let target = try current()
        let token = try permit.arm()
        destination = target
        testDetails["insertionStage"] = "field-armed"
        return token
    }
    public func insert(_ text: String, token: UUID) async -> Acknowledgement.Status {
        guard !busy, permit.consume(token), let target = destination else { return .rejected }
        destination = nil
        busy = true
        defer { busy = false }
        testDetails["insertionStage"] = "checking-before-paste"
        testDetails["insertionMethod"] = "checked-paste"
        do {
            let (now, value) = try checkedValue()
            guard same(target, now) else { throw AutomationError.focusChanged }
            let expected = try InsertionPolicy.replacingSelection(in: value, range: target.range, text: text)
            let expectedHash = digest(expected)
            // A writable AXSelectedText flag does not prove that the app supports insertion.
            // Choose one checked native paste up front, never an AX write followed by paste.
            // Keep remote/dictation modifier state out of the generated shortcut.
            guard let source = CGEventSource(stateID: .privateState),
                let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            else { return .rejected }
            down.flags = .maskCommand
            up.flags = .maskCommand
            let result = try await CheckedPaste.perform(
                text, pasteboard: .general,
                destinationUnchanged: { self.same(target, try self.current()) },
                post: {
                    down.postToPid(target.pid)
                    up.postToPid(target.pid)
                },
                verify: { await self.verify(target, expectedHash: expectedHash) },
                report: { self.testDetails[$0] = $1 })
            testDetails["insertionStage"] = result.rawValue
            return result
        } catch {
            testDetails["insertionStage"] = "rejected-before-paste"
            testDetails["insertionFailure"] =
                error is AutomationError ? error.localizedDescription : "field-check-failed"
            return .rejected
        }
    }
    private func verify(_ target: Destination, expectedHash: Data) async -> Bool {
        // Read-only verification; never re-post a failed/slow paste.
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, AccessibilitySupport.isTrusted else {
                testDetails["verification"] = "cancelled-or-permission-lost"
                return false
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
                testDetails["verification"] = "foreground-changed"
                return false
            }
            guard
                let appWindow = AccessibilitySupport.element(
                    AXUIElementCreateApplication(target.pid), kAXFocusedWindowAttribute),
                CFEqual(appWindow, target.window),
                let appField = AccessibilitySupport.element(
                    AXUIElementCreateApplication(target.pid), kAXFocusedUIElementAttribute),
                CFEqual(appField, target.field),
                let value = AccessibilitySupport.attribute(target.field, kAXValueAttribute) as? String
            else {
                testDetails["verification"] = "field-or-window-unavailable-or-changed"
                return false
            }
            if value.utf8.count <= InsertionPolicy.maximumFieldBytes + TextPolicy.maximumBytes,
                digest(value) == expectedHash
            {
                testDetails["verification"] = "expected-value-matched"
                return true
            }
        }
        testDetails["verification"] = "expected-value-not-observed"
        return false
    }
    private func current() throws -> Destination { try checkedValue().0 }
    private func checkedValue() throws -> (Destination, String) {
        testDetails["accessibilityAllowed"] = String(AccessibilitySupport.isTrusted)
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
