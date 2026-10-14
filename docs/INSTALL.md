# Install MacRelay on both Macs

MacRelay is one app. The same app includes **Send** and **Receive** modes.
Install the app from the **same download** on both Macs and check that the
version shown in its menu matches. You do not need separate sender and receiver
downloads.

## Install or update

1. Quit MacRelay if it is running.
2. Unpack the download. Move **MacRelay.app** into the main **Applications**
   folder, choosing **Replace** when updating.
3. Open the installed app. If macOS asks for permission, use MacRelay's
   **Open Accessibility settings** button and allow the current app. On newer
   macOS this permission is called **Device Control and Data Access**.
4. Use **Send** on the MacBook and **Receive** on the mini.

These are development downloads, locally signed rather than Apple-notarized.
An update can require renewed permission. Keep the app in Applications.
Use a build made for your Mac's processor; one Apple Silicon build works on
both an Apple Silicon MacBook Air and an M4 Mac mini. macOS 14 or later is required.

## Connect and dictate

Existing pairing keys can be kept when updating. For a first setup, create a
pairing code on the mini and verify it on the MacBook. Keep the code private.

1. On the mini, start receiving and enable **Insert dictation automatically**.
2. On the MacBook, click **Choose Screen Sharing window**, check the receiver is
   the mini, choose its window, then **Relay Wispr from this window**.
3. Focus a text field on the mini through Screen Sharing and use Wispr normally.

Automatic mode starts off after reopening the app. During testing, turn off
Screen Sharing's **Share Clipboard** option. MacRelay does not change it for you.
If delivery is unconfirmed, check the field before dictating again; MacRelay
does not repeat an uncertain insertion. **Save test report** saves only check
results, without your words.

Automatic mode uses an independent, undocumented Wispr adapter and remains
experimental. See the repository's README and validation notes for tested cases
and limits.
