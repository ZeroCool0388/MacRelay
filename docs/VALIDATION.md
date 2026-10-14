# Validation

## Checked locally — 14 October 2026

On an Apple Silicon Mac with Swift 6.4 and the macOS 27.0 SDK:

- **18 automated checks passed**, including the optional real Bonjour check.
- A release `.app` built successfully and its local code signature verified.
- Sender, receiver, and manual-address screens were inspected in UI preview mode.
- The app's settings file and shell scripts passed syntax checks.

The tests cover pairing-code parsing, both handshake proofs, wrong keys, changed messages, cross-session replay, separate acknowledgement keys, matching delivery IDs, text and frame limits, one waiting slot, expiry, and local address restrictions.

Network checks use actual sockets on the same Mac. They cover pairing probes, encrypted delivery, a busy receiver, wrong-key rejection, timeouts, and split TCP frames. The opt-in Bonjour check advertises a receiver, discovers it, and completes an authenticated pairing probe through its discovered endpoint.

Run the normal suite:

```sh
./scripts/test.sh
```

Run the Bonjour check as well, on a Mac with Local Network access:

```sh
MACRELAY_TEST_BONJOUR=1 ./scripts/test.sh
```

The normal suite skips Bonjour because CI and some networks restrict discovery. The test suite never reads or writes the general clipboard, saves a pairing key, or needs real transcriptions.

GitHub Actions runs the normal checks and builds the app on macOS 14, 15, and 26. The macOS 14 job explicitly selects Xcode 16.2 to use Swift 6 instead of the runner's older default tools. Current run results are recorded on the repository's Actions tab; this document is a local validation record, not a claim about future runs.

## Still needs two Macs

These checks have not been completed yet. Use harmless sample text.

- [ ] Build and open the app on the MacBook and Mac mini.
- [ ] Allow Local Network access and, where prompted, incoming connections.
- [ ] Create a receiver code, verify pairing on the sender, and restart both apps. Check Keychain persistence and any permission prompts.
- [ ] Start receiving again. Turn off Screen Sharing's Share Clipboard option for this test.
- [ ] Copy a sample sentence on the MacBook. Use **⇧⌥⌘S** and check **Delivered**.
- [ ] Confirm the Mac mini's clipboard did not change merely because text arrived.
- [ ] Click **Copy received text** on the mini, then paste into TextEdit. Check exact Unicode, line breaks, and whitespace.
- [ ] Repeat using **⇧⌥⌘R** through Screen Sharing. Check that the shortcut reaches the intended Mac.
- [ ] Send another item while text is waiting. Check **busy** and confirm the first item is unchanged.
- [ ] Leave an item waiting for two minutes. Check that it expires. Stop receiving and quit with an item waiting; check it does not return.
- [ ] Copy text deliberately, then let the waiting-item deadline pass. Check MacRelay does not later restore or clear the clipboard.
- [ ] Replace the receiver code. Check the previous sender key fails and the new code pairs successfully.
- [ ] Disconnect the network mid-send. Check an uncertain delivery does not trigger an automatic resend.
- [ ] Test with another app taking the same shortcut; check the MacRelay buttons remain usable.

Direct Wispr capture, automatic insertion, real Keychain UI prompts, and compatibility with every Screen Sharing setup are not verified by the socket tests or UI preview.
