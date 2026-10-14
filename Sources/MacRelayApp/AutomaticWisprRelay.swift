import AppKit
import Foundation
import MacRelayCore
import MacRelayInsertion
import MacRelayTransport
import MacRelayWispr
import Network

/// A guarded paste attempt is mandatory. Without one, no automatic transfer happens.
/// This avoids a duplicate when an unrecognized Wispr insertion path bypasses the guard.
@MainActor
final class AutomaticWisprRelay {
    var onStatus: ((String) -> Void)?
    var onStopped: (() -> Void)?
    private let guardTap = WisprPasteGuard()
    private let sender = RelaySender()
    private var store: WisprStore?
    private var cursor: WisprCursor?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var run = UUID()
    private var binding: ScreenSharingDestination?
    private var endpoint: NWEndpoint?
    private var pairing: PairingKey?
    private var lastPIDRefresh = Date.distantPast
    private var blockedCount = 0
    private var insertedCount = 0
    private var receiverNames: [String] = []
    private var observations: [String: String] = [:]
    private var waitingForSource = false
    private var sourceWasReady = false
    private var pauseReason: String?
    private var lastVerifiedSource = Date.distantPast
    var testDetails: [String: String] {
        observations.merging(
            [
                "pasteAttemptsStopped": String(blockedCount), "confirmedInsertions": String(insertedCount),
                "pasteGuardHealthy": String(guardTap.isHealthy),
            ], uniquingKeysWith: { _, new in new })
    }

