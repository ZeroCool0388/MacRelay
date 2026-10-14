import AppKit
import SwiftUI

@main
@MainActor
struct MacRelayApp: App {
    @StateObject private var model = RelayModel()
    var body: some Scene {
        MenuBarExtra(
            "MacRelay",
            systemImage: model.automaticFailed
                ? "exclamationmark.triangle"
                : model.pendingText == nil ? "arrow.left.arrow.right" : "tray.fill"
        ) {
            RelayPanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
struct RelayPanel: View {
    @ObservedObject var model: RelayModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.title).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacRelay").font(.headline)
                        Text("Your text. Between your Macs.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v0.2.5 test").font(.caption).foregroundStyle(.secondary)
                }
                Picker("This Mac", selection: $model.role) {
                    ForEach(RelayModel.Role.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(model.isSending)
                Text(model.role == .sender ? "Use Send on your MacBook." : "Use Receive on your Mac mini.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Status: \(model.status)")
                automaticControls
                if model.role == .sender {
                    if model.senderPaired {
                        DisclosureGroup("Manual transfer and pairing") { senderControls }
                    } else {
                        senderControls
                    }
                } else {
                    receiverControls
                }
                Divider()
                Text(model.hotKeyStatus).font(.caption).foregroundStyle(.secondary)
                Text("No saved text history. Automatic mode starts off each time you open MacRelay.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Quit") {
                        model.shutdown()
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain).font(.caption)
                }
            }
            .padding(18)
        }
        .frame(width: 390, height: model.role == .sender ? 620 : 550)
        .onDisappear {
            model.hidePairingCode()
            model.revealText = false
        }
        .onChange(of: model.pendingText) { _, _ in model.revealText = false }
        .alert("Replace this pairing?", isPresented: $model.confirmReplacement) {
            Button("Replace pairing", role: .destructive) { model.generatePairingCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The old code will stop working. Any waiting text will be discarded. Pair the MacBook again with the new code."
            )
        }
    }
    private var automaticControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wispr through Screen Sharing").font(.headline)
            Text("Experimental — needs a live dictation test.").font(.caption).foregroundStyle(.secondary)
            if model.role == .sender, !model.sourceWindows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Receiver: \(model.sourceReceiverName ?? "Paired Mac")", systemImage: "lock.shield")
                    Text("Choose the Screen Sharing window showing this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Window", selection: $model.selectedSourceWindowID) {
                        Text("Choose window").tag(UUID?.none)
                        ForEach(model.sourceWindows) { window in
                            Text(window.label).tag(Optional(window.id))
                        }
                    }.disabled(model.automaticEnabled || model.isSending)
                    HStack {
                        Button("Show window") { model.showSelectedSourceWindow() }
                            .disabled(model.selectedSourceWindowID == nil || model.automaticEnabled)
                        Button("Change window") { model.prepareSourceWindows() }.disabled(model.isSending)
                    }.font(.caption)
                }
            }
            Button(
                model.automaticStarting
                    ? "Checking…"
                    : model.automaticEnabled
                        ? "Turn automatic mode off"
                        : model.role == .sender
                            ? (model.sourceWindows.isEmpty
                                ? "Choose Screen Sharing window" : "Relay Wispr from this window")
                            : "Insert dictation automatically"
            ) {
                model.toggleAutomatic()
            }.buttonStyle(.borderedProminent).disabled(model.automaticStarting || model.isSending)
            Text(
                model.role == .sender
                    ? "Choose the mini’s Screen Sharing window once. Then use your usual Wispr dictation key while that window is focused."
                    : "Words go into the focused text field. Password fields and known terminal apps are blocked. MacRelay never presses Enter."
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open Accessibility settings") { model.openAccessibilitySettings() }
                Spacer()
                Button("Save test report") { model.saveTestReport() }
            }.font(.caption)
            Text(
                "Allow MacRelay on both Macs, then turn automatic mode on. A temporary clipboard change may be needed on the mini; it is restored if no other app has changed it."
            )
            .font(.caption).foregroundStyle(.secondary)
            Divider()
        }
    }
    private var senderControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.senderPaired {
                Label("Paired: \(model.pairedTargetLabel ?? "Receiver")", systemImage: "lock.shield")
                    .font(.callout)
                Button(model.isSending ? "Please wait…" : "Send clipboard text  ⇧⌥⌘S") {
                    model.sendClipboard()
                }
                .buttonStyle(.bordered).disabled(model.isSending || model.automaticEnabled)
                Text("Manual fallback: sends the clipboard once. Turn automatic mode off to use it.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
            }
            Text(model.senderPaired ? "Pair with a receiver again" : "Pair with your Mac mini").font(
                .headline)
            Toggle("Enter local address manually", isOn: $model.useAddress)
            if model.useAddress {
                TextField("Local host name or IP address", text: $model.host)
                TextField("Port (45821 by default)", text: $model.port)
            } else {
                Picker("Receiver", selection: $model.selectedDevice) {
                    Text("Choose receiver").tag("")
                    ForEach(model.devices) { device in Text(device.name).tag(device.id) }
                }
                HStack {
                    Text(model.discoveryStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { model.startDiscovery() }
                }
            }
            SecureField("MR1 pairing code from receiver", text: $model.pairingInput)
                .textFieldStyle(.roundedBorder)
            Button("Verify and pair") { model.pairSender() }
                .disabled(model.isSending || model.pairingInput.isEmpty)
            Text("Find the code in MacRelay on the Mac mini. Transfer it through a route you trust.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(model.isSending)
    }
    private var receiverControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.receiverPaired {
                Label("Pairing key saved on this Mac", systemImage: "lock.shield").font(.callout)
                Button(model.receiverRunning ? "Stop receiving" : "Start receiving") {
                    model.toggleReceiver()
                }
                .buttonStyle(.borderedProminent)
            }
            Button(model.receiverPaired ? "Replace pairing code…" : "Create pairing code and start") {
                if model.receiverPaired {
                    model.confirmReplacement = true
                } else {
                    model.generatePairingCode()
                }
            }
            if let code = model.pairingCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pairing code — keep private").font(.caption).bold()
                    Text(code).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Copy code") { model.copyPairingCode() }
                        Button("Hide") { model.hidePairingCode() }
                    }
                    Text(
                        "Copy code replaces this Mac's clipboard by request. The code hides when this panel closes or after two minutes."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            if model.pendingText != nil {
                Label("Text waiting", systemImage: "tray.fill").font(.headline)
                if let expires = model.expiresAt {
                    Text("Expires \(expires.formatted(date: .omitted, time: .shortened))").font(.caption)
                }
                HStack {
                    Button("Copy received text  ⇧⌥⌘R") { model.copyReceived() }.buttonStyle(
                        .borderedProminent)
                    Button("Discard") { model.discardReceived() }
                }
                Toggle("Show text", isOn: $model.revealText)
                if model.revealText, let text = model.pendingText {
                    ScrollView { Text(text).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 80)
                }
            } else {
                Label("No text waiting", systemImage: "tray").foregroundStyle(.secondary)
            }
            Text(
                "Copy is an explicit clipboard change. Then use ⌘V in your chosen app. New text cannot replace a waiting item."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
