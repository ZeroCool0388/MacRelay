import AppKit
import SwiftUI

@main
@MainActor
struct MacRelayApp: App {
    @StateObject private var model = RelayModel()
    var body: some Scene {
        MenuBarExtra(
            "MacRelay", systemImage: model.pendingText == nil ? "arrow.left.arrow.right" : "tray.fill"
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
                    Text("v0.1").font(.caption).foregroundStyle(.secondary)
                }
                Picker("This Mac", selection: $model.role) {
                    ForEach(RelayModel.Role.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(model.isSending)
                Text(model.role == .sender ? "Use Send on your MacBook." : "Use Receive on your Mac mini.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.role == .sender { senderControls } else { receiverControls }
                Divider()
                Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Status: \(model.status)")
                Text(model.hotKeyStatus).font(.caption).foregroundStyle(.secondary)
                Text("Text stays in memory. Receiving does not change your clipboard.")
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
    private var senderControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.senderPaired {
                Label("Paired: \(model.pairedTargetLabel ?? "Receiver")", systemImage: "lock.shield")
                    .font(.callout)
                Button(model.isSending ? "Please wait…" : "Send clipboard text  ⇧⌥⌘S") {
                    model.sendClipboard()
                }
                .buttonStyle(.borderedProminent).disabled(model.isSending)
                Text("Sends the clipboard's current plain text once. It does not read Wispr history.")
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
