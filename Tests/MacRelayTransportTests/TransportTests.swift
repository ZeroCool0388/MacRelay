import Foundation
import MacRelayCore
import Network
import Testing

@testable import MacRelayTransport

@Suite(.serialized)
@MainActor
struct TransportTests {
    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw RelayError.timedOut }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    private func listeningReceiver(key: PairingKey, handler: @escaping (Transfer) throws -> Acknowledgement)
        async throws -> (RelayReceiver, NWEndpoint)
    {
        let receiver = RelayReceiver()
        receiver.onTransfer = handler
        var boundPort: UInt16?
        receiver.onReady = { port in boundPort = port }
        try receiver.start(pairing: key, port: 0, advertise: false)
        do { try await waitFor { boundPort != nil } } catch {
            receiver.stop()
            throw error
        }
        let port = try #require(boundPort)
        receiver.onReady = nil
        return (receiver, .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
    }

    @Test
    func realLoopbackPairSendBusyAndProbe() async throws {
        let key = PairingKey()
        var inbox = Inbox()
        let (receiver, endpoint) = try await listeningReceiver(key: key) { try inbox.receive($0) }
        defer { receiver.stop() }
        let sender = RelaySender()
        let paired = try await sender.send(Transfer(), to: endpoint, pairing: key)
        #expect(paired.status == .paired)
        #expect(inbox.text == nil)
        let text = "Loopback transfer: 🏌️\nPlain text remains local."
        let delivered = try await sender.send(Transfer(text: text), to: endpoint, pairing: key)
        #expect(delivered.status == .accepted)
        #expect(inbox.text == text)
        await #expect(throws: RelayError.busy) {
            _ = try await sender.send(Transfer(text: "must not replace"), to: endpoint, pairing: key)
        }
        #expect(inbox.text == text)
        inbox.clear()
        _ = try await sender.send(Transfer(text: "after discard"), to: endpoint, pairing: key)
        #expect(inbox.text == "after discard")
    }

    @Test
    func wrongKeyDoesNotReachReceiver() async throws {
        var received = false
        let (receiver, endpoint) = try await listeningReceiver(key: PairingKey()) { transfer in
            received = true
            return Acknowledgement(id: transfer.id, status: .accepted)
        }
        defer { receiver.stop() }
        await #expect(throws: RelayError.authenticationFailed) {
            _ = try await RelaySender().send(Transfer(text: "private"), to: endpoint, pairing: PairingKey())
        }
        #expect(!received)
    }

    @Test
    func idleConnectionTimesOut() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        var serverConnection: NWConnection?
        var ready = false
        listener.stateUpdateHandler = { state in
            Task { @MainActor in if case .ready = state { ready = true } }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                serverConnection = connection
                connection.start(queue: .main)  // Intentionally never sends a hello.
            }
        }
        listener.start(queue: .main)
        defer {
            serverConnection?.cancel()
            listener.cancel()
        }
        try await waitFor { ready }
        let port = try #require(listener.port)
        let channel = FramedConnection(NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        defer { channel.close() }
        try await channel.start(timeout: 0.2)
        await #expect(throws: RelayError.timedOut) { _ = try await channel.receive() }
    }

    @Test
    func splitHeaderAndBodyAreReassembled() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        var serverConnection: NWConnection?
        var ready = false
        let payload = Data("A split TCP message".utf8)
        let frame = try Framing.header(forLength: payload.count) + payload
        listener.stateUpdateHandler = { state in
            Task { @MainActor in if case .ready = state { ready = true } }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                serverConnection = connection
                connection.stateUpdateHandler = { state in
                    if case .ready = state {
                        connection.send(
                            content: frame.prefix(2),
                            completion: .contentProcessed { _ in
                                connection.send(
                                    content: frame.dropFirst(2).prefix(3),
                                    completion: .contentProcessed { _ in
                                        connection.send(
                                            content: frame.dropFirst(5),
                                            completion: .contentProcessed { _ in })
                                    })
                            })
                    }
                }
                connection.start(queue: .main)
            }
        }
        listener.start(queue: .main)
        defer {
            serverConnection?.stateUpdateHandler = nil
            serverConnection?.cancel()
            listener.cancel()
        }
        try await waitFor { ready }
        let port = try #require(listener.port)
        let channel = FramedConnection(NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        defer { channel.close() }
        try await channel.start()
        #expect(try await channel.receive() == payload)
    }
}

// Opt in on a Mac whose Local Network permission allows Bonjour.
@Suite
@MainActor
struct BonjourTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACRELAY_TEST_BONJOUR"] == "1"))
    func discoversReceiverAndVerifiesPairing() async throws {
        let receiver = RelayReceiver()
        let discovery = ReceiverDiscovery()
        let key = PairingKey()
        var ready = false
        var devices: [DiscoveredReceiver] = []
        receiver.onReady = { _ in ready = true }
        receiver.onTransfer = { transfer in
            #expect(transfer.kind == .probe)
            return Acknowledgement(id: transfer.id, status: .paired)
        }
        try receiver.start(pairing: key, port: 0, advertise: true)
        defer {
            discovery.stop()
            receiver.stop()
        }
        let deadline = Date().addingTimeInterval(8)
        while !ready {
            guard Date() < deadline else { throw RelayError.timedOut }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        discovery.onResults = { devices = $0 }
        discovery.start()
        while devices.isEmpty {
            guard Date() < deadline else { throw RelayError.timedOut }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // Pairing authentication identifies our listener even if another MacRelay is advertised.
        var authenticated = false
        for device in devices {
            if let ack = try? await RelaySender().send(Transfer(), to: device.endpoint, pairing: key) {
                authenticated = ack.status == .paired
                if authenticated { break }
            }
        }
        #expect(authenticated)
    }
}
