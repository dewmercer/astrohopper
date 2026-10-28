import Foundation
import Network

enum TelescopeError: LocalizedError, Equatable {
    case notConnected
    case connectionFailed(String)
    case timeout
    case belowHorizon
    case notAligned

    var errorDescription: String? {
        switch self {
        case .notConnected: "The telescope isn't connected."
        case let .connectionFailed(reason): "Couldn't connect to the telescope: \(reason)"
        case .timeout: "The telescope didn't respond."
        case .belowHorizon: "That object is below the telescope's altitude limit."
        case .notAligned: "Align the telescope first."
        }
    }
}

/// A TCP connection to a SkyPortal WiFi module. Commands are sent one at a
/// time, and each waits for the matching reply from the device it was sent
/// to. Everything else on the bus (echoes of our own packets, traffic from
/// a hand controller) is ignored.
actor AUXClient {
    private var connection: NWConnection?
    private var parser = AUX.Parser()
    private var pending: (id: UUID, request: AUX.Packet, continuation: CheckedContinuation<AUX.Packet, Error>)?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var closeHandler: (@Sendable (String?) -> Void)?
    private let queue = DispatchQueue(label: "org.davemercer.AstroHopper.aux")

    /// Called once when an open connection drops, with the reason if known.
    func onClose(_ handler: @escaping @Sendable (String?) -> Void) {
        closeHandler = handler
    }

    func connect(host: String, port: UInt16 = AUX.port, timeout: Duration = .seconds(5)) async throws {
        disconnect()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw TelescopeError.connectionFailed("bad port") }
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        options.connectionTimeout = Int(timeout.components.seconds.clamped(to: 1...60))
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: NWParameters(tls: nil, tcp: options))
        connection = conn
        let once = Once()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    once.run { cont.resume() }
                case let .waiting(error), let .failed(error):
                    let first = once.run { cont.resume(throwing: TelescopeError.connectionFailed(error.localizedDescription)) }
                    if !first, case .failed = state { Task { await self?.closed(error.localizedDescription) } }
                    if first { conn.cancel() }
                case .cancelled:
                    let first = once.run { cont.resume(throwing: TelescopeError.connectionFailed("cancelled")) }
                    if !first { Task { await self?.closed(nil) } }
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout / .milliseconds(1)))) {
                if once.run({ cont.resume(throwing: TelescopeError.timeout) }) { conn.cancel() }
            }
        }
        receive(on: conn)
    }

    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        parser = AUX.Parser()
        if let p = pending {
            pending = nil
            p.continuation.resume(throwing: TelescopeError.notConnected)
        }
    }

    var isConnected: Bool { connection != nil }

    /// Sends a command and returns the device's reply.
    func send(_ packet: AUX.Packet, timeout: Duration = .milliseconds(1500)) async throws -> AUX.Packet {
        await lock()
        defer { unlock() }
        guard let conn = connection else { throw TelescopeError.notConnected }
        let id = UUID()
        return try await withCheckedThrowingContinuation { cont in
            pending = (id, packet, cont)
            conn.send(content: Data(packet.bytes), completion: .contentProcessed { [weak self] error in
                if let error { Task { await self?.fail(id, TelescopeError.connectionFailed(error.localizedDescription)) } }
            })
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.fail(id, TelescopeError.timeout)
            }
        }
    }

    // MARK: Internals

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { await self?.received(data.map { [UInt8]($0) } ?? [], from: conn, done: isComplete || error != nil) }
        }
    }

    private func received(_ bytes: [UInt8], from conn: NWConnection, done: Bool) {
        guard conn === connection else { return }
        for packet in parser.feed(bytes) {
            if let p = pending,
               packet.destination == AUX.Device.app.rawValue,
               packet.source == p.request.destination,
               packet.command == p.request.command {
                pending = nil
                p.continuation.resume(returning: packet)
            }
        }
        if done {
            closed("The connection was closed.")
        } else {
            receive(on: conn)
        }
    }

    private func closed(_ reason: String?) {
        guard connection != nil else { return }
        disconnect()
        closeHandler?(reason)
    }

    private func fail(_ id: UUID, _ error: Error) {
        guard let p = pending, p.id == id else { return }
        pending = nil
        p.continuation.resume(throwing: error)
    }

    private func lock() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    private func unlock() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Runs a closure at most once across threads; `run` reports whether it ran.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    @discardableResult
    func run(_ body: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        body()
        return true
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
