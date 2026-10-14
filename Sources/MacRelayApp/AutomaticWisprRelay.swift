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
            guard let focused = try? ScreenSharingDestination.capture(expectedNames: receiverNames) else {
                if task != nil {
                    fail(AutomationError.screenSharing)
                    return
                }
                cursor.skip(to: try store.latestRowID())
                self.cursor = cursor
                binding = nil
                return
            }
            if let binding, !binding.isCurrent() {
                if task != nil {
                    fail(AutomationError.screenSharing)
                    return
                }
                cursor.skip(to: try store.latestRowID())
            }
            binding = focused
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
        guard let destination = try? ScreenSharingDestination.capture(expectedNames: receiverNames) else {
            fail(AutomationError.screenSharing)
            return
        }
        // Refresh immediately so a recently created History row is included.
        poll()
        guard self.run == run else { return }
        onStatus?("Wispr paste stopped. Checking the mini's field…")
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.run == run { self.task = nil } }
            do {
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