    func start(to endpoint: NWEndpoint, pairing: PairingKey) async throws {
        stop()
        let startingRun = run
        guard AccessibilitySupport.isTrusted else { throw AutomationError.permission }
        let probe = try await sender.send(Transfer(), to: endpoint, pairing: pairing)
        guard run == startingRun, !Task.isCancelled else { throw CancellationError() }
        guard probe.capabilities?.contains(Acknowledgement.automaticInsertion) == true else {
            throw AutomationError.receiverUpgrade
        }
        guard let names = probe.receiverNames, !names.isEmpty else { throw AutomationError.receiverUpgrade }
        receiverNames = names
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/Wispr Flow/flow.sqlite")
        let store = try WisprStore(url: url)
        self.store = store
        cursor = WisprCursor(baseline: store.baseline)
        self.endpoint = endpoint
        self.pairing = pairing
        guardTap.onPaste = { [weak self] in self?.pasteWasBlocked(evidence: $0) }
        guardTap.onFailure = { [weak self] in self?.fail($0) }
        do { try guardTap.start() } catch {
            stop()
            throw error
        }
        blockedCount = 0
        insertedCount = 0
        observations = ["adapter": "local-read-only-v1", "schemaCheck": "passed", "receiverCheck": "passed"]
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        onStatus?(
            "Automatic mode is on. Click into a field on the mini through Screen Sharing, then dictate normally."
        )
    }
    func stop() {
        run = UUID()
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        guardTap.stop()
        sender.cancel()
        store = nil
        cursor = nil
        binding = nil
        endpoint = nil
        pairing = nil
        receiverNames = []
        waitingForSource = false
        sourceWasReady = false
        pauseReason = nil
        lastVerifiedSource = .distantPast
    }
    private func poll() {
        guard let store, var cursor else { return }
        guard AccessibilitySupport.isTrusted, guardTap.isHealthy else {
            fail(AutomationError.guardUnavailable)
            return
        }
        if Date().timeIntervalSince(lastPIDRefresh) > 1 {
            guardTap.refreshPIDs()
            lastPIDRefresh = Date()
        }
        do {
            let source = inspectSource()
            guard let focused = source.destination else {
                if waitingForSource { return }
                if task != nil {
                    fail(source.failure)
                    return
                }
                let preserve = SourcePausePolicy.preserveCursor(
                    foreground: source.details["sourceForegroundBundle"] ?? "",
                    hasVerifiedBinding: binding != nil,
                    secondsSinceVerified: Date().timeIntervalSince(lastVerifiedSource))
                if !preserve {
                    cursor.skip(to: try store.latestRowID())
                    self.cursor = cursor
                    binding = nil
                }
                let reason = source.failure.localizedDescription
                if sourceWasReady || pauseReason != reason {
                    onStatus?("Automatic mode is paused. " + source.failure.localizedDescription)
                    sourceWasReady = false
                    pauseReason = reason
                }
                return
            }
            if !sourceWasReady {
                onStatus?("Screen Sharing window checked. Dictate normally into the mini's focused field.")
                sourceWasReady = true
                pauseReason = nil
            }
            if let binding, !binding.isCurrent() {
                if task != nil {
                    fail(AutomationError.screenSharing)
                    return
                }
                cursor.skip(to: try store.latestRowID())
            }
            binding = focused
            lastVerifiedSource = Date()
            let records = try store.records(after: cursor.watermark, pending: cursor.pendingIDs)
            if let latest = records.last {
                let app = latest.app
                observations["newRecordApp"] =
                    app.count <= 128 && app.contains(".")
                        && app.unicodeScalars.allSatisfy({
                            CharacterSet(
                                charactersIn:
                                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
                            ).contains($0)
                        })
                    ? app : "unrecognized"
                observations["newRecordStatus"] =
                    ["formatted", "processing", "recording", "transcribing", "error", "failed", "pending"]
                        .contains(latest.status) ? latest.status : "unrecognized"
            }
            try cursor.observe(records, eligible: true)
            self.cursor = cursor
            if task == nil, cursor.hasUnguardedCompletion() { fail(AutomationError.unrecognizedPaste) }
        } catch { fail(error) }
    }
    private func pasteWasBlocked(evidence: Data) {
        blockedCount += 1
        guard task == nil, let endpoint, let pairing else {
            // Never associate a later dictation with an earlier reservation.
            fail(RelayError.insertionRejected)
            return
        }
        let run = self.run
        waitingForSource = true
        onStatus?("Wispr paste stopped. Checking the Screen Sharing window…")
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.run == run {
                    self.task = nil
                    self.waitingForSource = false
                }
            }
            do {
                // Wispr may still be returning focus when its generated V event is intercepted.
                // Wait for a verified source; never deliver into an unchecked session.
                let focusDeadline = Date().addingTimeInterval(1)
                var check = self.inspectSource()
                while check.destination == nil, Date() < focusDeadline {
                    guard self.run == run, !Task.isCancelled, self.guardTap.isHealthy else {
                        throw CancellationError()
                    }
                    try await Task.sleep(nanoseconds: 50_000_000)
                    check = self.inspectSource()
                }
                guard self.run == run, !Task.isCancelled, let destination = check.destination else {
                    throw check.failure
                }
                self.waitingForSource = false
                self.binding = destination
                self.poll()
                guard self.run == run else { return }
                self.onStatus?("Screen Sharing window checked. Checking the mini's field…")
                let armed = try await self.sender.send(
                    Transfer(armID: UUID()), to: endpoint, pairing: pairing)
                guard let token = armed.token else { throw RelayError.acknowledgementMismatch }
                let deadline = Date().addingTimeInterval(5)
                var record: WisprRecord?
                while record == nil {
                    guard self.run == run, !Task.isCancelled, destination.isCurrent(), Date() < deadline,
                        self.guardTap.isHealthy
                    else { throw AutomationError.noFreshDictation }
                    record = try self.cursor?.ready(matchingDigest: evidence)
                    if record == nil { try await Task.sleep(nanoseconds: 50_000_000) }
                }
                guard self.run == run, !Task.isCancelled, destination.isCurrent(),
                    self.guardTap.isHealthy, let record, let text = record.text
                else { throw AutomationError.focusChanged }
                // Remove before sending. An uncertain insertion must never be attempted again.
                self.cursor?.consume(record)
                _ = try await self.sender.send(
                    Transfer(inserting: text, token: token), to: endpoint, pairing: pairing)
                guard self.run == run else { return }
                self.insertedCount += 1
                self.onStatus?(
                    "Dictation inserted on the mini. \(self.insertedCount) confirmed; \(self.blockedCount) Wispr paste attempts stopped."
                )
            } catch {
                guard self.run == run else { return }
                self.fail(error)
            }
        }
    }
    private func inspectSource() -> ScreenSharingCheck {
        let check = ScreenSharingDestination.inspect(expectedNames: receiverNames)
        for key in observations.keys.filter({ $0.hasPrefix("source") }) {
            observations.removeValue(forKey: key)
        }
        observations.merge(check.details, uniquingKeysWith: { _, new in new })
        if check.details["sourceForegroundBundle"] == "com.apple.ScreenSharing" {
            for (key, value) in check.details { observations["lastScreenSharing." + key] = value }
        }
        return check
    }
    private func fail(_ error: Error) {
        stop()
        let message: String
        if error is AutomationError || error is WisprStoreError || error is RelayError {
            message = error.localizedDescription
        } else {
            message =
                "Automatic delivery stopped. Check the mini before dictating again; delivery is unconfirmed."
        }
        observations["lastFailure"] = message
        onStatus?(message + " Automatic mode is now off.")
        onStopped?()
    }
}
