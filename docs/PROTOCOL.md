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

5. Sender → receiver: AES-GCM combined representation of JSON `Transfer {id, kind, text}` under the transfer key. Associated data is `SHA256(T) || "transfer"`.
6. Receiver → sender: AES-GCM combined representation of JSON `Acknowledgement {id, status}` under the acknowledgement key. Associated data is `SHA256(T) || "ack"`.

CryptoKit's combined representation contains the random 12-byte nonce, ciphertext, and 16-byte tag. Each encryption chooses a new nonce. The sender verifies the acknowledgement ID and its allowed status for the transfer kind.

Kinds:

- `probe`: `text` must be absent. Receiver responds `paired`; it does not change a live pending item or extend its expiry.
- `text`: `text` must be non-empty and at most 65,536 UTF-8 bytes. Receiver responds `accepted` only after placing it in the volatile inbox, or `busy` if an unexpired item is already waiting.

A connection reads only one encrypted transfer. It closes after acknowledgement or error. The receiver must never accept an encrypted transfer twice on the same connection. Cross-session ciphertext and client-proof replay fail because the challenge, ephemeral key pairs, and derived keys change.

The inbox expires after 120 seconds and clears on explicit copy/discard, receiver stop, role switch, or app exit. There is no automatic resend. Successful acknowledgement proves receipt into memory, not that the text has been copied or inserted into another app.

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
