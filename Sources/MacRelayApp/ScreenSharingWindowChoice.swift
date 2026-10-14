import AppKit
import ApplicationServices
import MacRelayCore
import MacRelayInsertion

@MainActor
struct ScreenSharingWindowBinding {
    let pid: pid_t
    let window: AXUIElement
    let originalTitle: String
    func matches(pid: pid_t, window: AXUIElement, title: String?) -> Bool {
        SourceBindingPolicy.matches(
            approvedPID: self.pid, currentPID: pid,
            sameWindow: CFEqual(self.window, window), approvedTitle: originalTitle, currentTitle: title)
    }
    var isAvailable: Bool {
        guard
            NSWorkspace.shared.runningApplications.contains(where: {
                $0.processIdentifier == pid && $0.bundleIdentifier == "com.apple.ScreenSharing"
            })
        else { return false }
        return matches(
            pid: pid, window: window,
            title: AccessibilitySupport.attribute(window, kAXTitleAttribute) as? String)
    }
}

@MainActor
struct ScreenSharingWindowChoice: Identifiable {
    let id = UUID()
    let binding: ScreenSharingWindowBinding
    let label: String
    let isFocused: Bool
    static func available() -> [Self] {
        var result: [Self] = []
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == "com.apple.ScreenSharing" {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            let focused = AccessibilitySupport.element(root, kAXFocusedWindowAttribute)
            var windows = AccessibilitySupport.attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let focused, !windows.contains(where: { CFEqual($0, focused) }) { windows.append(focused) }
            for window in windows {
                guard AccessibilitySupport.attribute(window, kAXRoleAttribute) as? String == kAXWindowRole,
                    AccessibilitySupport.attribute(window, kAXMinimizedAttribute) as? Bool != true,
                    AccessibilitySupport.attribute(window, kAXModalAttribute) as? Bool != true,
                    let title = AccessibilitySupport.attribute(window, kAXTitleAttribute) as? String,
                    !title.isEmpty
                else { continue }
                let safeTitle =
                    title.count <= 160 && !title.contains("://") && !title.contains("@")
                        && !title.unicodeScalars.contains(where: {
                            CharacterSet.controlCharacters.contains($0)
                        })
                    ? title : "Screen Sharing window \(result.count + 1)"
                let isFocused = focused.map { CFEqual($0, window) } ?? false
                result.append(
                    Self(
                        binding: ScreenSharingWindowBinding(
                            pid: app.processIdentifier,
                            window: window, originalTitle: title),
                        label: safeTitle + (isFocused ? " (current)" : ""), isFocused: isFocused))
            }
        }
        return result
    }
    func show() {
        guard binding.isAvailable else { return }
        AXUIElementPerformAction(binding.window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: binding.pid)?.activate(options: [])
    }
}
