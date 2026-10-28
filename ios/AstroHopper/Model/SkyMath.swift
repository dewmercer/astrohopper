import Foundation

typealias Vec3 = SIMD3<Double>

let deg2rad = Double.pi / 180
let rad2deg = 180 / Double.pi

func dot(_ a: Vec3, _ b: Vec3) -> Double { (a * b).sum() }

func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
    Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

func length(_ v: Vec3) -> Double { dot(v, v).squareRoot() }

func normalize(_ v: Vec3) -> Vec3 { v / length(v) }

/// Row-major 3x3 matrix, matching the `[m11, m12, m13, m21, ...]` arrays of the web app.
struct Mat3: Equatable {
    var r0, r1, r2: Vec3

    static let identity = Mat3(r0: Vec3(1, 0, 0), r1: Vec3(0, 1, 0), r2: Vec3(0, 0, 1))

    init(r0: Vec3, r1: Vec3, r2: Vec3) {
        self.r0 = r0; self.r1 = r1; self.r2 = r2
    }

    init(_ m: [[Double]]) {
        r0 = Vec3(m[0][0], m[0][1], m[0][2])
        r1 = Vec3(m[1][0], m[1][1], m[1][2])
        r2 = Vec3(m[2][0], m[2][1], m[2][2])
    }

    subscript(row: Int, col: Int) -> Double {
        switch row {
        case 0: r0[col]
        case 1: r1[col]
        default: r2[col]
        }
    }

    var transposed: Mat3 {
        Mat3(r0: Vec3(r0.x, r1.x, r2.x), r1: Vec3(r0.y, r1.y, r2.y), r2: Vec3(r0.z, r1.z, r2.z))
    }

    func column(_ i: Int) -> Vec3 { Vec3(r0[i], r1[i], r2[i]) }

    static func * (m: Mat3, v: Vec3) -> Vec3 {
        Vec3(dot(m.r0, v), dot(m.r1, v), dot(m.r2, v))
    }

    static func * (a: Mat3, b: Mat3) -> Mat3 {
        func row(_ r: Vec3) -> Vec3 { r.x * b.r0 + r.y * b.r1 + r.z * b.r2 }
        return Mat3(r0: row(a.r0), r1: row(a.r1), r2: row(a.r2))
    }

    static func * (m: Mat3, s: Double) -> Mat3 { Mat3(r0: m.r0 * s, r1: m.r1 * s, r2: m.r2 * s) }

    static func + (a: Mat3, b: Mat3) -> Mat3 { Mat3(r0: a.r0 + b.r0, r1: a.r1 + b.r1, r2: a.r2 + b.r2) }

    /// Skew-symmetric cross-product matrix `[u]x`.
    static func skew(_ u: Vec3) -> Mat3 {
        Mat3(r0: Vec3(0, -u.z, u.y), r1: Vec3(u.z, 0, -u.x), r2: Vec3(-u.y, u.x, 0))
    }

    /// Rotation by `angle` radians around the unit axis `u` (Rodrigues).
    static func rotation(axis u: Vec3, angle: Double) -> Mat3 {
        let w = skew(u)
        let s = sin(angle / 2)
        return identity + w * sin(angle) + (w * w) * (2 * s * s)
    }

    /// W3C device-orientation rotation about the vertical axis (alpha), in degrees.
    static func rotZ(degrees: Double) -> Mat3 {
        let c = cos(degrees * deg2rad), s = sin(degrees * deg2rad)
        return Mat3(r0: Vec3(c, -s, 0), r1: Vec3(s, c, 0), r2: Vec3(0, 0, 1))
    }

    /// W3C device-orientation tilt (beta around X, then gamma around Y), in degrees.
    static func tilt(beta: Double, gamma: Double) -> Mat3 {
        let cX = cos(beta * deg2rad), sX = sin(beta * deg2rad)
        let cY = cos(gamma * deg2rad), sY = sin(gamma * deg2rad)
        return Mat3(r0: Vec3(cY, 0, sY),
                    r1: Vec3(sX * sY, cX, -sX * cY),
                    r2: Vec3(-cX * sY, sX, cX * cY))
    }

    /// Same as the web app's `getRotationMatrix(alpha, beta, gamma)` (ZXY Euler angles).
    static func deviceOrientation(alpha: Double, beta: Double, gamma: Double) -> Mat3 {
        rotZ(degrees: alpha) * tilt(beta: beta, gamma: gamma)
    }
}

