# Contributing

Small, focused contributions are welcome. Open an issue before a large feature or protocol change.

## Work locally

Use macOS 14 or later and Apple developer tools with Swift 6 or later. No third-party packages are required. Linux cannot build the AppKit app or run the full test suite.

```sh
./scripts/test.sh
./scripts/build-app.sh debug
open build/MacRelay.app
```

For a UI preview without Keychain access, discovery, shortcuts or clipboard writes:

```sh
open build/MacRelay.app --args --preview
```

Preview buttons that would connect or copy text are inactive. Quit the preview before opening the app normally. To check the archive and included installation guide, run `./scripts/package-app.sh` after building.

## Keep these rules

- Do not put transferred text, field contents or pairing secrets in logs, preferences, test fixtures or issue reports.
- Keep manual receiving separate from explicit clipboard copy. Automatic insertion requires opt-in and a checked destination.
- Preserve clipboard ownership checks. Restore after a verified paste or before posting; leave an unconfirmed paste's payload available and preserve newer copies.
- Do not load binary clipboard flavors to decide whether they are too large. Refuse unsupported clipboard items before reading their data.
- Do not replace a waiting inbox item or retry an uncertain transfer automatically.
- Authenticate both peers, consume tokens before insertion and cancel matching reservations when an attempt is abandoned.
- Keep frames, text sizes, connections and deadlines bounded, and document limits that apply only after a read.
- Describe undocumented adapters as experimental. Do not claim an official Wispr integration or a successful live path without evidence.

## Before a pull request

Run `./scripts/test.sh` and `./scripts/build-app.sh` on macOS. Add meaningful tests for changed behaviour. For UI, clipboard, permissions or network changes, record the relevant two-Mac checks from [the validation guide](docs/VALIDATION.md). State what you could not test.

Use four-space indentation and existing Swift patterns. Keep dependency additions and architectural changes out of unrelated fixes. Check documentation and UI wording for assumptions about particular Mac models, account names, local paths or network names.

## Reports

Use the existing issue templates. Include app and macOS versions, processor architectures, sender and receiver roles, and reproducible steps with invented sample text. Do not include pairing codes, credentials or private transcriptions. Remove private device names and network addresses from reports. Follow [SECURITY.md](SECURITY.md) for vulnerabilities instead of posting exploit details publicly.
