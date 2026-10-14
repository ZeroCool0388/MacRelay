import AppKit
import ApplicationServices
import CryptoKit
import MacRelayCore
import MacRelayInsertion

/// Only filters V events whose source PID belongs to a currently running Wispr app.
/// Physical/user paste events, other keys and other apps pass through unchanged.
@MainActor
final class WisprPasteGuard {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var wisprPIDs = Set<pid_t>()
    private var blockedUps: [pid_t: Date] = [:]
    private var lastPaste = Date.distantPast
    var onPaste: ((Data) -> Void)?
    var onFailure: ((AutomationError) -> Void)?
    var isHealthy: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
    func refreshPIDs() {
        let known = ["com.electron.wispr-flow", "com.electron.wispr-flow.accessibility-mac-app"]
        wisprPIDs = Set(
            NSWorkspace.shared.runningApplications.filter {
                known.contains($0.bundleIdentifier ?? "") && !$0.isTerminated
            }.map(\.processIdentifier))
    }
    func start() throws {
        stop()
        guard AccessibilitySupport.isTrusted else { throw AutomationError.permission }
        refreshPIDs()
        guard !wisprPIDs.isEmpty else { throw AutomationError.wisprNotRunning }
        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let guardObject = Unmanaged<WisprPasteGuard>.fromOpaque(context).takeUnretainedValue()
            // This tap's source is installed exclusively on the main run loop.
            return MainActor.assumeIsolated { guardObject.filter(type, event: event) }
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else {
            throw AutomationError.guardUnavailable
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard isHealthy else {
            stop()
            throw AutomationError.guardUnavailable
        }
    }
    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        blockedUps.removeAll()
    }
    private func filter(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in self?.onFailure?(.guardUnavailable) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp,
            event.getIntegerValueField(.keyboardEventKeycode) == 9
        else { return Unmanaged.passUnretained(event) }
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        let now = Date()
        if type == .keyUp, let expiry = blockedUps.removeValue(forKey: pid), now < expiry { return nil }
        guard
            PasteGuardPolicy.shouldSuppress(
                keyCode: 9, sourcePID: pid, wisprPIDs: wisprPIDs,
                frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            blockedUps[pid] = now.addingTimeInterval(2)
            if now.timeIntervalSince(lastPaste) > 0.3 {
                lastPaste = now
                // Correlate this exact Wispr paste with a new local record. No clipboard polling,
                // writing, history or payload forwarding. The transient value is kept only to hash.
                let pasteboard = NSPasteboard.general
                let change = pasteboard.changeCount
                guard let text = pasteboard.string(forType: .string),
                    change == pasteboard.changeCount, (try? TextPolicy.validate(text)) != nil
                else {
                    Task { @MainActor [weak self] in self?.onFailure?(.noFreshDictation) }
                    return nil
                }
                let evidence = Data(SHA256.hash(data: Data(text.utf8)))
                // Keep this handler lightweight. It marks the attempt pending immediately,
                // before a later run-loop turn can discard the just-finished record.
                onPaste?(evidence)
            }
        }
        return nil
    }
}

@MainActor
struct ScreenSharingCheck {
    let destination: ScreenSharingDestination?
    let details: [String: String]
    let failure: AutomationError
}

@MainActor
struct ScreenSharingDestination {
    let pid: pid_t
    let window: AXUIElement
    let expectedNames: [String]
    let approvedWindow: ScreenSharingWindowBinding

