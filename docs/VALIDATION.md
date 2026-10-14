# Validation

## Checked locally — 14 October 2026

On an Apple Silicon Mac with Swift 6.4 and the macOS 27.0 SDK:

- The original v0.1 had **18 automated checks pass**, including the optional real Bonjour check.
- v0.2 adds automatic-message, reservation/replay, Unicode selection, Wispr cursor/database, paste-filter policy and private-clipboard restoration checks. **33 checks passed locally**, including Bonjour; the release app built and its local signature verified. Sender and receiver screens were checked in a separate preview without connections or clipboard access.
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

The normal suite skips Bonjour because CI and some networks restrict discovery. The test suite never reads or writes the general clipboard, saves a pairing key, or needs real transcriptions. New clipboard tests use isolated named test pasteboards; database tests create temporary synthetic SQLite fixtures.

GitHub Actions runs the normal checks and builds the app on macOS 14, 15, and 26. The macOS 14 job explicitly selects Xcode 16.2 to use Swift 6 instead of the runner's older default tools. Current run results are recorded on the repository's Actions tab; this document is a local validation record, not a claim about future runs.

## Two-Mac manual transfer — user reported

Pairing, manual send/copy/paste and the original four-key shortcuts were tested by the user on a MacBook Air and Mac mini through Screen Sharing. They reported success. This is a bounded user test, not a claim that every case below passed.

The remaining manual checklist uses harmless sample text.

- [x] Open the development app on the MacBook and Mac mini.
- [ ] Allow Local Network access and, where prompted, incoming connections.
- [ ] Create a receiver code, verify pairing on the sender, and restart both apps. Check Keychain persistence and any permission prompts.
- [ ] Start receiving again. Turn off Screen Sharing's Share Clipboard option for this test.
- [x] Send a sample sentence from the MacBook, using the button and **⇧⌥⌘S**.
- [ ] Confirm the Mac mini's clipboard did not change merely because text arrived.
- [ ] Click **Copy received text** on the mini, then paste into TextEdit. Check exact Unicode, line breaks, and whitespace.
- [x] Use **⇧⌥⌘R** through Screen Sharing and paste the received text on the mini.
- [ ] Send another item while text is waiting. Check **busy** and confirm the first item is unchanged.
- [ ] Leave an item waiting for two minutes. Check that it expires. Stop receiving and quit with an item waiting; check it does not return.
- [ ] Copy text deliberately, then let the waiting-item deadline pass. Check MacRelay does not later restore or clear the clipboard.
- [ ] Replace the receiver code. Check the previous sender key fails and the new code pairs successfully.
- [ ] Disconnect the network mid-send. Check an uncertain delivery does not trigger an automatic resend.
- [ ] Test with another app taking the same shortcut; check the MacRelay buttons remain usable.

Direct Wispr capture, automatic insertion, real Keychain UI prompts, and compatibility with every Screen Sharing setup are not verified by the socket tests or UI preview.

## v0.2 experimental automatic relay — local gate

Wispr Flow **1.6.1147** was running on the MacBook Air. A read-only helper confirmed the needed field names in its local `History` table. It did not read transcript rows, clipboard, audio, credentials or settings. This confirms schema compatibility only.

The new tests use synthetic data and private named pasteboards. They cover:

- Baseline exclusion of old rows, unfinished text and text targeted at other apps.
- Read-only database mode, schema changes, oversized bodies and row reset.
- Stable final text matched to the stopped Wispr paste, ambiguous new records, expired candidates and no consumed-record replay.
- Authenticated capability/arm/commit exchanges over real local sockets; replayed token refusal.
- Single-use/expired reservations and UTF-16 selection correctness.
- Paste filter refusal for physical/user input, other PIDs, other keys and other apps.
- Receiver-name checks for Screen Sharing titles.
- Restoration of multiple clipboard items/types; preserving a newer copy; oversized clipboard refusal.

These checks do not prove actual Wispr event source IDs, the live record lifecycle, Accessibility permissions, or another app’s insertion behaviour.

## v0.2 live test — pending

Use **v0.2 test** on both Macs. Allow Accessibility, enable receiver automatic insertion first, then sender automatic relay. Turn off Screen Sharing clipboard sync and use one session for the paired receiver.

- [ ] Dictate a harmless sentence into a blank TextEdit document on the mini. Words appear once, with no relay/copy/paste gesture.
- [ ] Sender confirms insertion and reports a stopped Wispr paste attempt. This distinguishes MacRelay from native clipboard sync.
- [ ] Repeat in the everyday destination app, including Unicode and punctuation.
- [ ] Move destination focus/selection or edit the field during delivery; confirm refusal without insertion in a new field.
- [ ] Check ordinary user typing and Command-V still work while the sender mode is on.
- [ ] Test two dictations close together, failure/unconfirmed result, and disconnection. No automatic replay.
- [ ] Put harmless non-text clipboard content on the mini, dictate, and confirm it is restored; make a newer copy during paste and confirm that copy is preserved.
- [ ] Stop/relaunch each app and Wispr. Earlier dictations are never sent when enabling again.
- [ ] Test password fields and known terminal apps; insertion is refused.

Use **Save test report** on each Mac after a failure. The report contains metadata only. Do not mark the automatic feature proven until the first two live checks pass.

## First automatic live attempt — 14 October 2026

The MacBook report confirmed one recognized Wispr paste was stopped, with receiver and schema checks passing. The source Screen Sharing window check rejected delivery before receiver field reservation. The user reported one visible remote window with a name matching the paired mini. No automatic insertion was confirmed.

v0.2.1 removes the optional standard-window subrole requirement, checks the named focused window, and limits main-window fallback to a single verified non-modal window. It waits briefly for source focus to return and records the actual failing attributes as counts/booleans, without window titles or field text. A new live test is required; these changes are not a claim that the reported failure is fully resolved.

## v0.2.1 live attempt

The report confirmed the focused window and title were readable, one Wispr paste was stopped, and no insertion was attempted. The receiver-name comparison returned false for every source window. The user-visible title matched the mini’s reported name, so the name heuristic did not establish the intended source reliably.

v0.2.2 uses an explicit source-window choice beside the authenticated receiver name. It keeps the original window reference, owner process and title in memory and refuses a changed window. Alias acceptance and changed-process/window/title refusal are checked with synthetic inputs. The user must still confirm the receiver is the mini, choose the window showing it, and complete a new spoken dictation test.