/// Device-to-world (East, North, Up) attitude split the way the web app sees it:
/// `deviceOrientation(alpha, ...) == rotZ(alpha) * tilt`.
enum Attitude {
    /// W3C alpha (degrees) of a device-to-ENU matrix, or nil when the phone's top
    /// points straight up or down and the azimuth is undefined.
    static func alpha(of m: Mat3) -> Double? {
        let e = m[0, 1], n = m[1, 1]
        guard e * e + n * n > 1e-10 else { return nil }
        return atan2(-e, n) * rad2deg
    }

    /// W3C (beta, gamma) of the tilt part, used for the debug read-out only.
    static func betaGamma(ofTilt t: Mat3) -> (beta: Double, gamma: Double) {
        let beta = asin(max(-1, min(1, t[2, 1]))) * rad2deg
        let gamma = atan2(-t[2, 0], t[2, 2]) * rad2deg
        return (beta, gamma)
    }
}

/// Telescope view direction (`fwd`) plus screen axes, all in ENU coordinates.
struct CameraRays {
    var top: Vec3
    var left: Vec3
    var fwd: Vec3

    /// Port of `getCameraRays()`: the screen looks along the phone's top edge, and
    /// `left` is kept horizontal so the map always has the zenith up.
    init(deviceToENU m: Mat3, alignMatrix: Mat3?) {
        var fwd = m * Vec3(0, 1, 0)
        let hlen = (fwd.x * fwd.x + fwd.y * fwd.y).squareRoot()
        let fwdHor = hlen > 1e-12 ? Vec3(fwd.x / hlen, fwd.y / hlen, 0) : Vec3(0, 1, 0)
        var left = Vec3(-fwdHor.y, fwdHor.x, 0)
        var top = cross(fwd, left)
        if let a = alignMatrix {
            top = a * top
            left = a * left
            fwd = a * fwd
        }
        self.top = top
        self.left = left
        self.fwd = fwd
    }

    /// Altitude and azimuth (degrees) of the view direction.
    var altAz: (alt: Double, az: Double) {
        let alt = asin(max(-1, min(1, fwd.z))) * rad2deg
        var az = atan2(fwd.x, fwd.y) * rad2deg
        if az < 0 { az += 360 }
        return (alt, az)
    }
}

enum Sky {
    /// Unit vector of RA/DE (degrees) in the equatorial frame.
    static func equatorial(ra: Double, de: Double) -> Vec3 {
        let r = ra * deg2rad, d = de * deg2rad
        return Vec3(cos(d) * cos(r), cos(d) * sin(r), sin(d))
    }

    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Local sidereal angle (radians) exactly as computed by `rayFromPos()`.
    static func localSiderealAngle(date: Date, lonDegrees: Double) -> Double {
        let tu = julianDay(date) - 2451545.0
        let frac = 0.7790572732640 + 1.00273781191135448 * tu
        return 2 * Double.pi * (frac - frac.rounded(.down)) + lonDegrees * deg2rad
    }

    /// Matrix taking an equatorial unit vector to (East, North, Up); equivalent to
    /// `rayFromPos()` but without per-object trigonometry.
    static func equatorialToENU(date: Date, latDegrees: Double, lonDegrees: Double) -> Mat3 {
        let q = localSiderealAngle(date: date, lonDegrees: lonDegrees)
        let cL = cos(q), sL = sin(q)
        let f = latDegrees * deg2rad
        let cf = cos(f), sf = sin(f)
        return Mat3(r0: Vec3(-sL, cL, 0),
                    r1: Vec3(-sf * cL, -sf * sL, cf),
                    r2: Vec3(cf * cL, cf * sL, sf))
    }
}

/// Port of `xyzTo2d()` with the default camera projection. Returns screen
/// coordinates normalized to 0...1, or nil when behind or outside the view.
struct Projection {
    var limX: Double
    var limY: Double

    init(fovDegrees: Double, width: Double, height: Double) {
        let ratio = width / height
        let lr, td: Double
        if ratio < 1 {
            td = fovDegrees
            lr = td * ratio
        } else {
            lr = fovDegrees
            td = lr / ratio
        }
        limX = sin(lr * deg2rad / 2)
        limY = sin(td * deg2rad / 2)
    }

    var fovLR: Double { asin(limX) * 2 * rad2deg }

    func project(_ xyz: Vec3, inFOV: Bool = true) -> (x: Double, y: Double)? {
        if xyz.z <= 0 { return nil }
        if inFOV {
            if xyz.x < -limX || xyz.x > limX { return nil }
            if xyz.y < -limY || xyz.y > limY { return nil }
        }
        return ((xyz.x + limX) / (limX * 2), 1 - (xyz.y + limY) / (limY * 2))
    }
}
