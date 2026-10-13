# Roadmap

## v0.1: explicit transfer

Sender and receiver in one menu bar app. Private pairing, direct encrypted transfer, Bonjour with a local address fallback, global send/copy shortcuts, and one temporary waiting item. No saved text history or automatic clipboard writes.

Before calling this ready for everyday use, finish the two-Mac checklist in [VALIDATION.md](VALIDATION.md).

## v0.2: easier setup

- Review the security protocol independently before broader distribution.
- Add clear, tested reconnect behaviour and visible receiver health.
- Make shortcuts configurable and test their routing through Screen Sharing.
- Add a better first-run guide and a way to forget pairing keys.
- Build signed, notarized downloads for Apple Silicon and Intel.
- Improve the pairing experience without falling back to a guessable PIN or unauthenticated discovery.

## Wispr Flow: verify first

Check current official Wispr documentation and test the supported ways of obtaining the latest transcription. Do not assume there is an API, stable history-file format, completion event, or reliable shortcut.

Start with a user-triggered capture only if it can be verified. Test clipboard restoration, old transcriptions, rapid consecutive dictations, focus changes, and Screen Sharing. Show clearly when capture fails. Never send an old clipboard item silently.

Automatic capture should be opt-in and use a supported completion signal. Avoid continuous clipboard watching and reading private application databases as a default integration.

## Seamless insertion: opt in

After capture is reliable, explore inserting into a chosen receiver app. This will need an explicit mode, destination checks, a clear failure state, and any required Accessibility permission. If the app uses the clipboard temporarily, restore it only when no other app has changed it in the meantime.

Never paste or type into an unknown field, run shell commands, or submit a form as part of text delivery. Keep the v0.1 manual copy-and-paste route available.

## Later

Consider deliberate remote-network support only after local use is proven. Any VPN option needs a reviewed trust model, explicit setup, and tests. No cloud transcription or persistent text archive is planned.
