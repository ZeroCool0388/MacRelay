import AppKit
import ApplicationServices
import Foundation
import MacRelayCore
import MacRelayInsertion
import MacRelayTransport
import Network
import SwiftUI

struct SavedTarget: Codable, Equatable {
    enum Kind: String, Codable { case nearby, address }
    let kind: Kind
    let name: String
    let domain: String?
    let port: UInt16?
    var label: String { kind == .nearby ? name : "\(name):\(port ?? RelayReceiver.defaultPort)" }
    var endpoint: NWEndpoint {
        if kind == .nearby {
            return .service(
                name: name, type: RelayReceiver.serviceType, domain: domain ?? "local.", interface: nil)
        }
        return .hostPort(host: NWEndpoint.Host(name), port: NWEndpoint.Port(rawValue: port!)!)
    }
}

@MainActor
final class RelayModel: ObservableObject {
    enum Role: String, CaseIterable {
        case sender = "Send"
        case receiver = "Receive"
    }
    @Published var role: Role {
        didSet {
            guard role != oldValue else { return }
            if !preview { UserDefaults.standard.set(role.rawValue, forKey: "role") }
            operation = UUID()
            sourceWindows = []
            selectedSourceWindowID = nil
            sourceReceiverName = nil
            stopAutomatic()
            stopReceiver()
            sender.cancel()
            discovery.stop()
            hidePairingCode()
            configureHotKeys()
            pairingInput = ""
            inbox.clear()
            refreshInbox()
            status = "Ready. Choose an explicit action below."
            if role == .sender { startDiscovery() }
        }
    }
    @Published var confirmReplacement = false
    @Published var revealText = false
    @Published var status = "Ready. Choose Send on the MacBook and Receive on the Mac mini."
    @Published var hotKeyStatus = ""
    @Published var discoveryStatus = ""
    @Published var devices: [DiscoveredReceiver] = []
    @Published var selectedDevice = ""
    @Published var useAddress = false
    @Published var host = ""
    @Published var port = String(RelayReceiver.defaultPort)
    @Published var pairingInput = ""
    @Published var pairingCode: String?
    @Published var receiverPaired = false
    @Published var senderPaired = false
    @Published var receiverRunning = false
    @Published var isSending = false
    @Published var pendingText: String?
    @Published var expiresAt: Date?
    @Published var pairedTargetLabel: String?
    @Published var automaticEnabled = false
    @Published var automaticFailed = false
    @Published var sourceWindows: [ScreenSharingWindowChoice] = []
    @Published var selectedSourceWindowID: UUID?
    @Published var sourceReceiverName: String?
    var selectedSourceWindow: ScreenSharingWindowChoice? {
        sourceWindows.first { $0.id == selectedSourceWindowID }
    }
    @Published var automaticStarting = false
    private let automatic = AutomaticWisprRelay()
    private let insertion = FocusedInsertion()
    private let receiver = RelayReceiver()
    private let sender = RelaySender()
    private let discovery = ReceiverDiscovery()
    private let hotKeys = GlobalHotKeys()
    private var receiverKey: PairingKey?
    private var senderKey: PairingKey?
    private var savedTarget: SavedTarget?
    private var inbox = Inbox()
    private var expiryTimer: Timer?
    private var codeTimer: Timer?
    private var operation = UUID()
    private let preview: Bool
    private var previewWindow: NSWindow?

