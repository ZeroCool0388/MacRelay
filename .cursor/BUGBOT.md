# Review rules for MacRelay

MacRelay is a macOS menu bar app that relays text from a sender Mac to a receiver Mac on the local network.

Focus on:
- Clipboard safety: never leave a user's clipboard overwritten, restored at the wrong moment, or loaded without a size bound.
- Insertion permits and reservations: every failure path must clear or cancel armed state.
- Network listener and connection failures, including Local Network permission loss.
- Thread safety between Network.framework callbacks and the main actor.
- No personal names, hostnames, paths or emails in code, docs or test fixtures.

Skip style nits that SwiftFormat or the compiler would catch.
