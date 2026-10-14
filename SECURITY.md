# Security

MacRelay is a development build; v0.2 automatic mode is experimental. Its protocol has automated checks, but has not had an independent security audit.

## What it protects

The pairing code contains a random 256-bit secret. Both Macs must prove they have that secret before the sender transmits text. Text and acknowledgements are encrypted. A nearby device advertising the same Bonjour name does not become trusted.

Keys are saved as non-synchronizing, device-local Keychain items, accessible when the user's Keychain is unlocked. Receiver and sender keys use separate accounts. Text exists only in temporary dictation, field-verification and transfer buffers, or the manual waiting slot; it is not written to app logs, files, preferences, or Keychain.

The app cannot prevent another program from reading an explicitly copied clipboard item. It cannot promise forensic removal of strings from RAM, swap, crash dumps, screenshots, or third-party clipboard history. Keychain and computer access remain part of the trust boundary.

## Connection design

- `Network.framework` provides TCP and Bonjour. There is no cloud relay or TLS certificate infrastructure.
- The receiver authenticates a fresh 32-byte challenge and X25519 public key with HMAC-SHA256 using the pairing secret.
- The sender verifies that proof, then authenticates the receiver challenge and both ephemeral public keys with its own HMAC-SHA256 proof. Distinct server/client transcript labels prevent proof reflection.
- Both sides derive separate transfer and acknowledgement keys from ephemeral X25519 agreement using HKDF-SHA256. The authenticated handshake transcript is bound into derivation and AES-GCM associated data.
- Text and acknowledgement records use AES-GCM with random nonces. The pairing code and plaintext text never travel on the wire.
- Each connection processes one transfer or pairing probe and then closes. A captured transfer cannot be decrypted or accepted in another fresh session.
- Acknowledgements must match the transfer ID and kind. The app never automatically retries after an uncertain result.

This is a small application protocol using standard CryptoKit primitives, not a reviewed implementation of TLS or Noise. Independent protocol review is a roadmap item before a broader release.

## Limits and revocation

One pairing secret authorizes anyone who possesses it. It is not tied to a hardware identity. Protect the code while moving it between Macs. No short PIN, unauthenticated network pairing, or cloud pairing fallback is provided. Replacing the receiver code revokes the previous secret and cancels existing sessions.

The app restricts connections to private, link-local, or loopback IP addresses. Manual host names must be `localhost` or end in `.local`. Private addressing does not prove that two devices are physically on the same LAN; VPNs and network routing can connect private networks. Do not forward the listening port to the internet.

Bonjour service names, addresses, packet lengths, and timing are visible to the network. The generic advertisement avoids using the personal computer name. Peer-to-peer Wi-Fi is not enabled.

The receiver allows at most four concurrent connections, each with a ten-second deadline. Frames are bounded to 512 KiB, handshake records to 2 KiB, and text to 64 KiB in UTF-8. These limits bound work; they do not prevent denial of service by a hostile network peer.

There is no persistent deduplication ledger. The one-message-per-session rule prevents network replay within a session, while fresh session keys prevent cross-session replay. If a valid sender deliberately sends the same text again after the waiting slot has cleared, it is a new transfer. Check the receiver after an unconfirmed delivery.

## Automatic insertion

Automatic mode is explicitly enabled on both Macs and starts off after relaunch. A receiver capability check prevents a new sender from treating a v0.1 receiver as an automatic inserter. Receiver names are carried only in authenticated encrypted acknowledgements, not Bonjour advertisements. The user explicitly maps a Screen Sharing window to that receiver. Its owner PID, AX window reference and original title must stay the same. The selection is not persisted. Machine/connection names can be aliases, so display-name equality is not used as an authentication substitute.

The sender uses an undocumented Wispr database adapter opened with SQLite READONLY. It baselines the maximum row ID when enabled, reads bounded new-record metadata and completed bodies for Screen Sharing only, and ignores earlier transcript bodies. Records that appear outside the checked Screen Sharing window are skipped. Database replacement, schema mismatch, ambiguity and missing completed text stop delivery.

