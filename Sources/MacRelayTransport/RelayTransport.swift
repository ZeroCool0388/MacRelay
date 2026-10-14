import Foundation
import MacRelayCore
import Network

/// All state and Network callbacks run on the main queue; text is never logged.
@MainActor
final class FramedConnection {
    let connection: NWConnection
    private var readiness: CheckedContinuation<Void, Error>?
    private var ready = false
    private var closed = false
    private var timedOut = false
    private var deadline: DispatchWorkItem?

    init(_ connection: NWConnection) { self.connection = connection }

    func start(timeout: TimeInterval = 10) async throws {
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timedOut = true
            self.close()
        }
        deadline = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
        try await withCheckedThrowingContinuation { continuation in
            readiness = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.ready = true
                        self.finishReadiness(nil)
                    case .failed:
                        self.finishReadiness(RelayError.disconnected)
                        self.close()
                    case .cancelled:
                        self.finishReadiness(self.timedOut ? RelayError.timedOut : RelayError.disconnected)
                    default: break
                    }
                }
            }
            connection.start(queue: .main)
        }
    }

    private func finishReadiness(_ error: Error?) {
        guard let continuation = readiness else { return }
        readiness = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func send(_ data: Data) async throws {
        guard ready, !closed else { throw failure }
        let framed = try Framing.header(forLength: data.count) + data
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: framed,
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        if self?.closed != false || error != nil {
                            continuation.resume(throwing: self?.failure ?? RelayError.disconnected)
                        } else {
                            continuation.resume()
                        }
                    }
                })
        }
    }

    func receive(maximum: Int = Framing.maximumBytes) async throws -> Data {
        let header = try await readExactly(4)
        let count = try Framing.length(from: header, maximum: maximum)
        return try await readExactly(count)
    }

    private func readExactly(_ count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            guard !closed else { throw failure }
            let remaining = count - result.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
                    [weak self] data, _, complete, error in
                    Task { @MainActor in
                        if self?.closed != false || error != nil {
                            continuation.resume(throwing: self?.failure ?? RelayError.disconnected)
                        } else if let data, !data.isEmpty {
                            continuation.resume(returning: data)
                        } else if complete {
                            continuation.resume(throwing: RelayError.disconnected)
                        } else {
                            continuation.resume(throwing: RelayError.invalidFrame)
                        }
                    }
                }
            }
            result.append(chunk)
        }
        return result
    }

    private var failure: RelayError { timedOut ? .timedOut : .disconnected }
    func close() {
        guard !closed else { return }
        closed = true
        deadline?.cancel()
        deadline = nil
        finishReadiness(failure)
        connection.cancel()
    }
}

@MainActor
public final class RelayReceiver {
    nonisolated public static let serviceType = "_macrelay._tcp"
    nonisolated public static let defaultPort: UInt16 = 45821
    private var listener: NWListener?
    private var sessions: [UUID: FramedConnection] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generation = UUID()
    public var onState: ((String) -> Void)?
    public var onReady: ((UInt16) -> Void)?
    public var onTransfer: ((Transfer) async throws -> Acknowledgement)?

