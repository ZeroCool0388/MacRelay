import AppKit
import ApplicationServices

@MainActor
public enum AccessibilitySupport {
    public static var isTrusted: Bool { AXIsProcessTrusted() }
    /// Call only for an explicit setup gesture. The macOS prompt is asynchronous;
    /// the return value still reflects current permission, not a future approval.
    public static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    public static func openSettings() {
        _ = requestPermission()
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
    public static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    public static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }
    public static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
            && settable.boolValue
    }
    public static func selection(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute),
            CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }
    /// Read the complete editable text using the field's character count and range API.
    /// Refuse changing counts, partial responses and oversized fields. Call only after protected-field checks.
    static func fullRangeText(_ element: AXUIElement, maximumBytes: Int) -> String? {
        guard let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
            CFGetTypeID(count) == CFNumberGetTypeID(),
            count.doubleValue.isFinite, count.doubleValue == Double(count.intValue),
            count.intValue >= 0, count.intValue <= maximumBytes
        else { return nil }
        let length = count.intValue
        var range = CFRange(location: 0, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var raw: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &raw) == .success,
            let text = raw as? String, text.utf16.count == length, text.utf8.count <= maximumBytes,
            let after = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
            CFGetTypeID(after) == CFNumberGetTypeID(), after.doubleValue == Double(length)
        else { return nil }
        return text
    }
}

public enum AutomationError: Error, LocalizedError {
    case permission, clipboardUnavailable, clipboardChanged, noField, protectedField, focusChanged
    case guardUnavailable, screenSharing, wisprNotRunning, noFreshDictation, receiverUpgrade
    case unrecognizedPaste, screenSharingWindowUnavailable, screenSharingNameMismatch,
        screenSharingWindowChanged
    public var errorDescription: String? {
        switch self {
        case .permission:
            return
                "Allow MacRelay in Privacy & Security → Accessibility (Device Control and Data Access on newer macOS), then enable automatic mode again."
        case .clipboardUnavailable:
            return "The mini's clipboard could not be preserved. Nothing was inserted."
        case .clipboardChanged: return "The clipboard changed. Insertion was stopped."
        case .noField:
            return "Click into an editable text field on the mini. This field could not be checked safely."
        case .protectedField: return "Automatic insertion is disabled for password fields and terminals."
        case .focusChanged: return "The focused app, field or selection changed. Nothing was inserted."
        case .guardUnavailable:
            return
                "Wispr's paste blocker is unavailable. Automatic mode is off. Check Accessibility permission."
        case .screenSharing:
            return "Return to the mini's Screen Sharing window. It must be focused for automatic delivery."
        case .screenSharingWindowUnavailable:
            return "Screen Sharing's active window could not be verified. Save the MacBook test report."
        case .screenSharingWindowChanged:
            return
                "The chosen Screen Sharing window changed or is not focused. Choose the mini's window again."
        case .screenSharingNameMismatch:
            return
                "The Screen Sharing window's name does not match the paired mini. Save the MacBook test report."
        case .wisprNotRunning: return "Open Wispr Flow on the MacBook, then enable automatic mode again."
        case .noFreshDictation:
            return "No matching completed dictation was found. Check Wispr and try a new dictation."
        case .receiverUpgrade:
            return "Update MacRelay on the mini and enable Insert dictation automatically there."
        case .unrecognizedPaste:
            return "Wispr finished, but its paste event was not recognized. Nothing was sent automatically."
        }
    }
}
