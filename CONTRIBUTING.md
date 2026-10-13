# Contributing

Small, focused contributions are welcome. Open an issue before a large feature or protocol change.

## Work locally

Use macOS 14+ and Swift 6+. No third-party packages are required.

```sh
./scripts/test.sh
./scripts/build-app.sh debug
open build/MacRelay.app
```

For a UI-only preview that does not read Keychain, start discovery, register shortcuts, or write the clipboard:

```sh
open build/MacRelay.app --args --preview
```

Preview buttons that would create a connection or copy text are inactive. Quit the preview before opening the normal app.

## Keep these rules

- No transferred text or pairing secrets in logs, preferences, files, fixtures from real users, or issue reports.
- Receiving must not change the clipboard. Sending and copying must remain explicit actions.
- Do not replace an unexpired pending item. Do not retry an unconfirmed transfer automatically.
- Authenticate the receiver before transmitting text, and the sender before accepting it.
- Keep frames, text sizes, connections, and deadlines bounded.
- Do not add a Wispr integration claim without an official source and a reproducible check.

## Before a pull request

Run `./scripts/test.sh` and `./scripts/build-app.sh`. Add meaningful tests for changed behaviour. For UI, clipboard, permissions, or network changes, record the relevant two-Mac checks from [VALIDATION.md](docs/VALIDATION.md). State what you could not test.

Use four-space indentation and existing Swift patterns. Keep dependency additions and architectural changes out of unrelated fixes.

## Reports

Include the app version, macOS version, which Mac was sending, and the steps to reproduce. Use invented sample text. Remove local addresses or device names if they are private. Use the private route in [SECURITY.md](SECURITY.md) for vulnerabilities.
