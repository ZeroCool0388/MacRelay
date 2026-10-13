# MacRelay

**Send text between your Macs, without relying on Screen Sharing's clipboard.**

MacRelay is a small macOS menu bar app. Copy text on your MacBook, send it with a shortcut, then copy and paste it on your Mac mini.

The two Macs connect directly. There is no account, cloud service, analytics, or saved text history.

**v0.1 is an early build.** It supports manual clipboard transfer. Automatic Wispr Flow capture and automatic typing into other apps are future work. It has not yet completed a hands-on test between two physical Macs using Screen Sharing. See [validation](docs/VALIDATION.md).

## What it does

- Send the current clipboard text with **Shift + Option + Command + S**.
- Find a receiver on the local network using Bonjour, or enter its local address.
- Verify both Macs using a private pairing code and encrypt each transfer.
- Keep one received item in memory for up to two minutes.
- Copy received text with a button or **Shift + Option + Command + R**, then paste normally.
- Refuse a new item while one is waiting, so text is never silently replaced.

Receiving does **not** change the clipboard. Sending does **not** change the sender's clipboard. Only **Copy received text** and **Copy code** write to it, when you request them.

## Build and open

You need macOS 14 or later and Apple's developer tools with Swift 6 or later. The project has no third-party dependencies.

Check your tools:

```sh
xcode-select -p
swift --version
```

If tools are missing, install Apple's Command Line Tools with `xcode-select --install`, or use Xcode. Then:

```sh
git clone https://github.com/ZeroCool0388/MacRelay.git
cd MacRelay
./scripts/test.sh
./scripts/build-app.sh
open build/MacRelay.app
```

The scripts handle differences between Apple's Command Line Tools and Xcode, including test-runner paths in newer Swift versions.

The app appears in the menu bar, without a Dock icon. Build it on each Mac, or copy the built app to another Mac with the same processor architecture. The default build is for the Mac you build on; it is not a universal binary.

This is a locally signed development build, not a notarized public download. Building from source is the supported route for v0.1. Keep the app in the same location after pairing; rebuilding or moving a development build can trigger a Keychain permission prompt.

You can open `Package.swift` in Xcode to work on the source. The script above creates the runnable `.app` bundle with its menu bar and local network settings.

## First setup

1. On the **Mac mini**, open MacRelay and choose **Receive**.
2. Click **Create pairing code and start**. Keep that code private. It hides when the panel closes or after two minutes.
3. On the **MacBook**, choose **Send**. Select the nearby receiver, or enable the manual address option.
4. Enter the complete `MR1-…` code and click **Verify and pair**. The code is only saved after the receiver proves it has the matching key.
5. Allow **Local Network** access if macOS asks. If the firewall asks about incoming connections, allow MacRelay on the receiver.

For manual setup, use a name such as `Mac-mini.local` or a private local IP address such as `192.168.1.20`. The default port is `45821`. Public IP addresses and internet host names are rejected. Both Macs need a network path to each other; guest Wi-Fi may block that.

Pairing codes are random secrets, not short PINs. Transfer the code through a route you trust. **Copy code** deliberately replaces the receiver's clipboard. A code can pair one sender configuration; anyone who has it can act as a paired Mac. Choose **Replace pairing code…** to revoke the old code and pair again.

Receiving starts when you create the code. After quitting and reopening MacRelay, click **Start receiving**. MacRelay does not start receiving automatically at login or launch.

## Everyday use

1. Put the exact text you want to transfer on the **MacBook's clipboard**.
2. Press **⇧⌥⌘S**, or click **Send clipboard text**.
3. Wait for **Delivered**. This means the receiver has accepted the text into its waiting slot.
4. On the **Mac mini**, click **Copy received text**, or use **⇧⌥⌘R** there.
5. Click the destination field and press **⌘V**.

The text stays hidden unless you choose **Show text**. It expires after two minutes, or clears when you copy, discard, stop receiving, change roles, or quit. Text you explicitly copied remains in the macOS clipboard until another app or action changes it.

Only the shortcut for the selected role is registered on each Mac. Screen Sharing's shortcut routing still needs a two-Mac check; the buttons are always available if a shortcut is already taken or does not reach the receiver.

To check that MacRelay works independently of Screen Sharing clipboard sync, turn off Screen Sharing's **Share Clipboard** option during your own test. MacRelay does not change that setting for you.

### Using it with Wispr Flow

v0.1 sends whatever plain text is on the clipboard at the moment you press Send. Make sure that is the transcription you intend to send. MacRelay does not access Wispr Flow's history, trigger its shortcuts, watch its clipboard activity, or claim a direct integration.

Verifying a reliable, supported way to obtain the latest transcription is the first step in the [roadmap](docs/ROADMAP.md).

## Privacy and security

Pairing keys are saved in this Mac's Keychain, with iCloud Keychain syncing disabled for those keys. The app saves the selected role and receiver address, but never saves transferred text or text history.

Connections use authenticated encryption built with Apple's CryptoKit. Bonjour discovers a possible receiver; the pairing key decides whether to trust it. Each connection uses fresh encryption keys. See [SECURITY.md](SECURITY.md) for the protocol and its limits.

MacRelay does not monitor other clipboard changes, paste automatically, use Accessibility access, or send text to a cloud service. Other software, macOS clipboard sharing, clipboard managers, screenshots, and crash reports are outside its control.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| No receiver appears | Start receiving on the Mac mini. Check Local Network permission and the network. Try the manual local address. |
| Pairing fails | Use the complete code from the intended receiver. If it was replaced, pair again with the new code. |
| Receiver is busy | Copy or discard the waiting item on the Mac mini, then send again. |
| Delivery is unconfirmed | Check the receiver before resending. An acknowledgement may have been lost after acceptance. There are no automatic retries. |
| Shortcut does nothing | Check the selected role and use its button. Another app or Screen Sharing may intercept the shortcut. |
| Received text disappears | Waiting text expires after two minutes. Copy it before then. |
| Receiver cannot start | Another app may be using port `45821`. Stop the other MacRelay instance and check network permissions. |

Plain text only, up to 64 KiB per item. Images, files, formatting, multiple receivers, and internet relay connections are outside v0.1.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), [the roadmap](docs/ROADMAP.md), and [the protocol](docs/PROTOCOL.md). Please keep changes small and preserve the explicit send/copy actions and lack of saved text history.

[MIT licensed](LICENSE).
