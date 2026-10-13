# Security

MacRelay v0.1 is a development build. Its protocol has automated checks, but has not had an independent security audit.

## What it protects

The pairing code contains a random 256-bit secret. Both Macs must prove they have that secret before the sender transmits text. Text and acknowledgements are encrypted. A nearby device advertising the same Bonjour name does not become trusted.

Keys are saved as non-synchronizing, device-local Keychain items, accessible when the user's Keychain is unlocked. Receiver and sender keys use separate accounts. Text exists only in a single waiting slot and temporary transfer buffers; it is not written to app logs, files, preferences, or Keychain.

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

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository when available. Do not put pairing codes, real transferred text, credentials, or sensitive screenshots in a public issue. If private reporting is unavailable, open a minimal issue requesting a private contact route, without the exploit or private data.
