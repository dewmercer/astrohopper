import Foundation

/// Corrects the phone's measured pointing to where the telescope really points.
///
/// - `world` rotates the measured sky (compass or gyroscope azimuth error and,
///   with three stars, a small tilt of the reference frame).
/// - `tubeAxis` is the telescope's direction in the phone's own coordinates.
///   It differs from the phone's top edge `(0, 1, 0)` when the phone isn't
///   mounted exactly parallel to the tube, which a single star can only hide
///   near that star.
struct PointingModel {
    var world: Mat3 = .identity
    var tubeAxis = Vec3(0, 1, 0)

    func direction(deviceToENU d: Mat3) -> Vec3 { world * (d * tubeAxis) }
}

/// One alignment star: the phone's attitude while the telescope pointed at
/// it, and the star's true direction at that moment, both in east-north-up
/// coordinates. Both frames are fixed to the ground, so samples taken
/// minutes apart can be combined.
struct AlignmentSample {
    var index: Int
    var deviceToENU: Mat3
    var star: Vec3
}

enum Alignment {
    /// Port of `selectAlign()`: rotate around the vertical axis, then around
    /// the camera's left axis, so the star lands exactly in the center.
    static func oneStar(camera cam: CameraRays, star tr: Vec3) -> Mat3 {
        let fw = cam.fwd
        let trH = normalize(Vec3(tr.x, tr.y, 0))
        let fwH = normalize(Vec3(fw.x, fw.y, 0))
        let dAZ = atan2(cross(trH, fwH).z, dot(trH, fwH))
        let dAlt = asin(max(-1, min(1, tr.z))) - asin(max(-1, min(1, fw.z)))
        let dazMat = Mat3(r0: Vec3(cos(dAZ), sin(dAZ), 0), r1: Vec3(-sin(dAZ), cos(dAZ), 0), r2: Vec3(0, 0, 1))
        let daltMat = Mat3.rotation(axis: cam.left, angle: -dAlt)
        return dazMat * daltMat
    }

    // MARK: Multi-star fit

    /// Parameters: azimuth offset, the tube axis offsets across the phone
    /// (x) and through the screen (z), and with three or more stars a tilt
    /// of the reference frame around east and north. All in radians.
    private static func model(_ p: [Double]) -> PointingModel {
        let az = rot(Vec3(0, 0, 1), p[0])
        let tilt = p.count > 3 ? rot(Vec3(1, 0, 0), p[3]) * rot(Vec3(0, 1, 0), p[4]) : .identity
        return PointingModel(world: az * tilt, tubeAxis: normalize(Vec3(p[1], 1, p[2])))
    }

    private static func rot(_ axis: Vec3, _ angle: Double) -> Mat3 {
        let c = cos(angle), s = sin(angle)
        switch (axis.x, axis.y) {
        case (1, _): return Mat3(r0: Vec3(1, 0, 0), r1: Vec3(0, c, -s), r2: Vec3(0, s, c))
        case (_, 1): return Mat3(r0: Vec3(c, 0, s), r1: Vec3(0, 1, 0), r2: Vec3(-s, 0, c))
        default: return Mat3(r0: Vec3(c, -s, 0), r1: Vec3(s, c, 0), r2: Vec3(0, 0, 1))
        }
    }

    /// Weak pull of the offsets toward zero, so a poorly spread pair of stars
    /// (for example two at the same altitude) can't produce a wild model.
    private static let prior = 0.02

    private static func residuals(_ p: [Double], _ samples: [AlignmentSample]) -> [Double] {
        let m = model(p)
        var r: [Double] = []
        for s in samples {
            let d = m.direction(deviceToENU: s.deviceToENU) - s.star
            r += [d.x, d.y, d.z]
        }
        for v in p.dropFirst() { r.append(prior * v) }
        return r
    }

    /// Least-squares pointing model for two or more stars (Gauss-Newton).
    static func fit(_ samples: [AlignmentSample]) -> PointingModel {
        guard let first = samples.first else { return PointingModel() }
        let f = first.deviceToENU * Vec3(0, 1, 0)
        let fH = Vec3(f.x, f.y, 0), tH = Vec3(first.star.x, first.star.y, 0)
        var p = [Double](repeating: 0, count: samples.count >= 3 ? 5 : 3)
        p[0] = atan2(cross(fH, tH).z, dot(fH, tH))
        let n = p.count
        for _ in 0..<30 {
            let r = residuals(p, samples)
            var jac = [[Double]](repeating: [], count: n)
            for j in 0..<n {
                var q = p
                q[j] += 1e-7
                jac[j] = zip(residuals(q, samples), r).map { ($0 - $1) / 1e-7 }
            }
            // normal equations (JᵀJ) δ = -Jᵀr
            var a = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
            for i in 0..<n {
                for j in 0..<n { a[i][j] = zip(jac[i], jac[j]).reduce(0) { $0 + $1.0 * $1.1 } }
                a[i][i] += 1e-12
                a[i][n] = -zip(jac[i], r).reduce(0) { $0 + $1.0 * $1.1 }
            }
            guard let delta = solve(a) else { break }
            for i in 0..<n { p[i] += delta[i] }
            if delta.map(abs).max() ?? 0 < 1e-10 { break }
        }
        return model(p)
    }

    /// Gaussian elimination with partial pivoting on an augmented matrix.
    private static func solve(_ m: [[Double]]) -> [Double]? {
        var a = m
        let n = a.count
        for c in 0..<n {
            guard let pivot = (c..<n).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[pivot][c]) > 1e-15 else {
                return nil
            }
            a.swapAt(c, pivot)
            for r in 0..<n where r != c {
                let k = a[r][c] / a[c][c]
                for j in c...n { a[r][j] -= k * a[c][j] }
            }
        }
        return (0..<n).map { a[$0][n] / a[$0][$0] }
    }

    /// Angle in degrees between where the model says each alignment star
    /// was and where it really was.
    static func errors(_ model: PointingModel, _ samples: [AlignmentSample]) -> [Double] {
        samples.map { s in
            acos(max(-1, min(1, dot(normalize(model.direction(deviceToENU: s.deviceToENU)), s.star)))) * rad2deg
        }
    }

    static func rmsError(_ model: PointingModel, _ samples: [AlignmentSample]) -> Double {
        let e = errors(model, samples)
        return e.isEmpty ? 0 : (e.reduce(0) { $0 + $1 * $1 } / Double(e.count)).squareRoot()
    }

    // MARK: Choosing the next star

    /// Picks a bright object well away from the stars already used: about
    /// 90° from them, and for a third star also far from the great circle
    /// through the first two. It must be comfortably above the horizon and
    /// not near the zenith, where azimuth is ill-defined.
    static func suggest(candidates: [(index: Int, enu: Vec3, mag: Double)], used: [Vec3]) -> Int? {
        var best: (index: Int, score: Double)?
        let plane = used.count >= 2 ? normalize(cross(used[0], used[1])) : nil
        for c in candidates {
            let alt = asin(max(-1, min(1, c.enu.z))) * rad2deg
            guard alt >= 15, alt <= 75 else { continue }
            let minSep = used.map { acos(max(-1, min(1, dot($0, c.enu)))) * rad2deg }.min() ?? 90
            guard minSep >= 30 else { continue }
            var score = min(minSep, 90) / 90 - 0.15 * c.mag
            if let plane { score += abs(dot(plane, c.enu)) }
            if best == nil || score > best!.score { best = (c.index, score) }
        }
        return best?.index
    }
}
