import Foundation

enum MountType: String, CaseIterable, Identifiable {
    case altAz, equatorial
    var id: String { rawValue }
    var label: String {
        switch self {
        case .altAz: "Alt-Azimuth"
        case .equatorial: "Equatorial"
        }
    }
}

/// One alignment star for the mount: the raw axis angles (encoder steps as
/// degrees) when the telescope was centered on it, and the star's true
/// direction then, in east-north-up coordinates.
struct MountSample {
    var index: Int
    var axis1: Double
    var axis2: Double
    var star: Vec3
}

/// Maps the mount's encoder readings to sky directions and back.
///
/// The axes are treated like an alt-az mount in the mount's own frame: axis
/// 1 turns around the frame's vertical, axis 2 tilts the tube up from the
/// frame's horizontal. For an alt-az mount the frame is the local sky; for
/// an equatorial mount its vertical is the celestial pole, so axis 1 is the
/// hour-angle axis and axis 2 declination. Offsets of the encoders, a mount
/// that isn't level or polar aligned, and an optical tube that isn't square
/// to its axis are all absorbed by the same pointing fit used for the
/// phone (`Alignment.fit`).
struct MountModel {
    var type: MountType
    var latitude: Double
    /// Directions of the encoders: +1 when the angle grows with the encoder.
    var signs: (axis1: Double, axis2: Double) = (1, 1)
    var pointing = PointingModel()

    /// Rotation from east-north-up into the mount frame.
    static func frame(_ type: MountType, latitude: Double) -> Mat3 {
        guard type == .equatorial else { return .identity }
        let phi = latitude * deg2rad
        // the visible celestial pole, at altitude |latitude| due north or south
        let pole = latitude >= 0 ? Vec3(0, cos(phi), sin(phi)) : Vec3(0, -cos(phi), -sin(phi))
        let east = Vec3(1, 0, 0)
        return Mat3(r0: east, r1: cross(pole, east), r2: pole)
    }

    var frame: Mat3 { Self.frame(type, latitude: latitude) }

    /// Mount attitude for raw axis angles, in the same form as a phone
    /// attitude: it maps the tube's nominal direction (0, 1, 0) to the sky.
    func attitude(_ a1: Double, _ a2: Double) -> Mat3 {
        Self.attitude(a1, a2, signs: signs)
    }

    static func attitude(_ a1: Double, _ a2: Double, signs: (axis1: Double, axis2: Double)) -> Mat3 {
        Mat3.rotZ(degrees: -signs.axis1 * a1) * Mat3.rotation(axis: Vec3(1, 0, 0), angle: signs.axis2 * a2 * deg2rad)
    }

    /// Where the telescope points (east-north-up) for raw axis angles.
    func direction(_ a1: Double, _ a2: Double) -> Vec3 {
        normalize(frame.transposed * pointing.direction(deviceToENU: attitude(a1, a2)))
    }

    /// Raw axis angles that point the telescope at an east-north-up direction.
    func axes(for enu: Vec3) -> (axis1: Double, axis2: Double) {
        let t = normalize(frame * enu)
        // ignoring the corrections, the direction is (sin a cos h, cos a cos h, sin h)
        let u = pointing.world.transposed * t
        var p = [signs.axis1 * atan2(u.x, u.y) * rad2deg, signs.axis2 * asin(max(-1, min(1, u.z))) * rad2deg]
        func residual(_ q: [Double]) -> Vec3 { pointing.direction(deviceToENU: attitude(q[0], q[1])) - t }
        for _ in 0..<12 {
            let r = residual(p)
            let h = 1e-6
            let j0 = (residual([p[0] + h, p[1]]) - r) / h
            let j1 = (residual([p[0], p[1] + h]) - r) / h
            let a00 = dot(j0, j0), a01 = dot(j0, j1), a11 = dot(j1, j1)
            let b0 = -dot(j0, r), b1 = -dot(j1, r)
            let det = a00 * a11 - a01 * a01
            guard abs(det) > 1e-18 else { break }
            let d0 = (b0 * a11 - b1 * a01) / det, d1 = (a00 * b1 - a01 * b0) / det
            p[0] += d0
            p[1] += d1
            if max(abs(d0), abs(d1)) < 1e-9 { break }
        }
        return (Self.wrap180(p[0]), Self.wrap180(p[1]))
    }

    // MARK: Alignment

    private static func alignmentSamples(_ samples: [MountSample], frame: Mat3,
                                         signs: (axis1: Double, axis2: Double)) -> [AlignmentSample] {
        samples.map {
            AlignmentSample(index: $0.index, deviceToENU: attitude($0.axis1, $0.axis2, signs: signs), star: normalize(frame * $0.star))
        }
    }

    /// Fits the mount to its alignment stars. One star only centers that
    /// star. With two or more, the encoder directions are also found, by
    /// keeping whichever combination fits the stars best.
    static func fit(_ type: MountType, latitude: Double, samples: [MountSample]) -> MountModel? {
        guard let first = samples.first else { return nil }
        let frame = Self.frame(type, latitude: latitude)
        if samples.count == 1 {
            var m = MountModel(type: type, latitude: latitude)
            let s = alignmentSamples([first], frame: frame, signs: m.signs)[0]
            let cam = CameraRays(deviceToENU: s.deviceToENU, alignment: nil)
            m.pointing = PointingModel(world: Alignment.oneStar(camera: cam, star: s.star))
            return m
        }
        var best: (model: MountModel, error: Double)?
        for signs in [(1.0, 1.0), (-1, 1), (1, -1), (-1, -1)] {
            let aligned = alignmentSamples(samples, frame: frame, signs: (signs.0, signs.1))
            let pointing = Alignment.fit(aligned)
            let error = Alignment.rmsError(pointing, aligned)
            // the expected directions win unless another fits clearly better
            if best == nil || error < best!.error - 0.05 {
                best = (MountModel(type: type, latitude: latitude, signs: (signs.0, signs.1), pointing: pointing), error)
            }
        }
        return best?.model
    }

    func rmsError(_ samples: [MountSample]) -> Double {
        let e = samples.map { s in acos(max(-1, min(1, dot(direction(s.axis1, s.axis2), normalize(s.star))))) * rad2deg }
        return e.isEmpty ? 0 : (e.reduce(0) { $0 + $1 * $1 } / Double(e.count)).squareRoot()
    }

    // MARK: Encoder steps

    static func degrees(steps: UInt32) -> Double {
        wrap180(Double(steps & 0xFF_FFFF) * 360 / AUX.stepsPerRevolution)
    }

    static func steps(degrees: Double) -> UInt32 {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return UInt32((d / 360 * AUX.stepsPerRevolution).rounded()) & 0xFF_FFFF
    }

    static func wrap180(_ d: Double) -> Double {
        var x = d.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x <= -180 { x += 360 }
        return x
    }
}