    static func inspect(expectedNames: [String], approvedWindow: ScreenSharingWindowBinding)
        -> ScreenSharingCheck
    {
        var details: [String: String] = [:]
        func failed(_ error: AutomationError) -> ScreenSharingCheck {
            ScreenSharingCheck(destination: nil, details: details, failure: error)
        }
        let app = NSWorkspace.shared.frontmostApplication
        let bundle = app?.bundleIdentifier ?? "unavailable"
        details["sourceForegroundBundle"] =
            bundle.count <= 128
                && bundle.unicodeScalars.allSatisfy({
                    CharacterSet(
                        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
                    ).contains($0)
                })
            ? bundle : "unrecognized"
        guard let app, app.bundleIdentifier == "com.apple.ScreenSharing" else {
            details["sourceCheck"] = "screen-sharing-not-foreground"
            return failed(.screenSharing)
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.1)
        let focused = AccessibilitySupport.element(root, kAXFocusedWindowAttribute)
        let main = AccessibilitySupport.element(root, kAXMainWindowAttribute)
        let listedWindows = AccessibilitySupport.attribute(root, kAXWindowsAttribute) as? [AXUIElement]
        let windows = listedWindows ?? []
        details["sourceWindowListReadable"] = String(listedWindows != nil)
        details["sourceFocusedWindowReadable"] = String(focused != nil)
        details["sourceMainWindowReadable"] = String(main != nil)
        details["sourceWindowCount"] = String(windows.count)
        details["sourceStandardWindowCount"] = String(
            windows.filter {
                AccessibilitySupport.attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
            }.count)
        guard let window = focused ?? main else {
            details["sourceCheck"] = "window-not-exposed"
            return failed(.screenSharingWindowUnavailable)
        }
        let role = AccessibilitySupport.attribute(window, kAXRoleAttribute) as? String
        let subrole = AccessibilitySupport.attribute(window, kAXSubroleAttribute) as? String
        func safeRole(_ role: String?) -> String {
            guard let role, role.hasPrefix("AX"), role.count <= 64,
                role.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
            else { return "unavailable" }
            return role
        }
        details["sourceWindowRole"] = safeRole(role)
        details["sourceWindowSubrole"] = safeRole(subrole)
        let title = AccessibilitySupport.attribute(window, kAXTitleAttribute) as? String
        let titleMatches =
            title.map { title in expectedNames.contains { PasteGuardPolicy.remoteTitle(title, matches: $0) } }
            ?? false
        details["sourceWindowTitleReadable"] = String(title != nil)
        details["sourceWindowNameMatched"] = String(titleMatches)
        let approvedMatch = approvedWindow.matches(pid: app.processIdentifier, window: window, title: title)
        details["sourceChosenPIDMatched"] = String(approvedWindow.pid == app.processIdentifier)
        details["sourceChosenWindowIdentityMatched"] = String(CFEqual(approvedWindow.window, window))
        details["sourceChosenTitleUnchanged"] = String(title == approvedWindow.originalTitle)
        details["sourceUserChosenWindowMatched"] = String(approvedMatch)
        // The user explicitly maps this window to the authenticated receiver. A display-name
        // alias is allowed; the window reference, original title and owner PID must stay unchanged.
        var matchingWindows = windows.filter { candidate in
            guard AccessibilitySupport.attribute(candidate, kAXRoleAttribute) as? String == kAXWindowRole
            else { return false }
            return approvedWindow.matches(
                pid: app.processIdentifier, window: candidate,
                title: AccessibilitySupport.attribute(candidate, kAXTitleAttribute) as? String)
        }
        if focused != nil, windows.isEmpty, role == kAXWindowRole, approvedMatch {
            matchingWindows = [window]
            details["sourceUsedFocusedWindowWithoutList"] = "true"
        }
        details["sourceMatchingWindowCount"] = String(matchingWindows.count)
        let minimized = AccessibilitySupport.attribute(window, kAXMinimizedAttribute) as? Bool == true
        let mainFlag = AccessibilitySupport.attribute(window, kAXMainAttribute) as? Bool == true
        let candidateMatches = matchingWindows.contains { CFEqual($0, window) }
        let modal = windows.contains {
            AccessibilitySupport.attribute($0, kAXModalAttribute) as? Bool == true
        }
        details["sourceModalWindowPresent"] = String(modal)
        details["sourceCandidateMatchesWindowList"] = String(candidateMatches)
        details["sourceMainWindowFlag"] = String(mainFlag)
        details["sourceMinimized"] = String(minimized)
        guard approvedMatch else {
            details["sourceCheck"] = "chosen-window-changed-or-not-focused"
            return failed(.screenSharingWindowChanged)
        }
        guard
            SourceWindowPolicy.canUse(
                role: role, titleMatches: approvedMatch,
                matchingWindows: matchingWindows.count,
                candidateIsMatchingWindow: candidateMatches,
                hasFocusedWindow: focused != nil,
                mainWindowIsMain: mainFlag,
                windowCount: windows.count, minimized: minimized, modal: modal)
        else {
            details["sourceCheck"] = "window-focus-or-identity-not-verified"
            return failed(.screenSharingWindowUnavailable)
        }
        details["sourceCheck"] = focused == nil ? "matched-main-window" : "matched-focused-window"
        return ScreenSharingCheck(
            destination: Self(
                pid: app.processIdentifier, window: window, expectedNames: expectedNames,
                approvedWindow: approvedWindow),
            details: details, failure: .screenSharing)
    }
    func isCurrent() -> Bool {
        guard let now = Self.inspect(expectedNames: expectedNames, approvedWindow: approvedWindow).destination
        else { return false }
        return pid == now.pid && CFEqual(window, now.window)
    }
}
