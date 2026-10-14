import Testing

@testable import MacRelayCore

@Suite struct SourceWindowTests {
    private func allowed(
        role: String? = "AXWindow", titleMatches: Bool = true, matches: Int = 1,
        sameWindow: Bool = true, focused: Bool = true, main: Bool = false,
        count: Int = 1, minimized: Bool = false, modal: Bool = false
    ) -> Bool {
        SourceWindowPolicy.canUse(
            role: role, titleMatches: titleMatches, matchingWindows: matches,
            candidateIsMatchingWindow: sameWindow, hasFocusedWindow: focused,
            mainWindowIsMain: main, windowCount: count, minimized: minimized, modal: modal)
    }
    @Test func focusedNamedWindowDoesNotDependOnOptionalWindowMetadata() {
        #expect(allowed())
        // A focused window may be exposed even when AXWindows is unavailable.
        #expect(allowed(count: 0))
        // A separate connections browser does not change the identity of the focused receiver window.
        #expect(allowed(count: 2))
    }
    @Test func mainFallbackRequiresOneVerifiedMainWindow() {
        #expect(allowed(focused: false, main: true))
        #expect(!allowed(focused: false, main: false))
        #expect(!allowed(focused: false, main: true, count: 0))
        #expect(!allowed(focused: false, main: true, count: 2))
    }
    @Test func explicitWindowChoiceAllowsAnAliasButRequiresExactLiveIdentity() {
        let alias = "Remote session"
        #expect(!PasteGuardPolicy.remoteTitle(alias, matches: "Example receiver"))
        let bound = SourceBindingPolicy.matches(
            approvedPID: 42, currentPID: 42, sameWindow: true,
            approvedTitle: alias, currentTitle: alias)
        #expect(bound)
        #expect(allowed(titleMatches: bound, count: 2))
        #expect(
            !SourceBindingPolicy.matches(
                approvedPID: 42, currentPID: 43, sameWindow: true,
                approvedTitle: alias, currentTitle: alias))
        #expect(
            !SourceBindingPolicy.matches(
                approvedPID: 42, currentPID: 42, sameWindow: false,
                approvedTitle: alias, currentTitle: alias))
        #expect(
            !SourceBindingPolicy.matches(
                approvedPID: 42, currentPID: 42, sameWindow: true,
                approvedTitle: alias, currentTitle: "Different session"))
        #expect(
            !SourceBindingPolicy.matches(
                approvedPID: 42, currentPID: 42, sameWindow: true,
                approvedTitle: alias, currentTitle: nil))
        #expect(
            !SourceBindingPolicy.matches(
                approvedPID: 42, currentPID: 42, sameWindow: true,
                approvedTitle: "", currentTitle: ""))
    }
    @Test func transientWisprFocusPreservesNewRecordsWithoutAuthorizingOtherApps() {
        #expect(
            SourcePausePolicy.preserveCursor(
                foreground: "com.electron.wispr-flow", hasVerifiedBinding: true, secondsSinceVerified: 2))
        #expect(
            SourcePausePolicy.preserveCursor(
                foreground: "com.apple.ScreenSharing", hasVerifiedBinding: true, secondsSinceVerified: 0.2))
        #expect(
            !SourcePausePolicy.preserveCursor(
                foreground: "com.apple.TextEdit", hasVerifiedBinding: true, secondsSinceVerified: 0.2))
        #expect(
            !SourcePausePolicy.preserveCursor(
                foreground: "com.electron.wispr-flow", hasVerifiedBinding: false, secondsSinceVerified: 0.2))
        #expect(
            !SourcePausePolicy.preserveCursor(
                foreground: "com.electron.wispr-flow", hasVerifiedBinding: true, secondsSinceVerified: 60))
        #expect(
            !SourcePausePolicy.preserveCursor(
                foreground: "com.apple.ScreenSharing", hasVerifiedBinding: true, secondsSinceVerified: 1))
    }
    @Test func incorrectAmbiguousHiddenOrModalWindowsAreRefused() {
        #expect(!allowed(role: nil))
        #expect(!allowed(role: "AXTextArea"))
        #expect(!allowed(titleMatches: false))
        #expect(!allowed(matches: 0))
        #expect(!allowed(matches: 2))
        #expect(!allowed(sameWindow: false))
        #expect(!allowed(minimized: true))
        #expect(!allowed(modal: true))
    }
}
