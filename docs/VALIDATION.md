# Testing and validation

Automated checks and limited live reports cover different parts of MacRelay. Past results do not prove that every later change or destination app works. Re-run the current suite on macOS and record the version, permissions and test conditions when reporting a result.

## Automated checks

Run the normal suite on a Mac with Swift 6 or later:

```sh
./scripts/test.sh
./scripts/build-app.sh
```

Run the optional Bonjour check on a network that permits discovery:

```sh
MACRELAY_TEST_BONJOUR=1 ./scripts/test.sh
```

The suite covers pairing and handshake proofs, encrypted transfers, changed messages, replay refusal, delivery IDs, frame and text limits, local address restrictions, inbox expiry and busy handling. Network tests use real local sockets; Bonjour discovery is opt-in because CI and some networks restrict it.

Automatic-mode tests cover synthetic Wispr records, enable-time baselines, ambiguous matches, stable completed text, database changes, token expiry and cancellation, UTF-16 selections, Screen Sharing window identity, field-text verification and clipboard transactions. Clipboard tests use private named pasteboards, including lazy data providers. Database tests create synthetic SQLite fixtures. Tests do not use the general clipboard, real dictation history or saved pairing keys.

The [CI workflow](../.github/workflows/ci.yml) runs tests and builds on macOS 14, 15 and 26. It selects Swift 6 tools explicitly on macOS 14 and packages a development build on that runner. Check the repository's Actions tab for current results. Linux cannot build the AppKit app or run the full macOS suite.

## Historical results

Development records dated 14 October 2026 report these results:

| Area | Reported result | Limit |
| --- | --- | --- |
| Manual transfer | Pairing, explicit send/copy/paste and shortcuts worked across two Macs. | The full interference and permission checklist was not completed. |
| Wispr schema | The required local History table fields were checked against Wispr Flow 1.6.1147. | This establishes schema compatibility, not live insertion reliability. |
| Early automatic builds | Source-window identity and destination-text verification refused several attempts. | A stopped paste or authenticated reply alone did not prove insertion. |
| TextEdit | Two consecutive dictations were reported as inserted and confirmed. | This was a limited live test, not an app-wide compatibility guarantee. |
| Codex | Two consecutive dictations were reported as inserted and confirmed, including a test with v0.2.6 on both Macs. | Longer sessions and other destination apps remained unverified. |
| Build and packaging | Local builds, signatures and packaged contents were checked; macOS CI builds and tests passed. | These historical results do not validate later source changes. |

Early tests temporarily used different sender and receiver versions. They are historical evidence, not installation instructions. Use matching app versions for new tests. The records do not contain dictated text and do not establish the cause of every failed attempt.

Later review fixes added listener-failure cleanup, token-specific cancellation, retained clipboard payloads after unconfirmed pastes and refusal of non-plain-text flavors. Their tests must be run on macOS before treating them as live-validated behaviour.

## Manual transfer checklist

Use harmless invented text. These are checks to run, not a list of completed results.

- [ ] Install compatible builds of the same version on the sender and receiver.
- [ ] Allow Local Network access and incoming connections where prompted.
- [ ] Pair the Macs, restart both apps and check Keychain persistence and permission prompts.
- [ ] Start receiving again and disable Screen Sharing clipboard sync if using a remote session.
- [ ] Send with the button and Shift + Option + Command + S.
- [ ] Check that receiving alone does not change the receiver's clipboard.
- [ ] Copy with the button and Shift + Option + Command + R, then paste. Check Unicode, line breaks and whitespace.
- [ ] Send while text is waiting. Confirm busy refusal and preservation of the first item.
- [ ] Check two-minute expiry, explicit discard, receiver stop, role changes and quitting.
- [ ] Replace the pairing code. Confirm the old key fails and the new code works.
- [ ] Disconnect during a send. Confirm that uncertain delivery does not cause a resend.
- [ ] Check shortcut conflicts and confirm the buttons remain usable.

## Automatic insertion checklist

Use the same app version on both Macs, allow Accessibility, start receiver insertion before sender relay and choose the receiver's Screen Sharing window. Turn off Screen Sharing's Share Clipboard option.

- [ ] Dictate harmless text into a blank TextEdit document. Confirm that it appears once and the sender reports a blocked Wispr paste and confirmed insertion.
- [ ] Repeat in the intended destination app, including Unicode and punctuation.
- [ ] Change destination focus, selection or text during delivery. Confirm refusal without insertion into another field.
- [ ] Check ordinary typing and Command-V while automatic mode is enabled.
- [ ] Test rapid dictations, ambiguous records, matching timeouts and focus loss after arming. Confirm reservation cancellation and no automatic replay.
- [ ] Fail the listener after arming. Confirm that automatic insertion turns off and the token is cleared.
- [ ] Use a clipboard offering images, PDFs, rich text or custom flavors. Confirm refusal without reading those flavors or changing the clipboard.
- [ ] Confirm restoration after verified insertion and preservation of newer clipboard writes.
- [ ] Delay destination event processing past verification. Confirm that the queued paste retains the intended payload and a quick automatic retry is refused.
- [ ] Select text identical to the proposed insertion. Confirm refusal before a paste is posted.
- [ ] Stop or relaunch MacRelay and Wispr. Confirm that earlier records are not sent when enabling again.
- [ ] Test password fields and known terminal apps. Confirm refusal.
- [ ] Test clipboard-sync interference, disconnection, permission renewal and Wispr updates separately.

Save a test report after a failure. Review it before sharing and remove private device or network details. Record only the observed outcome; socket tests, metadata and UI previews do not prove another app consumed a paste.
