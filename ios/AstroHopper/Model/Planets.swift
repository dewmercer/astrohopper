import Foundation

/// Truncated VSOP87A series (vsop87a.json, extracted from vsop87a_combined.js):
/// coordinate(t) = sum over n of t^n * sum(A * cos(B + C * t)), t in Julian millennia.
struct VSOP87 {
    struct Series {
        var powers: [(n: Int, terms: [(a: Double, b: Double, c: Double)])]

        func value(_ t: Double) -> Double {
            var total = 0.0
            for (n, terms) in powers {
                var s = 0.0
                for term in terms { s += term.a * cos(term.b + term.c * t) }
                total += s * pow(t, Double(n))
            }
            return total
        }

        /// d/dt, used for the Earth velocity (aberration).
        func derivative(_ t: Double) -> Double {
            var total = 0.0
            for (n, terms) in powers {
                var s = 0.0, ds = 0.0
                for term in terms {
                    let arg = term.b + term.c * t
                    s += term.a * cos(arg)
                    ds -= term.a * term.c * sin(arg)
                }
                let tn = pow(t, Double(n))
                total += ds * tn
                if n > 0 { total += s * Double(n) * pow(t, Double(n - 1)) }
            }
            return total
        }
    }

    let bodies: [String: [Series]]  // x, y, z

    static func loadBundled() throws -> VSOP87 {
        guard let url = Bundle.main.url(forResource: "vsop87a", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try VSOP87(json: Data(contentsOf: url))
    }

    init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: [String: [[Any]]]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var bodies: [String: [Series]] = [:]
        for (body, coords) in root {
            bodies[body] = try ["x", "y", "z"].map { c in
                guard let list = coords[c] else { throw CocoaError(.fileReadCorruptFile) }
                return Series(powers: list.map { entry in
                    let n = (entry[0] as? NSNumber)?.intValue ?? 0
                    let terms = (entry[1] as? [[NSNumber]] ?? []).map { ($0[0].doubleValue, $0[1].doubleValue, $0[2].doubleValue) }
                    return (n, terms)
                })
            }
        }
        self.bodies = bodies
    }

    func position(_ body: String, _ t: Double) -> Vec3 {
        guard let s = bodies[body] else { return .zero }
        return Vec3(s[0].value(t), s[1].value(t), s[2].value(t))
    }

    func velocity(_ body: String, _ t: Double) -> Vec3 {
        guard let s = bodies[body] else { return .zero }
        return Vec3(s[0].derivative(t), s[1].derivative(t), s[2].derivative(t))
    }
}

/// Port of the parts of CPReduce (vsop87-multilang, public domain) the web app
/// uses: topocentric astrometric J2000 RA/DE of a planet or the Moon.
struct Planets {
    let vsop: VSOP87

    /// Returns J2000 RA and DE in degrees. `name` is one of the planet names in
    /// the catalog ("Moon", "Mercury", ...); latitude/longitude are in degrees.
    func raDec(of name: String, julianDayUTC jdUTC: Double, lat: Double, lon: Double) -> (ra: Double, de: Double) {
        let jdTT = jdUTC + (Planets.leapSeconds(jdUTC) + 32.184) / 86400
        let jdTDB = jdTT
        let jdUT1 = jdUTC

        let earth = position(of: "Earth", jdTDB)
        let target = lightAdjusted(origin: earth, body: name, jd: jdTDB)

        let precession = Planets.precessionMatrix(jdTDB)
        let nutation = Planets.nutationMatrix(jdTDB)

        let geocentric = target - earth

        var observer = Planets.observerGeocentric(lat: lat * deg2rad, lon: lon * deg2rad, jdUT1: jdUT1)
        observer = nutation.transposed * observer
        observer = precession.transposed * observer

        let topocentric = geocentric - observer
        let (ra, de) = Planets.xyzToRaDec(topocentric)
        return (ra * rad2deg, de * rad2deg)
    }

    private func position(of body: String, _ jdTDB: Double) -> Vec3 {
        let t = (jdTDB - 2451545.0) / 365250.0
        let b: Vec3
        switch body {
        case "Moon":
            let e = vsop.position("earth", t)
            let emb = vsop.position("emb", t)
            b = (emb - e) * (1 + 1 / 0.01230073677) + e
        case "Sun":
            b = .zero
        default:
            b = vsop.position(body.lowercased(), t)
        }
        return Planets.rotVSOPToJ2000(b)
    }

