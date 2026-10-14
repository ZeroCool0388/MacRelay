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
                Task { @MainActor [weak self] in self?.onPaste?(evidence) }
            }
        }
        return nil
    }
}

@MainActor
struct ScreenSharingDestination {
    let pid: pid_t
    let window: AXUIElement
    let expectedNames: [String]
    static func capture(expectedNames: [String]) throws -> Self {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier == "com.apple.ScreenSharing"
        else {
            throw AutomationError.screenSharing
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = AccessibilitySupport.element(root, kAXFocusedWindowAttribute),
            let windows = AccessibilitySupport.attribute(root, kAXWindowsAttribute) as? [AXUIElement],
            windows.filter({
                AccessibilitySupport.attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
            }).count == 1,
            AccessibilitySupport.attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
        else {
            throw AutomationError.screenSharing
        }
        guard let title = AccessibilitySupport.attribute(window, kAXTitleAttribute) as? String,
            expectedNames.contains(where: { PasteGuardPolicy.remoteTitle(title, matches: $0) })
        else { throw AutomationError.screenSharing }
        return Self(pid: app.processIdentifier, window: window, expectedNames: expectedNames)
    }
    func isCurrent() -> Bool {
        guard let now = try? Self.capture(expectedNames: expectedNames) else { return false }
        return pid == now.pid && CFEqual(window, now.window)
    }
}
