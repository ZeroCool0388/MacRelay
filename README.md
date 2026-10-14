# MacRelay

**Dictate on your MacBook. Put the words into your Mac mini’s focused text field.**

MacRelay is a small macOS menu bar app for using Wispr Flow through Apple Screen Sharing. The Macs connect directly using a private pairing key and encrypted transfers. MacRelay has no account, cloud relay, analytics or saved text history.

**Automatic mode is experimental.** This branch builds the first automatic Wispr relay. The local tests and build checks do not prove a real spoken dictation works through Screen Sharing. See [validation](docs/VALIDATION.md). The original manual transfer remains available as a fallback.

## Automatic mode

1. Wispr makes a new dictation for Screen Sharing.
2. MacRelay stops Wispr’s usual paste event from reaching the remote session.
3. The mini checks and briefly reserves its focused text field.
4. MacRelay reads the new, completed words from Wispr’s local data and sends them directly to the mini.
5. The mini checks the same field and selection again, inserts once, and checks the result.

Use your usual Wispr dictation key. There is no extra send, copy or paste shortcut.

This uses an **independent, undocumented adapter**, not an official Wispr API. The data-field layout was checked against Wispr Flow 1.6.1147. Wispr updates may break it. If the data, paste event, destination or result cannot be checked, MacRelay stops automatic delivery. It never retries an uncertain insertion.

## Build and open

You need macOS 14 or later and Apple’s developer tools with Swift 6 or later. There are no third-party packages; SQLite, AppKit, Accessibility, Network and CryptoKit come with macOS.

```sh
git clone https://github.com/ZeroCool0388/MacRelay.git
cd MacRelay
# For the experimental automatic version:
git switch codex/automatic-wispr
./scripts/test.sh
./scripts/build-app.sh
```

Move `build/MacRelay.app` into the main **Applications** folder (`/Applications`) and open that installed copy. Quit MacRelay before replacing it with a new build. This makes it available in the standard app picker when adding permissions.

If developer tools are missing, install Apple’s Command Line Tools with `xcode-select --install`, or use Xcode. The scripts handle tool differences between supported versions.

The app appears in the menu bar, without a Dock icon. Build it on each Mac, or copy the built app to a Mac with the same processor architecture. These are locally signed development builds, not notarized public downloads. Building from source is the supported route.

Keep the app in the same location after pairing. These development builds use a signature tied to each build, so an update can require fresh Keychain or Accessibility approval. Click **Open Accessibility settings** in MacRelay to ask macOS for access to the current app, then allow the installed Applications copy. A switch left on from an earlier build is not proof the current process is allowed. You can also open `Package.swift` in Xcode.

## Pair the Macs

1. On the **mini**, choose **Receive**, then **Create pairing code and start**.
2. On the **MacBook**, choose **Send** and select the receiver. A manual local address is also available.
3. Enter the mini’s full `MR1-…` code and click **Verify and pair**. Keep the code private.
4. Allow **Local Network** access and incoming connections when macOS asks.

Bonjour finds nearby receivers. The pairing key verifies the intended receiver. Manual addresses must be `localhost`, a `.local` name, or a private local IP address. The default port is `45821`. Guest Wi-Fi may prevent Macs from connecting.

Pairing keys stay in each Mac’s Keychain without iCloud Keychain syncing. Replacing the mini’s code revokes the old pairing. Receiving starts when you create the code; after reopening the app, start it again.

## Try automatic dictation

Use the experimental version on **both Macs**. Existing pairing keys remain usable.

1. Allow **MacRelay** in **System Settings → Privacy & Security → Accessibility** on both Macs. On newer macOS this permission is called **Device Control and Data Access**. The app includes a button to open that page.
2. On the **mini**, click **Insert dictation automatically**.
3. On the **MacBook**, click **Choose Screen Sharing window**. Check that the receiver name is your mini, choose the window showing it, then click **Relay Wispr from this window**.
4. Keep the chosen Screen Sharing window focused. A separate connections browser is allowed. The window choice is explicit because macOS may expose a different connection label from the visible computer name.
5. Click into a blank **TextEdit** document on the mini, then dictate normally using Wispr on the MacBook.
6. Check the words appear **once**, without any relay, copy or paste action.

Turn off Screen Sharing’s **Share Clipboard** option during this test, so its own sync cannot affect the result. MacRelay does not change that setting for you.

