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
        let bundleIdentifier: String
        let field: AXUIElement
        let window: AXUIElement
        let valueHash: Data
        let fullRangeHash: Data?
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
    public func cancel(_ token: UUID) {
        if permit.cancel(token) { destination = nil }
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
        guard !busy else {
            testDetails["rejectionCheck"] = "insertion-busy"
            return .rejected
        }
        guard permit.consume(token) else {
            testDetails["insertionStage"] = "rejected-before-paste"
            testDetails["rejectionCheck"] = "invalid-or-expired-token"
            return .rejected
        }
        guard let target = destination else {
            testDetails["insertionStage"] = "rejected-before-paste"
            testDetails["rejectionCheck"] = "reservation-cleared"
            return .rejected
        }
        destination = nil
        busy = true
        defer { busy = false }
        testDetails["insertionStage"] = "checking-before-paste"
        testDetails["insertionMethod"] = "checked-paste"
        do {
            let (now, value, fullRangeText) = try checkedValue()
            guard same(target, now) else { throw AutomationError.focusChanged }
            let verification = try FieldTextVerification(
                value: value, fullRangeText: fullRangeText, selection: target.range, inserting: text,
                appBundleIdentifier: target.bundleIdentifier)
            testDetails["textVerificationSource"] = verification.source
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
                verify: { await self.verify(target, verification: verification) },
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
    private func verify(_ target: Destination, verification: FieldTextVerification) async -> Bool {
        // Read-only verification; never re-post a failed/slow paste.
        let deadline = Date().addingTimeInterval(1.5)
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Date() > deadline { break }
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
            guard value.utf8.count <= InsertionPolicy.maximumFieldBytes + TextPolicy.maximumBytes else {
                testDetails["verification"] = "field-too-large"
                return false
            }
            let body = AccessibilitySupport.fullRangeText(
                target.field, maximumBytes: InsertionPolicy.maximumFieldBytes + TextPolicy.maximumBytes)
            testDetails["verificationValueChanged"] = String(digest(value) != target.valueHash)
            testDetails["verificationFullRangeReadable"] = String(body != nil)
            if let match = verification.match(value: value, fullRangeText: body) {
                testDetails["verificationMatch"] = match.rawValue
                testDetails["verification"] = "expected-value-matched"
                return true
            }
            testDetails.merge(
                verification.mismatchDetails(value: value, fullRangeText: body),
                uniquingKeysWith: { _, new in new })
        }
        testDetails["verification"] = "expected-value-not-observed"
        return false
    }
    private func current() throws -> Destination { try checkedValue().0 }
    private func checkedValue() throws -> (Destination, String, String?) {
        testDetails["accessibilityAllowed"] = String(AccessibilitySupport.isTrusted)
        guard AccessibilitySupport.isTrusted else { throw AutomationError.permission }
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else {
            throw AutomationError.noField
        }
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        testDetails["destinationApp"] =
            bundle == "com.openai.codex" ? "codex" : bundle == "com.apple.textedit" ? "textedit" : "other"
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
        let body = AccessibilitySupport.fullRangeText(
            field, maximumBytes: InsertionPolicy.maximumFieldBytes)
        testDetails["fullRangeTextReadable"] = String(body != nil)
        if let body, !InsertionPolicy.isValidSelection(range, in: body) { throw AutomationError.noField }
        return (
            Destination(
                pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier ?? "",
                field: field, window: window, valueHash: digest(value),
                fullRangeHash: body.map(digest), range: range), value, body
        )
    }
    private func same(_ lhs: Destination, _ rhs: Destination) -> Bool {
        lhs.pid == rhs.pid && lhs.bundleIdentifier == rhs.bundleIdentifier
            && CFEqual(lhs.field, rhs.field) && CFEqual(lhs.window, rhs.window)
            && lhs.valueHash == rhs.valueHash && lhs.fullRangeHash == rhs.fullRangeHash
            && lhs.range == rhs.range
    }
    private func digest(_ value: String) -> Data { Data(SHA256.hash(data: Data(value.utf8))) }
}
