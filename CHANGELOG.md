# Changelog

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