    init() {
        preview = CommandLine.arguments.contains("--preview")
        role = Role(rawValue: UserDefaults.standard.string(forKey: "role") ?? "") ?? .sender
        receiver.onState = { [weak self] state in
            guard let self else { return }
            self.status = state
            if state.hasPrefix("Receiver unavailable") {
                self.receiverRunning = false
                self.stopAutomatic()
                self.automaticFailed = true
            }
        }
        receiver.onTransfer = { [weak self] transfer in
            guard let self, self.role == .receiver, self.receiverRunning else {
                throw RelayError.disconnected
            }
            if transfer.kind == .probe {
                return Acknowledgement(
                    id: transfer.id, status: .paired,
                    capabilities: self.automaticEnabled && AccessibilitySupport.isTrusted
                        ? [Acknowledgement.automaticInsertion] : [],
                    receiverNames: ([Host.current().localizedName, Host.current().name].compactMap { $0 }
                        + Host.current().addresses.filter { LocalAddress.isAllowed($0) }).prefix(8).map { $0 }
                )
            }
            if transfer.kind == .arm || transfer.kind == .insert {
                guard self.automaticEnabled, AccessibilitySupport.isTrusted else {
                    return Acknowledgement(id: transfer.id, status: .rejected)
                }
                if transfer.kind == .arm {
                    do {
                        let token = try self.insertion.arm()
                        self.status = "Field checked. Waiting briefly for the completed dictation…"
                        return Acknowledgement(id: transfer.id, status: .armed, token: token)
                    } catch {
                        self.status = error.localizedDescription
                        return Acknowledgement(id: transfer.id, status: .rejected)
                    }
                }
                guard let token = transfer.token, let text = transfer.text else {
                    throw RelayError.invalidMessage
                }
                let result = await self.insertion.insert(text, token: token)
                self.status =
                    result == .inserted
                    ? "Dictation inserted in the focused field."
                    : result == .unconfirmed
                        ? "Insertion was attempted. Check the field before dictating again."
                        : "Insertion stopped because the field, selection or permission changed."
                return Acknowledgement(id: transfer.id, status: result)
            }
            let ack = try self.inbox.receive(transfer)
            if ack.status == .accepted {
                self.refreshInbox()
                self.status = "Text received. Copy it on this Mac, then paste where you need it."
            }
            return ack
        }
        discovery.onResults = { [weak self] devices in
            self?.devices = devices
            if let self, !devices.contains(where: { $0.id == self.selectedDevice }) {
                self.selectedDevice = devices.first?.id ?? ""
            }
        }
        discovery.onStatus = { [weak self] in self?.discoveryStatus = $0 }
        automatic.onStatus = { [weak self] in self?.status = $0 }
        automatic.onStopped = { [weak self] in
            self?.automaticEnabled = false
            self?.automaticFailed = true
        }
        guard !preview else {
            if CommandLine.arguments.contains("--preview-source-choice") {
                let choice = ScreenSharingWindowChoice(
                    binding: ScreenSharingWindowBinding(
                        pid: 0,
                        window: AXUIElementCreateApplication(0), originalTitle: "Example remote screen"),
                    label: "Example remote screen (current)", isFocused: true)
                senderPaired = true
                sourceReceiverName = "Example Mac mini"
                sourceWindows = [choice]
                selectedSourceWindowID = choice.id
                role = .sender
            }
            hotKeyStatus = "Preview mode — shortcuts and connections are off."
            DispatchQueue.main.async { [weak self] in self?.showPreviewWindow() }
            return
        }
        do {
            receiverKey = try KeychainStore.read("receiver")
            senderKey = try KeychainStore.read("sender")
            receiverPaired = receiverKey != nil
            if let data = UserDefaults.standard.data(forKey: "pairedTarget"),
                let target = try? JSONDecoder().decode(SavedTarget.self, from: data),
                target.kind == .nearby || ((target.port ?? 0) > 0 && LocalAddress.isAllowed(target.name))
            {
                savedTarget = target
                pairedTargetLabel = target.label
                senderPaired = senderKey != nil
            }
        } catch { status = error.localizedDescription }
        hotKeys.onPress = { [weak self] id in
            Task { @MainActor in
                guard let self else { return }
                if id == 1, self.role == .sender { self.sendClipboard() }
                if id == 2, self.role == .receiver { self.copyReceived() }
            }
        }
        configureHotKeys()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let hadText = self.inbox.text != nil
                self.inbox.expire()
                self.refreshInbox()
                if hadText && self.inbox.text == nil {
                    self.status = "Received text expired after two minutes."
                }
            }
        }
        if role == .sender { startDiscovery() }
    }

    private func showPreviewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MacRelay Preview"
        window.contentView = NSHostingView(rootView: RelayPanel(model: self))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        previewWindow = window
    }

    private func configureHotKeys() {
        guard !preview else { return }
        hotKeyStatus =
            hotKeys.register(send: role == .sender)
            ? (role == .sender
                ? "Shortcut: ⇧⌥⌘S sends clipboard text" : "Shortcut: ⇧⌥⌘R copies received text")
            : "Shortcut is unavailable or already in use. Use the button."
    }

    func startDiscovery() {
        guard !preview else { return }
        discovery.start()
    }

    func generatePairingCode() {
        guard !preview, !isSending else { return }
        do {
            let key = PairingKey()
            try KeychainStore.save(key, account: "receiver")
            stopReceiver()
            inbox.clear()
            refreshInbox()
            receiverKey = key
            receiverPaired = true
            pairingCode = key.code
            codeTimer?.invalidate()
            codeTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.hidePairingCode() }
            }
            status = "Enter this code on the MacBook. Keep it private."
            startReceiver()
        } catch { status = error.localizedDescription }
    }
    func hidePairingCode() {
        pairingCode = nil
        codeTimer?.invalidate()
        codeTimer = nil
    }
    func copyPairingCode() {
        guard let pairingCode else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(pairingCode, forType: .string) {
            status = "Pairing code copied by request. Keep it private."
        } else {
            status = "The pairing code could not be copied."
        }
    }
    func startReceiver() {
        guard !preview, role == .receiver, let receiverKey else { return }
        do {
            try receiver.start(pairing: receiverKey)
            receiverRunning = true
            status = "Starting receiver…"
        } catch {
            receiverRunning = false
            status = "Receiver could not start. The port may already be in use."
        }
    }
    func stopReceiver() {
        stopAutomatic()
        receiver.stop()
        receiverRunning = false
        inbox.clear()
        refreshInbox()
    }
    func toggleReceiver() {
        if receiverRunning {
            stopReceiver()
            status = "Receiver stopped. Waiting text was discarded."
        } else {
            startReceiver()
        }
    }

    private func draftTarget() throws -> SavedTarget {
        if useAddress {
            let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty, !address.contains(where: { $0.isWhitespace }),
                LocalAddress.isAllowed(address), let number = UInt16(port), number > 0
            else {
                throw ConfigurationError.invalidAddress
            }
            return SavedTarget(kind: .address, name: address, domain: nil, port: number)
        }
        guard let device = devices.first(where: { $0.id == selectedDevice }),
            case .service(let name, _, let domain, _) = device.endpoint
        else {
            throw ConfigurationError.noReceiver
        }
        return SavedTarget(kind: .nearby, name: name, domain: domain, port: nil)
    }
    func pairSender() {
        guard !preview, role == .sender, !isSending else { return }
        stopAutomatic()
        sourceWindows = []
        selectedSourceWindowID = nil
        sourceReceiverName = nil
        do {
            let key = try PairingKey(code: pairingInput)
            let target = try draftTarget()
            isSending = true
            status = "Checking the receiver and pairing code…"
            let run = UUID()
            operation = run
            Task {
                defer { isSending = false }
                do {
                    _ = try await sender.send(Transfer(), to: target.endpoint, pairing: key)
                    guard operation == run, role == .sender else { return }
                    let targetData = try JSONEncoder().encode(target)
                    try KeychainStore.save(key, account: "sender")
                    UserDefaults.standard.set(targetData, forKey: "pairedTarget")
                    savedTarget = target
                    senderKey = key
                    senderPaired = true
                    pairedTargetLabel = target.label
                    pairingInput = ""
                    status = "Paired with \(target.label). Ready to send clipboard text."
                } catch {
                    guard operation == run else { return }
                    status = Self.userMessage(error)
                }
            }
        } catch { status = error.localizedDescription }
    }
    func sendClipboard() {
        guard !preview, role == .sender, !isSending, !automaticEnabled else { return }
        guard let senderKey, let savedTarget else {
            status = "Pair with the receiver first."
            return
        }
        let pasteboard = NSPasteboard.general
        let change = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else {
            status = "The clipboard has no plain text to send."
            return
        }
        guard change == pasteboard.changeCount else {
            status = "Clipboard changed while reading it. Try Send again."
            return
        }
        do {
            let transfer = try Transfer(text: text)
            isSending = true
            status = "Sending to \(savedTarget.label)…"
            let run = UUID()
            operation = run
            Task {
                defer { isSending = false }
                do {
                    _ = try await sender.send(transfer, to: savedTarget.endpoint, pairing: senderKey)
                    guard operation == run, role == .sender else { return }
                    status = "Delivered. Use Copy received text on the Mac mini, then paste."
                } catch {
                    guard operation == run else { return }
                    status = Self.userMessage(error)
                }
            }
        } catch { status = error.localizedDescription }
    }
    func copyReceived() {
        inbox.expire()
        refreshInbox()
        guard !preview, role == .receiver, let text = inbox.text else {
            status = "There is no received text waiting."
            return
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) {
            inbox.clear()
            refreshInbox()
            status = "Copied on this Mac. Press ⌘V in your chosen app."
        } else {
            status = "Copy failed. Text is still waiting; try again."
        }
    }
    func discardReceived() {
        inbox.clear()
        refreshInbox()
        status = "Received text discarded."
    }
    private func refreshInbox() {
        pendingText = inbox.text
        expiresAt = inbox.expiresAt
    }
    func shutdown() {
        operation = UUID()
        stopAutomatic()
        sender.cancel()
        receiver.stop()
        discovery.stop()
        expiryTimer?.invalidate()
        codeTimer?.invalidate()
        inbox.clear()
        refreshInbox()
        pairingCode = nil
        pairingInput = ""
    }
    func openAccessibilitySettings() { AccessibilitySupport.openSettings() }
    func saveTestReport() {
        guard !preview else { return }
        var report = role == .sender ? automatic.testDetails : insertion.testDetails
        report["purpose"] =
            "Automatic relay test metadata only. No dictation, field contents, clipboard, pairing keys, audio or login details."
        report["role"] = role.rawValue
        report["version"] = "0.2.6-experimental"
        report["status"] = status
        report["automaticEnabled"] = String(automaticEnabled)
        if role == .sender {
            let flow = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier == "com.electron.wispr-flow"
            }
            report["wisprVersion"] =
                flow?.bundleURL.flatMap { Bundle(url: $0) }?.infoDictionary?["CFBundleShortVersionString"]
                as? String ?? "unknown"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/MacRelay")
        let folder =
            FileManager.default.fileExists(atPath: cloud.path)
            ? cloud : home.appendingPathComponent("Desktop")
        let file = folder.appendingPathComponent(
            role == .sender ? "MacRelay-test-MacBook.json" : "MacRelay-test-mini.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: file, options: .atomic)
            status =
                "Test report saved in \(folder == cloud ? "iCloud Drive → MacRelay" : "Desktop"). It contains no dictated words."
        } catch { status = "Test report could not be saved." }
    }
    func prepareSourceWindows() {
        guard !preview, role == .sender, !isSending, !automaticStarting else { return }
        guard AccessibilitySupport.isTrusted else {
            status = AutomationError.permission.localizedDescription
            return
        }
        guard let senderKey, let savedTarget else {
            status = "Pair the two Macs first."
            return
        }
        stopAutomatic()
        sourceWindows = []
        selectedSourceWindowID = nil
        sourceReceiverName = nil
        let run = UUID()
        operation = run
        isSending = true
        status = "Checking the receiver before choosing a Screen Sharing window…"
        Task {
            defer { isSending = false }
            do {
                let peer = try await sender.send(Transfer(), to: savedTarget.endpoint, pairing: senderKey)
                guard operation == run, role == .sender else { return }
                guard peer.capabilities?.contains(Acknowledgement.automaticInsertion) == true,
                    let name = peer.receiverNames?.first, !name.isEmpty
                else { throw AutomationError.receiverUpgrade }
                sourceReceiverName = name
                let choices = ScreenSharingWindowChoice.available()
                guard !choices.isEmpty else { throw AutomationError.screenSharingWindowUnavailable }
                sourceWindows = choices
                selectedSourceWindowID =
                    choices.first(where: \.isFocused)?.id ?? (choices.count == 1 ? choices.first?.id : nil)
                status =
                    "Check the receiver name below. Choose the window showing that Mac, then start automatic relay."
            } catch {
                guard operation == run else { return }
                status = error.localizedDescription
                automaticFailed = true
            }
        }
    }
    func showSelectedSourceWindow() {
        guard !preview, !automaticEnabled else { return }
        selectedSourceWindow?.show()
    }
    func toggleAutomatic() {
        guard !preview, !automaticStarting else { return }
        if automaticEnabled {
            stopAutomatic()
            status = "Automatic mode is off."
            return
        }
        guard AccessibilitySupport.requestPermission() else {
            status = AutomationError.permission.localizedDescription
            automaticFailed = true
            return
        }
        automaticFailed = false
        if role == .receiver {
            guard receiverPaired else {
                status = "Pair the two Macs first."
                return
            }
            if !receiverRunning { startReceiver() }
            guard receiverRunning else { return }
            automaticEnabled = true
            status = "Automatic insertion is on. Click into a text field, then dictate on the MacBook."
            return
        }
        guard let senderKey, let savedTarget else {
            status = "Pair the two Macs first."
            return
        }
        guard let selected = selectedSourceWindow else {
            prepareSourceWindows()
            return
        }
        guard selected.binding.isAvailable else {
            status = AutomationError.screenSharingWindowChanged.localizedDescription
            prepareSourceWindows()
            return
        }
        automaticStarting = true
        isSending = true
        let run = UUID()
        operation = run
        status = "Checking automatic mode on the mini…"
        Task {
            defer {
                automaticStarting = false
                isSending = false
            }
            do {
                try await automatic.start(
                    to: savedTarget.endpoint, pairing: senderKey, sourceWindow: selected.binding)
                guard operation == run, role == .sender else {
                    automatic.stop()
                    return
                }
                automaticEnabled = true
            } catch {
                guard operation == run else { return }
                stopAutomatic()
                status = error.localizedDescription
                automaticFailed = true
            }
        }
    }
    private func stopAutomatic() {
        automatic.stop()
        insertion.clear()
        automaticEnabled = false
        automaticFailed = false
    }
    private static func userMessage(_ error: Error) -> String {
        if let known = error as? RelayError { return known.localizedDescription }
        if error is KeychainStore.StoreError { return error.localizedDescription }
        return "Connection failed. Check both Macs and Local Network access. Delivery is unconfirmed."
    }
    enum ConfigurationError: LocalizedError {
        case invalidAddress, noReceiver
        var errorDescription: String? {
            switch self {
            case .invalidAddress:
                return "Enter a .local host name or a private local IP address, and a port from 1 to 65535."
            case .noReceiver: return "Choose a nearby receiver, or enter its local address."
            }
        }
    }
}
