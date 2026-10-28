import Darwin
import Foundation
import Observation

/// Optional control of a Celestron mount through a SkyPortal WiFi module.
///
/// The mount is aligned by AstroHopper itself: each time the user confirms
/// an alignment star, the encoder readings are stored with the star's true
/// position and fitted like the phone's alignment. Goto then converts the
/// target into encoder positions, slews fast and then precisely, and keeps
/// it centered by setting each axis's tracking rate.
@MainActor
@Observable
final class TelescopeController {
    enum ConnectionMode: String, CaseIterable, Identifiable {
        case direct, network
        var id: String { rawValue }
        var label: String {
            switch self {
            case .direct: "Direct"
            case .network: "WiFi Network"
            }
        }
    }

    enum State: Equatable {
        case disconnected, connecting, connected
    }

    enum Activity: Equatable {
        case idle, slewing, tracking, moving
    }

    // MARK: Settings

    @ObservationIgnored private let defaults = UserDefaults.standard
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "scope_enabled"); if !enabled { disconnect() } } }
    var mountType: MountType {
        didSet {
            defaults.set(mountType.rawValue, forKey: "scope_mount")
            if mountType != oldValue { resetAlignment() }
        }
    }
    var connectionMode: ConnectionMode { didSet { defaults.set(connectionMode.rawValue, forKey: "scope_connection") } }
    var networkHost: String { didSet { defaults.set(networkHost, forKey: "scope_host") } }
    var trackAfterGoto: Bool { didSet { defaults.set(trackAfterGoto, forKey: "scope_track") } }
    /// Goto refuses targets lower than this, in degrees. Set by the app
    /// from its altitude limits (the horizon when there is no minimum).
    var minAltitude: Double = 0
    /// The telescope never points higher than this, in degrees; nil is no
    /// limit. Set by the app from its altitude limits.
    var maxAltitude: Double?

    var altitudeLimit: Double? { maxAltitude }
    /// Manual slew speed, 1 (slowest) to 9.
    var slewRate: Int { didSet { defaults.set(slewRate, forKey: "scope_slew_rate") } }

    var host: String { connectionMode == .direct ? AUX.defaultHost : networkHost }
    /// Always the module's port 2000, except in tests.
    @ObservationIgnored var port = AUX.port

    // MARK: State

    private(set) var state: State = .disconnected
    private(set) var activity: Activity = .idle
    private(set) var lastError: String?
    /// Latest raw axis angles, degrees.
    private(set) var axes: (axis1: Double, axis2: Double)?
    private(set) var model: MountModel?
    private(set) var samples: [MountSample] = []
    private(set) var alignmentError: Double?
    /// Name of the object being slewed to or tracked.
    private(set) var targetName: String?
    private(set) var scanning = false
    private(set) var foundHosts: [String] = []

    var isConnected: Bool { state == .connected }
    var isAligned: Bool { model != nil }

    /// Where the telescope points, east-north-up, once aligned.
    var pointingENU: Vec3? {
        guard let model, let axes else { return nil }
        return model.direction(axes.axis1, axes.axis2)
    }

    @ObservationIgnored private let client = AUXClient()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var motionTask: Task<Void, Never>?
    /// While tracking, the user's manual correction relative to the target.
    @ObservationIgnored private var trackOffset = (axis1: 0.0, axis2: 0.0)
    @ObservationIgnored private var trackTarget: (@MainActor (Date) -> Vec3)?
    @ObservationIgnored private var limitGuard: Task<Void, Never>?
    /// The telescope's altitude before the mount is aligned; the app supplies
    /// the phone's, since the phone rides on the tube.
    @ObservationIgnored var fallbackAltitude: (@MainActor () -> Double?)?

    /// The telescope's altitude in degrees: from the mount once it is
    /// aligned, otherwise from the phone.
    var currentAltitude: Double? {
        if let p = pointingENU { return altitude(p) }
        return fallbackAltitude?()
    }
    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "scope_enabled")
        mountType = MountType(rawValue: d.string(forKey: "scope_mount") ?? "") ?? .altAz
        connectionMode = ConnectionMode(rawValue: d.string(forKey: "scope_connection") ?? "") ?? .direct
        networkHost = d.string(forKey: "scope_host") ?? ""
        trackAfterGoto = d.object(forKey: "scope_track") as? Bool ?? true
        slewRate = d.object(forKey: "scope_slew_rate") as? Int ?? 5
    }

    // MARK: Connection

    func connect() {
        guard state == .disconnected else { return }
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            lastError = "Enter the telescope's address, or tap Find on Network."
            return
        }
        state = .connecting
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                await client.onClose { [weak self] reason in
                    Task { @MainActor in self?.connectionLost(reason) }
                }
                try await client.connect(host: host, port: port)
                // make sure a motor controller answers
                _ = try await client.send(AUX.Packet(.getVersion, to: .azimuth))
                state = .connected
                startPolling()
            } catch {
                await client.disconnect()
                state = .disconnected
                lastError = error.localizedDescription
            }
        }
    }

    func disconnect() {
        pollTask?.cancel()
        motionTask?.cancel()
        pollTask = nil
        motionTask = nil
        activity = .idle
        targetName = nil
        state = .disconnected
        axes = nil
        Task { await client.disconnect() }
    }

    private func connectionLost(_ reason: String?) {
        guard state != .disconnected else { return }
        disconnect()
        lastError = reason ?? "The connection to the telescope was lost."
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if activity != .tracking {  // the tracking loop reads positions itself
                    _ = try? await readAxes()
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: Commands

    @discardableResult
    func readAxes() async throws -> (axis1: Double, axis2: Double) {
        let a1 = try await client.send(AUX.Packet(.getPosition, to: .azimuth)).value
        let a2 = try await client.send(AUX.Packet(.getPosition, to: .altitude)).value
        let result = (MountModel.degrees(steps: a1), MountModel.degrees(steps: a2))
        axes = result
        return result
    }

    private func device(_ axis: Int) -> AUX.Device { axis == 1 ? .azimuth : .altitude }

    private func goto(_ a1: Double, _ a2: Double, fast: Bool) async throws {
        let command: AUX.Command = fast ? .gotoFast : .gotoSlow
        for (axis, angle) in [(1, a1), (2, a2)] {
            _ = try await client.send(AUX.Packet(command, to: device(axis), data: AUX.encode(MountModel.steps(degrees: angle))))
        }
    }

    private func slewDone() async throws -> Bool {
        for axis in [1, 2] {
            let reply = try await client.send(AUX.Packet(.slewDone, to: device(axis)))
            if reply.value != 0xFF { return false }
        }
        return true
    }

    /// Tracking rate for one axis in raw degrees per second; the AUX unit is
    /// 1/1024 arcsecond per second.
    private func setRate(_ axis: Int, _ degreesPerSecond: Double) async throws {
        let value = UInt32(min(abs(degreesPerSecond) * 3600 * 1024, Double(0xFF_FFFF)).rounded())
        let command: AUX.Command = degreesPerSecond < 0 ? .setNegGuideRate : .setPosGuideRate
        _ = try await client.send(AUX.Packet(command, to: device(axis), data: AUX.encode(value)))
    }

    private func move(_ axis: Int, _ rate: Int) async throws {
        let command: AUX.Command = rate < 0 ? .moveNeg : .movePos
        _ = try await client.send(AUX.Packet(command, to: device(axis), data: [UInt8(min(abs(rate), 9))]))
    }

    private func halt() async {
        for axis in [1, 2] {
            try? await move(axis, 0)
            try? await setRate(axis, 0)
        }
    }

    // MARK: Alignment

    func clearError() { lastError = nil }

    func resetAlignment() {
        samples = []
        model = nil
        alignmentError = nil
    }

    /// Records the mount's position for an alignment star the user just
    /// confirmed. `star` is the star's east-north-up direction now. With
    /// `restart`, this is the first star of a new alignment.
    func addAlignmentStar(index: Int, star: Vec3, latitude: Double, restart: Bool) {
        guard isConnected else { return }
        if restart { resetAlignment() }
        Task {
            do {
                let a = try await readAxes()
                samples.append(MountSample(index: index, axis1: a.axis1, axis2: a.axis2, star: star))
                model = MountModel.fit(mountType, latitude: latitude, samples: samples)
                alignmentError = samples.count >= 2 ? model?.rmsError(samples) : nil
            } catch {
                lastError = "Couldn't read the telescope's position: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Goto and tracking

    /// Slews to a target. `target` gives its east-north-up direction at any
    /// moment, so it is recomputed for the final approach and for tracking.
    func goto(name: String, target: @escaping @MainActor (Date) -> Vec3) {
        guard isConnected else { lastError = TelescopeError.notConnected.localizedDescription; return }
        guard let model else { lastError = TelescopeError.notAligned.localizedDescription; return }
        guard altitude(target(Date())) >= minAltitude else {
            lastError = TelescopeError.belowHorizon.localizedDescription
            return
        }
        if let limit = altitudeLimit, altitude(target(Date())) > limit {
            lastError = TelescopeError.aboveLimit.localizedDescription
            return
        }
        motionTask?.cancel()
        lastError = nil
        targetName = name
        trackTarget = target
        trackOffset = (0, 0)
        activity = .slewing
        motionTask = Task {
            do {
                await halt()
                for fast in [true, false] {
                    let enu = target(Date())
                    guard altitude(enu) >= minAltitude else { throw TelescopeError.belowHorizon }
                    let a = model.axes(for: enu)
                    if let limit = altitudeLimit {
                        guard altitude(enu) <= limit else { throw TelescopeError.aboveLimit }
                        let start = try await readAxes()
                        if Self.pathExceeds(limit, model: model, from: start, to: a) {
                            throw TelescopeError.pathAboveLimit
                        }
                    }
                    try await goto(a.axis1, a.axis2, fast: fast)
                    try await waitForSlew()
                }
                if trackAfterGoto {
                    activity = .tracking
                    try await track()
                } else {
                    activity = .idle
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    lastError = error.localizedDescription
                    activity = .idle
                    await halt()
                }
            }
        }
    }

    private func waitForSlew() async throws {
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(400))
            _ = try? await readAxes()
            // backstop in case the mount's path differs from the predicted one
            if let limit = altitudeLimit, let alt = currentAltitude, alt > limit + 0.3 {
                await halt()
                throw TelescopeError.aboveLimit
            }
            if try await slewDone() { return }
        }
        throw TelescopeError.timeout
    }

    /// Keeps the target centered: each axis runs at the target's predicted
    /// rate plus a correction that removes any position error over a few
    /// seconds.
    private func track() async throws {
        guard let model, let target = trackTarget else { return }
        while !Task.isCancelled {
            let now = Date()
            let current = try await readAxes()
            let enu = target(now)
            if altitude(enu) < minAltitude {
                await halt()
                activity = .idle
                lastError = "Tracking stopped: \(targetName ?? "the target") went below the altitude limit."
                return
            }
            if let limit = altitudeLimit, altitude(enu) > limit {
                await halt()
                activity = .idle
                lastError = "Tracking stopped: \(targetName ?? "the target") rose above the \(Int(limit))° maximum altitude."
                return
            }
            let here = model.axes(for: enu)
            let ahead = model.axes(for: target(now.addingTimeInterval(10)))
            let rates = Self.trackingRates(here: here, ahead: ahead, current: current, offset: trackOffset)
            try await setRate(1, rates.axis1)
            try await setRate(2, rates.axis2)
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// Degrees per second for each axis: the motion over the next 10 s,
    /// plus the remaining error spread over 4 s.
    nonisolated static func trackingRates(here: (axis1: Double, axis2: Double), ahead: (axis1: Double, axis2: Double),
                                          current: (axis1: Double, axis2: Double),
                                          offset: (axis1: Double, axis2: Double)) -> (axis1: Double, axis2: Double) {
        func rate(_ h: Double, _ a: Double, _ c: Double, _ o: Double) -> Double {
            MountModel.wrap180(a - h) / 10 + MountModel.wrap180(h + o - c) / 4
        }
        return (rate(here.axis1, ahead.axis1, current.axis1, offset.axis1),
                rate(here.axis2, ahead.axis2, current.axis2, offset.axis2))
    }

    private func altitude(_ enu: Vec3) -> Double { asin(max(-1, min(1, enu.z))) * rad2deg }

    /// Whether a goto from one set of axis angles to another would pass
    /// above `limit`. Each motor runs straight to its new encoder count, so
    /// the path is a straight line in encoder steps.
    nonisolated static func pathExceeds(_ limit: Double, model: MountModel, from start: (axis1: Double, axis2: Double),
                                        to end: (axis1: Double, axis2: Double)) -> Bool {
        func unsigned(_ d: Double) -> Double { d < 0 ? d + 360 : d }
        let s1 = unsigned(start.axis1), e1 = unsigned(end.axis1)
        let s2 = unsigned(start.axis2), e2 = unsigned(end.axis2)
        for i in 0...40 {
            let t = Double(i) / 40
            let d = model.direction(s1 + (e1 - s1) * t, s2 + (e2 - s2) * t)
            if asin(max(-1, min(1, d.z))) * rad2deg > limit + 0.01 { return true }
        }
        return false
    }

    /// Approximate speed of the mount's manual slew rates, degrees per second.
    nonisolated static func slewSpeed(rate: Int) -> Double {
        let speeds = [0.0, 0.0021, 0.0042, 0.0083, 0.033, 0.067, 0.5, 1, 2, 4]
        return speeds[max(0, min(9, rate))]
    }

    /// Turns tracking on or off, now and for later gotos. Turning it on
    /// after a goto tracks that object; turning it off leaves the telescope
    /// where it is. During a slew it applies when the slew finishes.
    func setTracking(_ on: Bool) {
        trackAfterGoto = on
        switch (on, activity) {
        case (false, .tracking):
            motionTask?.cancel()
            motionTask = nil
            activity = .idle
            Task { await halt() }
        case (true, .idle):
            guard isConnected, trackTarget != nil else { return }
            motionTask?.cancel()
            trackOffset = (0, 0)
            activity = .tracking
            motionTask = Task {
                do {
                    try await track()
                } catch is CancellationError {
                } catch {
                    if !Task.isCancelled {
                        lastError = error.localizedDescription
                        activity = .idle
                        await halt()
                    }
                }
            }
        default:
            break
        }
    }

    func stop() {
        motionTask?.cancel()
        motionTask = nil
        activity = .idle
        targetName = nil
        trackTarget = nil
        Task { await halt() }
    }

    // MARK: Manual slewing

    /// Direction on the slew pad: up/down move the altitude (or declination)
    /// axis, left/right the azimuth (or hour angle) axis.
    enum Direction { case up, down, left, right }

    @ObservationIgnored private var resumeTracking = false

    func startMove(_ direction: Direction) {
        guard isConnected else { return }
        let signs = model?.signs ?? (axis1: 1, axis2: 1)
        let (axis, sign): (Int, Double) = switch direction {
        case .up: (2, signs.axis2)
        case .down: (2, -signs.axis2)
        case .right: (1, signs.axis1)
        case .left: (1, -signs.axis1)
        }
        resumeTracking = activity == .tracking
        motionTask?.cancel()
        activity = .moving
        let rate = slewRate
        motionTask = Task {
            try? await setRate(1, 0)
            try? await setRate(2, 0)
            try? await move(axis, Int(sign) * rate)
        }
        guardLimit(axis: axis, rate: rate)
    }

    /// While the slew pad moves the mount, stops it before it rises past the
    /// maximum altitude. Moving back down is always allowed.
    private func guardLimit(axis: Int, rate: Int) {
        limitGuard?.cancel()
        guard let limit = altitudeLimit else { return }
        // the motor needs a moment to stop, and positions arrive every ~0.15 s
        let margin = max(0.1, Self.slewSpeed(rate: rate) * 0.5)
        limitGuard = Task { [weak self] in
            var last = self?.currentAltitude
            while !Task.isCancelled {
                guard let self, activity == .moving else { return }
                try? await Task.sleep(for: .milliseconds(150))
                _ = try? await readAxes()
                guard let alt = currentAltitude else { continue }
                if let l = last, alt > l + 1e-4, alt >= limit - margin {
                    motionTask?.cancel()
                    try? await move(axis, 0)
                    activity = .idle
                    resumeTracking = false
                    lastError = "Stopped at the \(Int(limit))° maximum altitude."
                    return
                }
                last = alt
            }
        }
    }

    func stopMove() {
        limitGuard?.cancel()
        guard activity == .moving else { return }
        let resume = resumeTracking
        let previous = motionTask
        motionTask = Task {
            await previous?.value
            try? await move(1, 0)
            try? await move(2, 0)
            guard resume, let model, let target = trackTarget else {
                activity = .idle
                return
            }
            // keep the user's correction while tracking
            if let current = try? await readAxes() {
                let here = model.axes(for: target(Date()))
                trackOffset = (MountModel.wrap180(current.axis1 - here.axis1), MountModel.wrap180(current.axis2 - here.axis2))
            }
            activity = .tracking
            do { try await track() } catch {
                if !Task.isCancelled { activity = .idle }
            }
        }
    }

    // MARK: Finding the module

    /// Looks for SkyPortal modules on the phone's WiFi network by trying
    /// port 2000 on every address of its subnet.
    func findOnNetwork() {
        guard !scanning else { return }
        guard let hosts = Self.subnetHosts(), !hosts.isEmpty else {
            lastError = "The phone isn't connected to a WiFi network."
            return
        }
        scanning = true
        foundHosts = []
        lastError = nil
        Task {
            let found = await withTaskGroup(of: String?.self) { group in
                var results: [String] = []
                var next = 0
                func add(_ g: inout TaskGroup<String?>) {
                    let h = hosts[next]
                    next += 1
                    g.addTask { await Self.probe(h) ? h : nil }
                }
                for _ in 0..<min(32, hosts.count) { add(&group) }
                while let r = await group.next() {
                    if let r { results.append(r) }
                    if next < hosts.count { add(&group) }
                }
                return results
            }
            foundHosts = found.sorted { $0.split(separator: ".").last.flatMap { Int($0) } ?? 0 < $1.split(separator: ".").last.flatMap { Int($0) } ?? 0 }
            scanning = false
            if let first = foundHosts.first {
                networkHost = first
            } else {
                lastError = "No telescope found. Check that the module is in network mode and on the same WiFi as the phone."
            }
        }
    }

    nonisolated private static func probe(_ host: String) async -> Bool {
        let client = AUXClient()
        defer { Task { await client.disconnect() } }
        do {
            try await client.connect(host: host, timeout: .milliseconds(1200))
            _ = try await client.send(AUX.Packet(.getVersion, to: .azimuth), timeout: .milliseconds(1500))
            return true
        } catch {
            return false
        }
    }

    /// All other addresses on the WiFi interface's subnet (at most a /24).
    nonisolated static func subnetHosts() -> [String]? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == "en0",
                  let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = ifa.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            m |= 0xFFFF_FF00  // never scan more than 254 addresses
            let network = ip & m
            let broadcast = network | ~m
            guard broadcast > network + 1 else { return [] }
            return (network + 1..<broadcast).filter { $0 != ip }.map {
                "\($0 >> 24 & 0xFF).\($0 >> 16 & 0xFF).\($0 >> 8 & 0xFF).\($0 & 0xFF)"
            }
        }
        return nil
    }
}