    /// Earth velocity in AU/day (J2000 frame); only needed for aberration, which
    /// does not affect the astrometric J2000 position returned by `raDec`.
    func earthVelocity(_ jdTDB: Double) -> Vec3 {
        let t = (jdTDB - 2451545.0) / 365250.0
        return Planets.rotVSOPToJ2000(vsop.velocity("earth", t) / 365250.0)
    }

    private func lightAdjusted(origin: Vec3, body: String, jd: Double) -> Vec3 {
        var jdLight = jd
        var b = Vec3.zero
        let c = 299792458.0
        let au = 149597870691.0
        for _ in 0..<3 {
            b = position(of: body, jdLight)
            let r = length(origin - b)
            jdLight = jd - r / (c / au * 60 * 60 * 24)
        }
        return b
    }

    static func rotVSOPToJ2000(_ x: Vec3) -> Vec3 {
        Vec3(x.x + x.y * 0.000000440360 + x.z * -0.000000190919,
             x.x * -0.000000479966 + x.y * 0.917482137087 + x.z * -0.397776982902,
             x.y * 0.397776982902 + x.z * 0.917482137087)
    }

    static func rotX(_ r: Double) -> Mat3 {
        Mat3(r0: Vec3(1, 0, 0), r1: Vec3(0, cos(r), sin(r)), r2: Vec3(0, -sin(r), cos(r)))
    }

    static func rotZ(_ r: Double) -> Mat3 {
        Mat3(r0: Vec3(cos(r), sin(r), 0), r1: Vec3(-sin(r), cos(r), 0), r2: Vec3(0, 0, 1))
    }

    private static let arcsec = 1 / 60.0 / 60.0 * Double.pi / 180

    private static func meanObliquity(_ t: Double) -> Double {
        (84381.406 - 46.836769 * t - 0.0001831 * t * t + 0.00200340 * t * t * t
            - 0.000000576 * t * t * t * t - 0.0000000434 * t * t * t * t * t) * arcsec
    }

    /// Fukushima-Williams IAU 2006.
    static func precessionMatrix(_ jdTDB: Double) -> Mat3 {
        let t = (jdTDB - 2451545.5) / 36525.0
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
        let gamma = (-0.052928 + 10.556378 * t + 0.4932044 * t2 - 0.00031238 * t3 - 0.000002788 * t4 + 0.0000000260 * t5) * arcsec
        let phi = (84381.412819 - 46.811016 * t + 0.0511268 * t2 + 0.00053289 * t3 - 0.000000440 * t4 - 0.0000000176 * t5) * arcsec
        let psi = (-0.041775 + 5038.481484 * t + 1.5584175 * t2 - 0.00018522 * t3 - 0.000026452 * t4 - 0.0000000148 * t5) * arcsec
        let eps = meanObliquity(t)
        return rotX(-eps) * (rotZ(-psi) * (rotX(phi) * rotZ(gamma)))
    }

    static func nutationMatrix(_ jdTDB: Double) -> Mat3 {
        let t = (jdTDB - 2451545.5) / 36525.0
        let (dpsi, deps) = nutation2000BTruncated(t)
        let eps = meanObliquity(t)
        return rotX(-(eps + deps)) * (rotZ(-dpsi) * rotX(eps))
    }

    /// IAU 2000B nutation truncated to 6 terms.
    static func nutation2000BTruncated(_ T: Double) -> (dpsi: Double, deps: Double) {
        var dp = 0.0, de = 0.0
        let T2 = T * T, T3 = T * T2, T4 = T * T3
        let Lp = arcsec * (1287104.79305 + 129596581.0481 * T - 0.5532 * T2 + 0.000136 * T3 - 0.00001149 * T4)
        let F = arcsec * (335779.526232 + 1739527262.8478 * T - 12.7512 * T2 - 0.001037 * T3 + 0.00000417 * T4)
        let D = arcsec * (1072260.70369 + 1602961601.2090 * T - 6.3706 * T2 + 0.006593 * T3 - 0.00003169 * T4)
        let Om = arcsec * (450160.398036 - 6962890.5431 * T + 7.4722 * T2 + 0.007702 * T3 - 0.00005939 * T4)

        var arg = Lp + 2 * (F - D + Om)
        dp += (-516821 + 1226 * T) * sin(arg) + -524 * cos(arg)
        de += (224386 + -677 * T) * cos(arg) + -174 * sin(arg)

        dp += (1475877 + -3633 * T) * sin(Lp) + 11817 * cos(Lp)
        de += (73871 + -184 * T) * cos(Lp) + -1924 * sin(Lp)

        arg = 2 * Om
        dp += (2074554 + 207 * T) * sin(arg) + -698 * cos(arg)
        de += (-897492 + 470 * T) * cos(arg) + -291 * sin(arg)

        arg = 2 * (F + Om)
        dp += (-2276413 + -234 * T) * sin(arg) + 2796 * cos(arg)
        de += (978459 + -485 * T) * cos(arg) + 1374 * sin(arg)

        arg = 2 * (F - D + Om)
        dp += (-13170906 + -1675 * T) * sin(arg) + -13696 * cos(arg)
        de += (5730336 + -3015 * T) * cos(arg) + -4587 * sin(arg)

        dp += (-172064161 + -174666 * T) * sin(Om) + 33386 * cos(Om)
        de += (92052331 + 9086 * T) * cos(Om) + 15377 * sin(Om)

        return (dp * arcsec / 10000000, de * arcsec / 10000000)
    }