Automatic mode starts **off** each time MacRelay opens. Turning it on ignores earlier Wispr records, including unfinished ones already present. Changing roles, stopping receiving or quitting cancels automatic work. Changing the chosen source window, its title or the destination field during delivery stops the attempt. The window choice is kept only in memory; choose again after quitting the app or opening a new remote session.

A confirmed result means the field’s exposed text matches the expected insertion. Some apps do not expose enough information through Accessibility and are refused. Password fields and known terminal apps are blocked. MacRelay never presses Enter or submits a form.

The receiver prefers the field’s complete editable text through Accessibility’s character-range API when available. It chooses that reader before insertion and checks the result using the same reader. Other fields use their exposed value. Codex’s chat editor has a narrow compatibility rule: differences only in surrounding whitespace may confirm a changed, non-empty complete text result. Words, punctuation, Unicode and internal spacing must still match. The text sent and pasted is unchanged. Other apps require an exact match. An unavailable reader remains unconfirmed.

If a test fails, use **Save test report** on the affected Mac. It saves only check results and counters in the existing iCloud Drive `MacRelay` folder, or on the Desktop if that folder is unavailable. It contains no dictated words, field contents, clipboard contents, keys, audio or login details. Keep reports out of public issues if they include information you want private.

## Clipboard and privacy

The automatic sender does not watch clipboard changes. When stopping a Wispr-generated paste event, it briefly reads that event’s current clipboard text and keeps only a fingerprint to match against a new Wispr dictation. The fingerprint must match one stable, completed dictation. Older unfinished entries or entries with different words do not prevent that unique match. Two matching entries are refused. Consumed and older pending entries cannot be relayed afterward. It never sends an ordinary clipboard item automatically. It opens `~/Library/Application Support/Wispr Flow/flow.sqlite` read-only. It reads metadata and completed text for new Screen Sharing dictations while the mode is enabled. It does not read earlier transcript bodies, audio, screenshots, account data or settings. MacRelay does not change Wispr’s own processing or history settings.

The receiver checks the focused field through Accessibility, temporarily puts the words on the clipboard, sends one paste to the checked app, and restores the previous clipboard items only if its own clipboard write is still present. A newer copy from you or another app is left alone. A clipboard too large or unavailable to preserve safely stops insertion. It does not write the field’s selected-text attribute: some fields report that attribute as writable without completing an insertion.

MacRelay saves role and receiver settings, and pairing keys. Transferred text, field checks and delivery tokens stay in memory. Other software, Wispr’s history, clipboard managers, operating system swap, screenshots and crash reports are outside MacRelay’s control.

See [SECURITY.md](SECURITY.md) for the connection design and limits.

## Manual fallback

With automatic mode off, expand **Manual transfer and pairing** on the sender:

- **Shift + Option + Command + S** sends the current clipboard’s plain text once.
- The mini keeps one received item in memory for up to two minutes.
- **Copy received text**, or **Shift + Option + Command + R**, deliberately changes the mini’s clipboard. Paste normally afterward.
- A second item cannot replace one already waiting. Receiving a manual item does not change the clipboard.

Plain text only, up to 64 KiB per dictation or transfer. Images, files, formatting, multiple remote sessions and internet relay connections are outside this version.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| No receiver | Start receiving; check Local Network permission and Wi-Fi. Try a manual local address. |
| Automatic mode will not start | Update both Macs, allow Accessibility, and enable automatic insertion on the mini first. |
| Screen Sharing check fails | Choose the window showing the paired mini. Use **Show window** to check your choice. Re-select after closing, changing or reconnecting the session. |
| Field cannot be checked | Try a blank TextEdit document. Some apps do not expose editable text or selection. |
| Wispr’s paste is unrecognized | Save the MacBook test report. Automatic transfer is refused to avoid sending the words twice. |
| Insertion is unconfirmed | Check the field before dictating again. MacRelay does not retry. |
| Permission was granted but still fails | Quit and reopen MacRelay. A rebuilt app may need its Accessibility entry renewed. |

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), [the roadmap](docs/ROADMAP.md) and [the protocol](docs/PROTOCOL.md). Preserve the automatic mode’s destination checks, single-attempt delivery, explicit opt-in and lack of saved text history.

[MIT licensed](LICENSE).