The event blocker filters V events originating from currently running known Wispr bundle IDs while Screen Sharing is foreground. Other keyboard events pass through; they are not stored. A detected, blocked Wispr paste attempt is mandatory before relaying. At that event only, the sender hashes bounded plain clipboard text and requires the new completed Wispr record to match. The clipboard value is never used as the relay payload. The fingerprint must select exactly one completed record, stable for at least 250 milliseconds. Other unfinished or different-text entries do not make that match ambiguous; two matching completions still stop delivery. After consuming a match, older pending entries are retired so they cannot reappear as a later dictation. A changed/empty clipboard, mismatch or ambiguous match refuses transfer; there is no general clipboard watcher. Unknown insertion paths do not trigger a relay. This is a compatibility guard, not a security boundary against another malicious local process. Real event-source behaviour still needs live validation.

The receiver grants a random UUID token only after checking an editable non-protected field. It keeps a hash of that field’s text, its selection, app, window and field identity. A token expires after 15 seconds and is consumed before any insertion attempt. A mismatched focus, changed text/selection, expired or consumed token is refused. Stopping/role changes clear reservations. There is one live reservation and one insertion at a time.

The sender never retries. The receiver uses Accessibility to reserve and recheck the field, then posts one native paste to the checked process. It does not attempt an Accessibility selected-text write. Keyboard events use a private source with Command as their only modifier. Password fields, unsupported fields and known terminal apps are refused; embedded terminals and unusual controls require separate compatibility review. The app never sends Enter. The operating system does not offer an atomic focus-check-and-write transaction, so final app behaviour remains part of the trust boundary.

When the field supports `AXNumberOfCharacters` and `AXStringForRange`, the receiver captures its complete bounded text, checks stable character counts and rejects partial responses. The reservation includes this text’s fingerprint alongside the exposed value and selection. It pins the text reader before paste and never switches readers after an uncertain result. Read-only verification polls for up to 1.5 seconds between bounded Accessibility calls; it never repeats the paste. Diagnostic comparisons remain booleans only and do not authorize confirmation.

Exact complete-text matching is the default. For the locally verified Codex bundle ID `com.openai.codex`, a full-range reader may also confirm a difference only in leading/trailing whitespace and line breaks. The expected non-whitespace text must be non-empty and different from the pre-insertion content, and its UTF-8 bytes must match after removing only surrounding whitespace. Internal spacing, punctuation, Unicode composition, added/missing words and duplicates remain failures. The wire/clipboard payload is never trimmed. The report distinguishes an exact match from this chat-formatting match. This is an editor-compatibility assumption, not proof that every destination preserves intended boundary whitespace; other apps and value-only readers do not get this exception.

The paste transaction accepts only an empty clipboard or items offering solely the plain-text flavor. It checks every item's flavor names before requesting any data, refusing rich text, images, PDFs, files and custom flavors rather than loading them. Retained text data is limited to 8 MiB; plain-text values are loaded before this size check because the pasteboard API does not expose their length first. It adds a private marker to its temporary write and restores the snapshot only when both marker and change count still match, and the paste has either not been posted or insertion is verified. An unconfirmed paste leaves the temporary payload available because the destination may still have Cmd-V queued; its marker prevents another automatic paste from replacing it. An identical-text replacement is refused before posting because unchanged field contents cannot confirm clipboard consumption. New clipboard writes are left alone. Clipboard managers or OS sharing may observe temporary clipboard contents even if they are later restored. Disable Screen Sharing clipboard sync during validation.

Test reports are written only when explicitly requested. They contain diagnostic counters, schema/permission results and status, never transferred text, field values, tokens or pairing secrets. Wispr’s own stored history and cloud processing settings remain unchanged.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository when available. Do not put pairing codes, real transferred text, credentials, or sensitive screenshots in a public issue. If private reporting is unavailable, open a minimal issue requesting a private contact route, without the exploit or private data.
