import Foundation

/// A verified receiver window does not need the optional AXStandardWindow subrole.
/// Main-window fallback is limited to a single window without a modal dialog.
public enum SourceWindowPolicy {
    public static func canUse(
        role: String?, titleMatches: Bool, matchingWindows: Int,
        candidateIsMatchingWindow: Bool, hasFocusedWindow: Bool, mainWindowIsMain: Bool,
        windowCount: Int, minimized: Bool, modal: Bool
    ) -> Bool {
        guard role == "AXWindow", titleMatches, matchingWindows == 1,
            candidateIsMatchingWindow, !minimized, !modal
        else { return false }
        return hasFocusedWindow || (mainWindowIsMain && windowCount == 1)
    }
}

/// Retain the new-record cursor through a short, expected source-focus transition.
/// This does not authorize delivery: the source window still has to pass all checks first.
public enum SourcePausePolicy {
    public static func preserveCursor(
        foreground: String, hasVerifiedBinding: Bool, secondsSinceVerified: TimeInterval
    ) -> Bool {
        guard hasVerifiedBinding, secondsSinceVerified.isFinite, secondsSinceVerified >= 0 else {
            return false
        }
        if ["com.electron.wispr-flow", "com.electron.wispr-flow.accessibility-mac-app"].contains(foreground) {
            return secondsSinceVerified < 60
        }
        return foreground == "com.apple.ScreenSharing" && secondsSinceVerified < 1
    }
}

/// Explicit setup binds one window to an authenticated receiver, independent of its display alias.
/// Window identity, process and original title must all remain the same for delivery.
public enum SourceBindingPolicy {
    public static func matches(
        approvedPID: Int32, currentPID: Int32, sameWindow: Bool,
        approvedTitle: String, currentTitle: String?
    ) -> Bool {
        approvedPID > 0 && approvedPID == currentPID && sameWindow && !approvedTitle.isEmpty
            && currentTitle == approvedTitle
    }
}
