import CoreMotion
import Foundation
import Observation

/// Supplies the three inputs the web app reads from device-orientation events:
///
/// - `tilt`: the gravity-defined part of the attitude (W3C beta/gamma)
/// - `compassAlpha`: absolute W3C alpha from the magnetometer (nil without a compass)
/// - `gyroAlpha`: relative alpha integrated from the gyroscope only, so a
///   magnetic disturbance after alignment cannot move the map
///
/// With these, the device-to-ENU attitude for any chosen alpha is
/// `Mat3.rotZ(degrees: alpha) * tilt`, exactly like `getRotationMatrix()`.
@MainActor
@Observable
final class MotionTracker {
    private(set) var tilt: Mat3 = .identity
    private(set) var compassAlpha: Double?
    private(set) var gyroAlpha: Double = 0
    private(set) var isAvailable = false
    private(set) var hasCompass = false
    private(set) var hasSample = false
    /// Rotation speed in degrees per second, smoothed over about a quarter
    /// second so that a shaking tube reads as moving. Zero in demo mode.
    @ObservationIgnored private(set) var angularSpeed: Double = 0

    /// Demo mode (simulator or no gyro): drag gestures move a virtual telescope.
    var isDemo: Bool { !isAvailable }
    private var demoAlpha: Double = 0
    private var demoBeta: Double = 20

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var frame: CMAttitudeReferenceFrame?
    @ObservationIgnored private var lastTimestamp: TimeInterval?
    /// Whether the quaternion's matrix maps device to reference coordinates;
    /// confirmed against the gravity vector on the first decisive sample.
    @ObservationIgnored private var quaternionMapsDeviceToReference = true
    @ObservationIgnored private var conventionConfirmed = false

    init() {
        isAvailable = manager.isDeviceMotionAvailable
        if !isAvailable { applyDemo() }
    }

    /// Starts updates; `trueNorth` needs location authorization.
    func start(trueNorth: Bool) {
        guard isAvailable else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let wanted: CMAttitudeReferenceFrame
        if trueNorth && frames.contains(.xTrueNorthZVertical) {
            wanted = .xTrueNorthZVertical
        } else if frames.contains(.xMagneticNorthZVertical) {
            wanted = .xMagneticNorthZVertical
        } else {
            wanted = .xArbitraryCorrectedZVertical
        }
        if frame == wanted && manager.isDeviceMotionActive { return }
        manager.stopDeviceMotionUpdates()
        frame = wanted
        hasCompass = wanted != .xArbitraryCorrectedZVertical
        if !hasCompass { compassAlpha = nil }
        lastTimestamp = nil  // gyroAlpha continues from its current value
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.showsDeviceMovementDisplay = true
        manager.startDeviceMotionUpdates(using: wanted, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.process(motion) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func process(_ motion: CMDeviceMotion) {
        let q = motion.attitude.quaternion
        let rq = Self.matrix(x: q.x, y: q.y, z: q.z, w: q.w)
        if !conventionConfirmed {
            let g = Vec3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
            let down = Vec3(0, 0, -1)
            let errDeviceToRef = length(rq.transposed * down - g)
            let errRefToDevice = length(rq * down - g)
            if abs(errDeviceToRef - errRefToDevice) > 0.3 {
                quaternionMapsDeviceToReference = errDeviceToRef < errRefToDevice
                conventionConfirmed = true
            }
        }
        let deviceToRef = quaternionMapsDeviceToReference ? rq : rq.transposed
        // Reference frame is X north (or arbitrary), Y west, Z up; convert to East, North, Up.
        let refToENU = Mat3(r0: Vec3(0, -1, 0), r1: Vec3(1, 0, 0), r2: Vec3(0, 0, 1))
        let attitude = refToENU * deviceToRef

        let w = motion.rotationRate
        let dt = lastTimestamp.map { min(max(motion.timestamp - $0, 0), 0.1) } ?? 0
        lastTimestamp = motion.timestamp
        update(attitude: attitude, rotationRate: Vec3(w.x, w.y, w.z), dt: dt)
    }

    private func update(attitude: Mat3, rotationRate w: Vec3, dt: Double) {
        let alpha = Attitude.alpha(of: attitude) ?? compassAlpha ?? 0
        let newTilt = Mat3.rotZ(degrees: -alpha) * attitude
        if hasCompass { compassAlpha = alpha }

        let speed = length(w) * rad2deg
        if !hasSample {
            angularSpeed = speed
        } else if dt > 0 {
            angularSpeed += (1 - exp(-dt / 0.25)) * (speed - angularSpeed)
        }

        if !hasSample {
            gyroAlpha = alpha
        } else if dt > 0 {
            // Propagate the previous gyro attitude by the body rotation rate and
            // keep only its yaw; tilt always comes from gravity.
            let previous = Mat3.rotZ(degrees: gyroAlpha) * tilt
            let angle = length(w) * dt
            let propagated = angle > 0 ? previous * Mat3.rotation(axis: w / length(w), angle: angle) : previous
            if let a = Attitude.alpha(of: propagated) { gyroAlpha = a }
        }
        tilt = newTilt
        hasSample = true
    }

    // MARK: Demo mode

    /// Drag in demo mode: dx/dy in degrees of azimuth/altitude.
    func demoMove(dAlpha: Double, dBeta: Double) {
        demoAlpha += dAlpha
        demoBeta = min(89, max(-30, demoBeta + dBeta))
        applyDemo()
    }

    private func applyDemo() {
        tilt = Mat3.tilt(beta: demoBeta, gamma: 0)
        gyroAlpha = demoAlpha
        hasSample = true
    }

    /// Rotation matrix of a unit quaternion (rotates vectors by q).
    static func matrix(x: Double, y: Double, z: Double, w: Double) -> Mat3 {
        Mat3(r0: Vec3(1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
             r1: Vec3(2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
             r2: Vec3(2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))
    }
}

/// Decides when the telescope has stopped moving after the user touched the
/// phone: the rotation speed must stay below `threshold` for `duration`
/// seconds in a row. Any movement starts the wait again.
struct SteadinessTimer {
    /// Degrees per second. Well above the gyroscope's noise, below the
    /// wobble of a tube that was just touched.
    static let threshold = 0.5
    static let duration = 1.5

    private(set) var steadyTime = 0.0
    private(set) var isMoving = false

    var progress: Double { min(steadyTime / Self.duration, 1) }
    var isComplete: Bool { steadyTime >= Self.duration }

    mutating func update(angularSpeed: Double, dt: Double) {
        if angularSpeed > Self.threshold {
            steadyTime = 0
            isMoving = true
        } else {
            steadyTime += dt
            isMoving = false
        }
    }
}
