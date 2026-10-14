# Changelog

## 0.2.5 — Codex chat formatting

- Permit surrounding-whitespace formatting only for Codex’s complete editable-text reader.
- Keep words, punctuation, Unicode and internal spacing exact; refuse unchanged or whitespace-only results.
- Report exact versus chat-formatting confirmation without saving text.
- Request the current app’s macOS permission when the user clicks setup/automatic-mode buttons.
- Document installation in the main Applications folder and permission renewal for development updates.

The v0.2.4 report found matching text after surrounding-whitespace comparison. The sender still stopped because verification required an exact field representation. This update targets that difference; repeated Codex dictation still needs a live test. TextEdit’s exact verification and the Air’s protocol remain unchanged.

## 0.2.4 — editable-text confirmation

- Check complete editable text through the Accessibility character-range API when the field supports it.
- Pin that text reader before pasting; keep exact matching and reject unavailable, partial or changed results.
- Allow up to 1.5 seconds for the app’s text representation to update, without repeating the paste.
- Add metadata-only reader and mismatch comparisons; formatting diagnostics never count as success.

The user confirmed two consecutive dictations in TextEdit with the v0.2.3 receiver. Codex’s chat field received a paste but failed the exposed-value confirmation and disabled the sender. This update adds a compatible text reader; the Codex live test is still pending. The Air’s v0.2.2 remains compatible.

## 0.2.3 — receiver insertion

- Use one checked native paste instead of relying on a writable selected-text attribute.
- Keep generated shortcut modifiers separate from remote input and dictation keys.
- Preserve the clipboard until verification completes; never replace a newer copy.
- Record the insertion stage, verification reason and clipboard restoration as metadata only.
- Add receiver transaction checks for delayed verification, focus changes, uncertain results and newer copies.

The v0.2.2 sender reached the receiver, which reported an unconfirmed direct insertion. This update changes the receiver; an Air running v0.2.2 remains compatible. Real dictation is still awaiting a successful live test.

## 0.2.2 — explicit source window

- Show the authenticated receiver’s computer name during source setup.
- Let the user explicitly choose and show the Screen Sharing window mapped to that receiver.
- Track the chosen window’s process, identity and original title instead of assuming its name equals the receiver’s computer name.
- Keep the window choice in memory only; changed/closed windows require a new choice.

The v0.2.1 live report identified the machine/window name comparison as the blocker. New automated checks do not replace the remaining live dictation test.

## 0.2.1 — Screen Sharing window checks

- Verify the focused receiver window without requiring the optional “standard window” label.
- Use a single verified main window when the focused-window attribute is unavailable.
- Briefly wait for source focus to return from Wispr before arming the receiver.
- Mark a blocked Wispr attempt pending immediately, so a later focus check cannot discard its new record first.
- Show when automatic mode is paused and include the exact failing window check in metadata-only reports.

The first v0.2 live test detected and blocked a Wispr paste but rejected the source window. The complete live dictation path is still unproven.

## 0.2.0 — experimental automatic dictation

- New Wispr dictation can be relayed without a separate send/copy/paste gesture.
- Opt-in, read-only Wispr adapter with no replay of earlier records.
- Narrow Wispr paste blocker to prevent duplicate Screen Sharing insertion.
- Receiver field reservations, focus/selection checks and one insertion attempt.
- Direct insertion with a guarded clipboard fallback and result verification.
- Metadata-only reports for the upcoming two-Mac test.

Wispr’s database and paste behaviour are undocumented. The live two-Mac dictation test is still pending; this is not a proven public release.

## 0.1.0 — initial development version

- Native SwiftUI menu bar app with Send and Receive roles.
- Explicit clipboard send and receiver copy shortcuts, with button equivalents.
- Private pairing codes, Keychain storage, and per-connection authenticated encryption.
- Bonjour discovery and manual local-address configuration.
- One in-memory waiting item, a two-minute expiry, and no saved text history.
- Bounded transport, verified acknowledgements, and no automatic resend.
- Build script, automated checks, and a two-Mac validation guide.

Direct Wispr integration and automatic insertion are not included.