    static func observerGeocentric(lat: Double, lon: Double, jdUT1: Double) -> Vec3 {
        // Explanatory Supplement to the Astronomical Almanac 3rd ed. p294, height 0.
        let au = 149597870691.0
        let a = 6378136.6 / au
        let f = 1 / 298.25642
        let C = 1 / (cos(lat) * cos(lat) + (1 - f) * (1 - f) * sin(lat) * sin(lat)).squareRoot()
        let S = (1 - f) * (1 - f) * C
        let ecef = Vec3(a * C * cos(lat) * cos(lon), a * C * cos(lat) * sin(lon), a * S * sin(lat))
        return rotZ(-greenwichApparentSiderealTime(jdUT1)) * ecef
    }

    static func xyzToRaDec(_ v: Vec3) -> (ra: Double, de: Double) {
        let r = length(v)
        var l = atan2(v.y, v.x)
        if l < 0 { l += 2 * Double.pi }
        return (l, 0.5 * Double.pi - acos(v.z / r))
    }

    static func greenwichApparentSiderealTime(_ jdUT1: Double) -> Double {
        let twoPi = 2 * Double.pi
        var gast = (greenwichMeanSiderealTime(jdUT1) + equationOfTheEquinoxes(jdUT1)).truncatingRemainder(dividingBy: twoPi)
        if gast < 0 { gast += twoPi }
        return gast
    }

    static func greenwichMeanSiderealTime(_ jdUT1: Double) -> Double {
        let twoPi = 2 * Double.pi
        let t = (jdUT1 - 2451545.0) / 36525.0
        let era = earthRotationAngle(jdUT1)
        let poly = (0.014506 + 4612.15739966 * t + 1.39667721 * t * t + -0.00009344 * t * t * t + 0.00001882 * t * t * t * t) * arcsec
        var gmst = (era + poly).truncatingRemainder(dividingBy: twoPi)
        if gmst < 0 { gmst += twoPi }
        return gmst
    }

    static func earthRotationAngle(_ jdUT1: Double) -> Double {
        let twoPi = 2 * Double.pi
        let t = jdUT1 - 2451545.0
        let frac = jdUT1.truncatingRemainder(dividingBy: 1.0)
        var era = (twoPi * (0.7790572732640 + 0.00273781191135448 * t + frac)).truncatingRemainder(dividingBy: twoPi)
        if era < 0 { era += twoPi }
        return era
    }

    static func equationOfTheEquinoxes(_ jdUT1: Double) -> Double {
        let t = (jdUT1 - 2451545.0) / 36525.0
        let (dpsi, deps) = nutation2000BTruncated(t)
        return dpsi * cos(meanObliquity(t) + deps)
    }

    /// TAI-UTC; no leap seconds have been added since 2017.
    static func leapSeconds(_ jd: Double) -> Double {
        let table: [(Double, Double)] = [
            (2457754.5, 37), (2457204.5, 36), (2456109.5, 35), (2454832.5, 34), (2453736.5, 33),
            (2451179.5, 32), (2450630.5, 31), (2450083.5, 30), (2449534.5, 29), (2449169.5, 28),
            (2448804.5, 27), (2448257.5, 26), (2447892.5, 25), (2447161.5, 24), (2446247.5, 23),
            (2445516.5, 22), (2445151.5, 21), (2444786.5, 20), (2444239.5, 19), (2443874.5, 18),
            (2443509.5, 17), (2443144.5, 16), (2442778.5, 15), (2442413.5, 14), (2442048.5, 13),
            (2441683.5, 12), (2441499.5, 11), (2441317.5, 10),
        ]
        for (start, secs) in table where jd > start { return secs }
        return 0
    }
}
