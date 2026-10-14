# Roadmap

MacRelay provides explicit local text transfer between a sender Mac and a receiver Mac. Experimental Wispr relay adds checked insertion through Apple Screen Sharing. Manual transfer remains available when automatic mode is unsuitable.

## Current automatic mode

- Read-only access to new, completed Wispr records, with a baseline set when enabling.
- A blocker for recognized Wispr-generated paste events in Screen Sharing.
- One explicitly chosen Screen Sharing session for the paired receiver.
- Authenticated, short-lived, single-use field reservations and token-specific cancellation.
- Focus, value and selection checks before insertion and result verification afterward.
- One native paste, with guarded clipboard restoration only after verified insertion.
- Refusal of unsupported clipboard flavors and overlapping unconfirmed pastes.
- Metadata-only test reports, no saved text history and no uncertain-delivery retries.

The Wispr data layout and paste events are undocumented. The schema was checked against Wispr Flow 1.6.1147. Limited live tests reported two consecutive confirmed dictations into TextEdit and Codex. See [validation notes](VALIDATION.md) for the evidence and limits. No official Wispr integration is claimed.

## Next checks

1. Test longer sessions, rapid dictations, clipboard interference and repeated enable/disable cycles.
2. Test focus and selection changes, ordinary user paste, Unicode, disconnection and Wispr restart or update.
3. Check individual destination apps and keep unsupported fields refused.
4. Investigate a supported Wispr completion interface that could replace the local adapter.
5. Improve setup, connection health and permission guidance based on reproducible reports.

## Distribution

Before broader distribution, obtain independent security review, provide signed and notarized builds for supported architectures, and publish a tested app compatibility list. Configurable shortcuts may improve manual transfer.

Internet relay and a persistent MacRelay transcript archive are outside the current scope.
