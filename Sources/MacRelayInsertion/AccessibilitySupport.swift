import AppKit
import ApplicationServices

@MainActor
public enum AccessibilitySupport {
    public static var isTrusted: Bool { AXIsProcessTrusted() }
    public static func openSettings() {
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
}

public enum AutomationError: Error, LocalizedError {
    case permission, clipboardUnavailable, clipboardChanged, noField, protectedField, focusChanged
    case guardUnavailable, screenSharing, wisprNotRunning, noFreshDictation, receiverUpgrade
    case unrecognizedPaste
    public var errorDescription: String? {
        switch self {
        case .permission: return "Allow MacRelay in Accessibility settings, then enable automatic mode again."
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
        case .screenSharing: return "Keep one Screen Sharing window open and focused while dictating."
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