    public init() {}
    public func start(pairing: PairingKey, port: UInt16 = defaultPort, advertise: Bool = true) throws {
        stop()
        let run = generation
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        if advertise {
            // Avoid exposing the user's personal computer name in discovery.
            listener.service = NWListener.Service(name: "MacRelay Receiver", type: Self.serviceType)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                switch state {
                case .ready:
                    self.onState?("Receiver is listening.")
                    if let port = listener?.port?.rawValue { self.onReady?(port) }
                case .failed:
                    self.stop()
                    self.onState?("Receiver unavailable. Check the port and Local Network permission.")
                case .waiting:
                    self.onState?("Waiting for network permission or a usable network.")
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.generation == run, self.sessions.count < 4,
                    Self.isLocal(connection.endpoint)
                else {
                    connection.cancel()
                    return
                }
                let id = UUID()
                let channel = FramedConnection(connection)
                self.sessions[id] = channel
                self.tasks[id] = Task { [weak self] in
                    defer {
                        channel.close()
                        self?.sessions.removeValue(forKey: id)
                        self?.tasks.removeValue(forKey: id)
                    }
                    do {
                        try await channel.start()
                        let handshake = ReceiverHandshake(pairing: pairing)
                        try await channel.send(JSONEncoder().encode(handshake.hello))
                        let clientData = try await channel.receive(maximum: 2048)
                        let client = try JSONDecoder().decode(ClientHello.self, from: clientData)
                        let keys = try handshake.accept(client)
                        let transfer = try keys.openTransfer(await channel.receive())
                        guard let self, self.generation == run, !Task.isCancelled,
                            let handler = self.onTransfer
                        else { throw RelayError.disconnected }
                        let ack = try await handler(transfer)
                        try await channel.send(keys.sealAcknowledgement(ack))
                    } catch {
                        // No payloads, pairing codes, network endpoints or raw errors in logs.
                    }
                }
            }
        }
        listener.start(queue: .main)
    }
    private static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return LocalAddress.isAllowedIPv4(address.rawValue)
        case .ipv6(let address): return LocalAddress.isAllowedIPv6(address.rawValue)
        default: return false
        }
    }
    public func stop() {
        generation = UUID()
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for task in tasks.values { task.cancel() }
        for channel in sessions.values { channel.close() }
        tasks.removeAll()
        sessions.removeAll()
    }
}

@MainActor
public final class RelaySender {
    private var active: FramedConnection?
    public init() {}
    public func cancel() { active?.close() }
    public func send(_ transfer: Transfer, to endpoint: NWEndpoint, pairing: PairingKey) async throws
        -> Acknowledgement
    {
        guard active == nil else { throw RelayError.busy }
        try transfer.validate()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let channel = FramedConnection(NWConnection(to: endpoint, using: parameters))
        active = channel
        defer {
            channel.close()
            active = nil
        }
        try await channel.start()
        let helloData = try await channel.receive(maximum: 2048)
        let server = try JSONDecoder().decode(ServerHello.self, from: helloData)
        let handshake = try SenderHandshake(server: server, pairing: pairing)
        try await channel.send(JSONEncoder().encode(handshake.hello))
        try await channel.send(handshake.keys.sealTransfer(transfer))
        let ack = try handshake.keys.openAcknowledgement(await channel.receive(maximum: 2048))
        try ack.validate(for: transfer)
        return ack
    }
}

public struct DiscoveredReceiver: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint
}

@MainActor
public final class ReceiverDiscovery {
    private var browser: NWBrowser?
    private var generation = UUID()
    public var onResults: (([DiscoveredReceiver]) -> Void)?
    public var onStatus: ((String) -> Void)?
    public init() {}
    public func start() {
        stop()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let run = generation
        let browser = NWBrowser(
            for: .bonjour(type: RelayReceiver.serviceType, domain: "local."), using: parameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                let receivers = results.compactMap { result -> DiscoveredReceiver? in
                    guard case .service(let name, let type, let domain, _) = result.endpoint else {
                        return nil
                    }
                    return DiscoveredReceiver(
                        id: name + "|" + type + "|" + domain,
                        name: name, endpoint: result.endpoint)
                }.sorted { $0.id < $1.id }
                let unique = Dictionary(grouping: receivers, by: \.id).values.compactMap(\.first)
                    .sorted { $0.id < $1.id }
                self.onResults?(unique)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                switch state {
                case .ready: self.onStatus?("Searching the local network…")
                case .waiting, .failed:
                    self.onStatus?(
                        "Discovery unavailable. Allow Local Network access or enter a local address.")
                default: break
                }
            }
        }
        browser.start(queue: .main)
    }
    public func stop() {
        generation = UUID()
        browser?.browseResultsChangedHandler = nil
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil
        onResults?([])
    }
}
