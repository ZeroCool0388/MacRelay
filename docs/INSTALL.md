# Install MacRelay

One app contains both Send and Receive modes. Install the same version on both Macs. macOS 14 or later is required. Use a build compatible with each Mac's processor architecture; the build script does not create a universal binary.

## Build and package from source

On a Mac with Swift 6 or later, run these commands from the repository directory:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/package-app.sh
```

The app is created at `build/MacRelay.app`. Packaging uses that existing app and produces `build/MacRelay-<version>-macOS.zip` with a `.sha256` checksum file. The archive contains the app, this guide and the MIT licence. Install compatible builds of the same version on both Macs.

## Install or update

1. Quit MacRelay if it is running.
2. Unpack the archive and move **MacRelay.app** to `/Applications`. Choose **Replace** when updating.
3. Open the installed app. It appears in the menu bar with no Dock icon.
4. Choose **Send** on the sender Mac and **Receive** on the receiver Mac.
5. Allow Local Network access when prompted. For automatic insertion, allow Accessibility on both Macs using **Open Accessibility settings**. Some macOS versions call this **Device Control and Data Access**.

These are ad-hoc signed development builds, not Developer ID signed or notarized apps. Keep the installed app in a consistent location. Replacing a build can require renewed Keychain or Accessibility approval. Request access for the current app; an enabled entry for a previous build may be insufficient.

## Pair and transfer text

1. On the receiver, click **Create pairing code and start**.
2. On the sender, select the receiver or enter its local address. Enter the full private code and click **Verify and pair**.
3. Copy sample text on the sender and click **Send clipboard text**.
4. On the receiver, click **Copy received text**, then paste into an app yourself.

Keep pairing codes private. Existing keys can be kept when updating. Replacing the receiver's code revokes the old pairing. After reopening the receiver app, click **Start receiving**.

## Try automatic dictation

Automatic mode is experimental and uses an undocumented Wispr Flow adapter. It requires Wispr on the sender and Apple Screen Sharing configured separately.

1. Start receiving and allow Accessibility on both Macs.
2. On the receiver, enable **Insert dictation automatically**. Use an empty or plain-text-only clipboard.
3. On the sender, open the receiver in Screen Sharing and turn off **Share Clipboard**. Click **Choose Screen Sharing window**, check the receiver, choose its window and click **Relay Wispr from this window**.
4. Keep that window focused, click a blank TextEdit document on the receiver and dictate with Wispr on the sender.
5. Check that the words appear once. Automatic mode starts off after reopening MacRelay.

If insertion is unconfirmed, check the field and any pending paste before dictating again. MacRelay does not repeat the insertion or restore the old clipboard into a queued paste. The temporary dictation remains on the clipboard and blocks another automatic paste until that clipboard item is replaced.

**Save test report** saves check results without dictated words. Review reports before sharing. The repository's README, security notes and validation guide describe the feature's limits and further checks.
