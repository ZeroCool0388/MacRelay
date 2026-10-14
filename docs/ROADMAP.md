# Roadmap

## Primary goal: seamless Wispr dictation

Dictate normally on the MacBook while using Screen Sharing. The words appear once in the mini’s focused text field, without an extra send, copy or paste action.

The manual v0.1 established pairing and local transfer. It does not solve this goal by itself.

## v0.2 experimental: automatic local adapter

Implemented for testing:

- Read-only access to new, completed Wispr records, with an enable-time baseline.
- A narrow blocker for Wispr-generated paste events in Screen Sharing.
- One Screen Sharing session, checked against the paired receiver’s name.
- Authenticated, short-lived, one-use field reservations.
- Focus, value and selection checks before insertion; result verification afterward.
- Checked native paste, with guarded clipboard restoration and read-only result verification.
- Metadata-only test reports, no saved text history and no uncertain-delivery retries.

The Wispr database layout and event behaviour are undocumented. Schema metadata was checked against Wispr Flow 1.6.1147. The user has verified two consecutive confirmed dictations through Screen Sharing into TextEdit, and subsequently into Codex with the same v0.2.6 app on both Macs. These are bounded live tests; see [VALIDATION.md](VALIDATION.md). No official Wispr integration is claimed.

## Next gates

1. Extend the successful two-dictation checks into longer everyday sessions. Independently check clipboard-sync interference and the paste blocker during those sessions.
2. Test rapid dictations, changed focus/selection, ordinary user paste, Unicode, disconnection and Wispr restart/update.
3. Test supported everyday apps individually. Keep unsupported fields blocked rather than inserting blindly.
4. Investigate an official completion signal/API with Wispr. Replace the local adapter if a reliable supported interface becomes available.
5. Improve first setup, connection health and permission guidance after the core dictation path works.

## Before broader distribution

Independent security review; signed and notarized Apple Silicon/Intel downloads; clearer pairing/revocation; a supported-app compatibility list. Configurable two-key shortcuts may improve the manual fallback, but are not a substitute for seamless dictation.

Remote-network support is later work. No cloud relay or persistent MacRelay transcript archive is planned.
