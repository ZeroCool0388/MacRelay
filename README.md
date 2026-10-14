# MacRelay

MacRelay is a macOS menu bar app that sends plain text directly between two Macs on a local network. One Mac sends text and the other receives it. Both roles are included in the same app.

Use it when you work across two Macs and want explicit text transfer without an account, cloud relay or saved text history. Manual transfer sends clipboard text on request. An experimental mode can relay new Wispr Flow dictation into a checked text field while you use Apple Screen Sharing.

## Requirements

- macOS 14 or later on both Macs.
- Apple developer tools with Swift 6 or later to build from source.
- A local network that allows the Macs to connect directly.
- Wispr Flow on the sender and Apple Screen Sharing configured separately for automatic dictation. Neither is needed for manual transfer.

There are no third-party package dependencies. AppKit, Accessibility, Network, CryptoKit and SQLite are provided by macOS. The app targets macOS; Linux cannot build the AppKit app or run the full test suite.

## Build and install

Download or clone this repository, then run these commands from its directory:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/package-app.sh
```

Install Apple Command Line Tools with `xcode-select --install` if needed, or use Xcode with Swift 6 or later. You can also open `Package.swift` in Xcode. The build script uses a release configuration by default; pass `debug` for a debug build.

The build creates `build/MacRelay.app`. The package script uses that existing app to create `build/MacRelay-<version>-macOS.zip` and a `.sha256` checksum file. The archive includes the app, an installation guide and the licence. To choose another output directory, pass it to `./scripts/package-app.sh`.

Quit any running copy, move the app into `/Applications`, then open the installed copy. MacRelay appears in the menu bar and has no Dock icon. Install the same app version on both Macs. A package contains the architecture of the Mac that built it, so use a compatible build for each Mac; the scripts do not create a universal binary.

Builds use an ad-hoc local signature. They are not Developer ID signed or notarized. Keep the app in a consistent location. Replacing a build may require renewed Keychain or Accessibility approval. See [the installation guide](docs/INSTALL.md) for updates and packaged builds.

## First-time setup

Choose which Mac will send and which will receive. You can change roles later.

### Receiver Mac

1. Open MacRelay and choose **Receive**.
2. Click **Create pairing code and start**. Receiving starts and a private pairing code appears.
3. Transfer the full code to the sender through a route you trust. Keep it out of public messages and issue reports.
4. Allow Local Network access and incoming connections if macOS asks.

### Sender Mac

1. Open MacRelay and choose **Send**.
2. Select the receiver in the nearby list. If discovery fails, choose **Enter local address manually** and enter its local address and port.
3. Enter the full pairing code and click **Verify and pair**.
4. Allow Local Network access if macOS asks.

Bonjour discovers nearby receivers. Pairing verifies the receiver using the shared secret, rather than trusting its advertised name. Manual addresses must be a local host name ending in `.local`, `localhost`, or a private, link-local or loopback IP address. The default receiver port is `45821`.

Pairing keys stay in each Mac's local Keychain and do not sync through iCloud Keychain. After reopening the receiver app, click **Start receiving**. Replacing its pairing code revokes the old pairing; pair the sender again with the new code.

## Manual text transfer

1. Copy plain text on the sender. Turn automatic mode off if it is enabled.
2. Click **Send clipboard text**, or press **Shift + Option + Command + S**. Paired senders have these controls under **Manual transfer and pairing**.
3. On the receiver, click **Copy received text**, or press **Shift + Option + Command + R**.
4. Paste into the destination app yourself.

Receiving manual text does not change the clipboard. The receiver holds one item in memory for up to two minutes. Another item cannot replace it while it is waiting. Copy or discard the item before sending another. Each transfer is limited to 64 KiB of plain text in UTF-8; files, images and formatting are not transferred.

## Permissions

**Local Network:** allow MacRelay on both Macs when prompted. If connections fail, check the Local Network entry in System Settings, the firewall and network isolation settings. Guest networks may block discovery or direct connections.

**Accessibility:** automatic dictation requires MacRelay to have this permission on both Macs. Use **Open Accessibility settings**, then allow the installed app under **System Settings > Privacy & Security > Accessibility**. Some macOS versions call this **Device Control and Data Access**. Manual transfer and its global shortcuts do not require Accessibility.

An enabled switch for an older build does not prove that the current process is allowed. After replacing the app, quit and reopen it, request permission for the current copy and renew the entry if needed.

## Experimental automatic Wispr insertion

This mode uses an independent, undocumented adapter to Wispr Flow's local data. It is not an official Wispr integration. The data layout was checked against Wispr Flow 1.6.1147; later versions may break it. Limited two-Mac tests have reported successful consecutive dictations in TextEdit and Codex. They do not establish reliability across apps or longer sessions. See [validation notes](docs/VALIDATION.md).

1. Pair the Macs and start receiving. Allow Accessibility on both Macs.
2. Open the receiver's desktop in Apple Screen Sharing on the sender. Turn off Screen Sharing's **Share Clipboard** option to avoid interference from its clipboard sync.
3. On the receiver, click **Insert dictation automatically**.
4. On the sender, click **Choose Screen Sharing window**. Check the displayed receiver, choose the window showing it, then click **Relay Wispr from this window**.
5. Keep that window focused. Click a blank TextEdit document on the receiver and dictate using Wispr on the sender.
6. Check that the words appear once before trying your usual destination app.

MacRelay blocks a recognized Wispr paste event, matches it to one new completed dictation, reserves the receiver's focused field, sends the text and attempts one checked paste. It checks the field, selection and result through Accessibility. It never presses Enter or submits a form.

Automatic mode starts off after each launch. Earlier dictations are ignored when enabling it. The window choice stays in memory and must be made again after reopening the app or creating a new remote session. Focus changes, changed fields, ambiguous records, missing permissions and unconfirmed results stop delivery. Password fields, known terminal apps and fields that cannot be checked are refused. MacRelay never retries an uncertain insertion.

Automatic insertion temporarily uses the receiver's clipboard. It requires an empty or plain-text-only clipboard; rich text, images, PDFs, files and custom flavors are refused before their data is loaded. Retained plain text is limited to 8 MiB, checked after reading. After verified insertion, the previous clipboard is restored only if MacRelay still owns the temporary write. Newer copies are left alone. If insertion is unconfirmed, the dictation stays on the clipboard so a queued paste cannot read the previous copy. Another automatic paste is refused while that temporary item remains. Check the destination and any pending paste before replacing it.

Verification normally requires an exact text result. Codex's complete editable-text reader has a narrow exception for surrounding whitespace in changed, non-empty content. Words, punctuation, Unicode and internal spacing must still match. This does not prove compatibility with other editors.

## Security and privacy

- Text and acknowledgements are encrypted. Both Macs authenticate using the private pairing secret.
- Connections are restricted to local address ranges. There is no internet relay, account or analytics service. Do not expose the receiver port to the internet.
- MacRelay saves settings and pairing keys, but no transferred-text history. Manual waiting text, reservations and field checks stay in memory.
- Other apps, clipboard managers, operating system sharing, Wispr's own history, swap and crash reports are outside MacRelay's control.
- The protocol has automated tests but has not had an independent security audit. Automatic mode remains experimental.

Read [SECURITY.md](SECURITY.md) for the protocol, limits, revocation and private vulnerability reporting.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| No nearby receiver | Start receiving, allow Local Network on both Macs and check network isolation. Try a manual local address. |
| Connection fails | Check the receiver port, firewall and pairing code. Install compatible versions on both Macs. |
| Pairing was replaced | Enter the receiver's new code and verify pairing again. |
| Shortcut does nothing | Use the matching button. Check for conflicts with another app's shortcuts. |
| Automatic mode will not start | Allow Accessibility, run Wispr on the sender and enable receiver insertion first. |
| Screen Sharing check fails | Choose the window showing the paired receiver. Use **Show window** to check it. Choose again after reconnecting or changing the session. |
| Clipboard is refused | Check any pending paste, then copy a small plain-text-only item on the receiver. Rich or binary clipboard items are unsupported. |
| Field cannot be checked | Try a blank TextEdit document. Some apps do not expose editable text or selection. |
| Wispr data or paste is unrecognized | The adapter may be incompatible with that Wispr version. Use manual transfer and save a test report. |
| Insertion is unconfirmed | Check the destination and pending paste before dictating again. MacRelay does not retry or restore the previous clipboard. |
| Permission still fails after an update | Quit and reopen MacRelay and renew permission for the installed copy. |

**Save test report** writes check results and counters to an existing MacRelay folder in iCloud Drive, or to the Desktop if that folder is unavailable. It saves no dictated words, field contents, clipboard contents, keys, audio or login details. Review reports before sharing them and remove private device or network details.

## Contributing and licence

Read [CONTRIBUTING.md](CONTRIBUTING.md), [the roadmap](docs/ROADMAP.md) and [the protocol](docs/PROTOCOL.md). Use the existing issue templates for bug reports and feature requests. Keep private data out of public reports.

MacRelay is licensed under the [MIT licence](LICENSE), copyright 2026 MacRelay contributors.
