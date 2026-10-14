# Protocol v1

This document describes the implemented protocol, rather than a future integration.

## Transport

Direct TCP; default receiver port `45821`. Bonjour service `_macrelay._tcp` in `local.`. IPv4 private/link-local/loopback and IPv6 unique-local/link-local/loopback sources are accepted, including mapped private IPv4 addresses. Public sources are rejected before handshake.

Every frame starts with a four-byte unsigned big-endian payload length. Length zero and values above 524,288 are rejected before allocation. Handshake frames and acknowledgement frames are capped at 2,048 bytes. Reads assemble partial TCP headers and bodies. A session has a ten-second deadline and the receiver caps concurrency at four sessions.

## Pairing

`MR1-` followed by the canonical unpadded base64url encoding of 32 random bytes. The code is shared out of band. The app parses exact-length canonical codes and saves them in local, non-synchronizing Keychain items. No secret is sent as a network field.

## Handshake

Each receiver connection creates a new X25519 key pair and random 32-byte challenge. Data fields in handshake JSON use JSONEncoder's base64 representation.

1. Receiver → sender: JSON `ServerHello {version: 1, challenge, publicKey, proof}`.
2. Sender verifies version and lengths, then verifies `proof`:
   `HMAC-SHA256(pairingKey, "MacRelay/v1/server\0" || challenge || serverPublicKey)`.
3. Sender creates a new X25519 key pair and sends JSON `ClientHello {publicKey, proof}`.
4. Receiver verifies lengths and sender proof:
   `HMAC-SHA256(pairingKey, "MacRelay/v1/client\0" || challenge || serverPublicKey || clientPublicKey)`.

All concatenated public keys and challenges are exactly 32 bytes. The labels include the shown terminating zero byte. The client transcript is called `T` below.

Both sides perform X25519 agreement. They derive two 32-byte keys using HKDF-SHA256 with `salt = SHA256(T)` and separate `info` strings `MacRelay/v1/transfer` and `MacRelay/v1/ack`.

## Encrypted records

5. Sender → receiver: AES-GCM combined representation of JSON `Transfer {id, kind, text?, token?}` under the transfer key. Associated data is `SHA256(T) || "transfer"`.
6. Receiver → sender: AES-GCM combined representation of JSON `Acknowledgement {id, status, token?, capabilities?, receiverNames?}` under the acknowledgement key. Associated data is `SHA256(T) || "ack"`.

CryptoKit's combined representation contains the random 12-byte nonce, ciphertext, and 16-byte tag. Each encryption chooses a new nonce. The sender verifies the acknowledgement ID and its allowed status for the transfer kind.

Kinds:

- `probe`: `text` must be absent. Receiver responds `paired`; it does not change a live pending item or extend its expiry.
- `text`: `text` must be non-empty and at most 65,536 UTF-8 bytes. Receiver responds `accepted` only after placing it in the volatile inbox, or `busy` if an unexpired item is already waiting.

Experimental optional kinds:

- `arm`: no text or token. With automatic insertion enabled, reserve the checked focused field and return `armed` with a fresh UUID token. Otherwise return `rejected`.
- `cancel`: no text, plus a reservation token. Clear only the matching reservation and return `accepted`, including when it is already gone. Cancellation is allowed without Accessibility access and cannot cancel a newer token.
- `insert`: non-empty validated text plus the reservation token. Consume a matching unexpired token **before** attempting insertion; check the destination again. Return `inserted` only after destination-text verification, `rejected` when refused before an attempt, or `unconfirmed` after an unverified attempt. Verification is exact by default. Codex’s full editable-text reader may accept boundary-whitespace formatting for changed, non-empty content; words, punctuation, Unicode and internal spacing remain exact.

New receivers advertise `wispr-insertion-v1` in a `paired` acknowledgement only when automatic insertion is enabled and Accessibility is available. Optional receiver names let the sender display the authenticated receiver when the user chooses a source Screen Sharing window. These values are encrypted. Existing v0.1 probes/clipboard messages remain compatible; old receivers do not advertise the capability, so new senders refuse automatic mode. Unknown kinds are rejected.

Reservations last 15 seconds. One reservation and one insertion may be live. Tokens and field fingerprints are never persisted. No automatic retry follows a rejected or uncertain result; enabling again establishes a new Wispr baseline.

A connection reads only one encrypted transfer. It closes after acknowledgement or error. The receiver must never accept an encrypted transfer twice on the same connection. Cross-session ciphertext and client-proof replay fail because the challenge, ephemeral key pairs, and derived keys change.

The inbox expires after 120 seconds and clears on explicit copy/discard, receiver stop, role switch, or app exit. There is no automatic resend. For manual `text`, successful acknowledgement proves receipt into memory. For `insert`, `inserted` means the pinned destination-text reader matched the expected single insertion under the receiver’s documented editor rule; it does not mean a form was submitted or boundary whitespace was preserved by a rich editor.

## Code map

| Area | Source |
| --- | --- |
| Pairing, handshake, encryption, framing | `Sources/MacRelayCore/Protocol.swift` |
| Local address policy | `Sources/MacRelayCore/LocalAddress.swift` |
| Waiting slot and expiry | `Sources/MacRelayCore/Inbox.swift` |
| TCP sender/receiver and Bonjour | `Sources/MacRelayTransport/RelayTransport.swift` |
| UI, clipboard actions, roles | `Sources/MacRelayApp/RelayModel.swift` |
| Keychain storage | `Sources/MacRelayApp/KeychainStore.swift` |
| Global shortcuts | `Sources/MacRelayApp/GlobalHotKeys.swift` |

Apple references: [CryptoKit](https://developer.apple.com/documentation/cryptokit), [SharedSecret](https://developer.apple.com/documentation/cryptokit/sharedsecret), [Network](https://developer.apple.com/documentation/network), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra).
