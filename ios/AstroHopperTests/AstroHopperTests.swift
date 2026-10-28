import Foundation
import Testing
@testable import AstroHopper

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

private func close(_ a: Vec3, _ b: Vec3, _ tol: Double = 1e-9) -> Bool { length(a - b) <= tol }

struct PlanetTests {
    /// Values computed by the web app's own JS (CPReduce.reduce with vsop87a_combined.js).
    static let reference: [(jd: Double, lat: Double, lon: Double, body: String, ra: Double, de: Double)] = [
        (2461341.6354166665, 31.9, 34.8, "Moon", 56.78623194067883, 24.928001307504445),
        (2461341.6354166665, 31.9, 34.8, "Mercury", 226.399356323687, -20.013644716146256),
        (2461341.6354166665, 31.9, 34.8, "Venus", 203.85624021403032, -16.117827079238644),
        (2461341.6354166665, 31.9, 34.8, "Mars", 139.20918379996212, 17.406662830391728),
        (2461341.6354166665, 31.9, 34.8, "Jupiter", 146.01935640929304, 14.33656220730548),
        (2461341.6354166665, 31.9, 34.8, "Saturn", 9.47077413968257, 1.1515965839441833),
        (2461341.6354166665, 31.9, 34.8, "Neptune", 2.201868594691266, -0.5891127147363489),
        (2461341.6354166665, 31.9, 34.8, "Uranus", 62.48861124650265, 20.875408991858123),
        (2460310.5, 51.5, -0.12, "Moon", 159.32744281898312, 12.119615027123682),
        (2460310.5, 51.5, -0.12, "Mercury", 261.4389975643846, -20.133975345590077),
        (2460310.5, 51.5, -0.12, "Venus", 240.61109989589394, -18.704330608448853),
        (2460310.5, 51.5, -0.12, "Mars", 266.69574090637025, -23.952408188026293),
        (2460310.5, 51.5, -0.12, "Jupiter", 33.361151725921914, 12.150753864243939),
        (2460310.5, 51.5, -0.12, "Saturn", 335.4634290460897, -11.958029896949993),
        (2460310.5, 51.5, -0.12, "Neptune", 355.6667988079569, -3.2239118400110907),
        (2460310.5, 51.5, -0.12, "Uranus", 46.679884149521826, 17.185628474295296),
        (2462668.4375, -33.9, 151.2, "Moon", 265.7037272927413, -21.694876768454712),
        (2462668.4375, -33.9, 151.2, "Mercury", 73.10718974643368, 22.290123154153907),
        (2462668.4375, -33.9, 151.2, "Venus", 49.81404431365395, 16.480031724042842),
        (2462668.4375, -33.9, 151.2, "Mars", 77.83640051360041, 23.45198374191491),
        (2462668.4375, -33.9, 151.2, "Jupiter", 226.43960222744656, -16.290295151377506),
        (2462668.4375, -33.9, 151.2, "Saturn", 59.71529666514608, 18.644161587114567),
        (2462668.4375, -33.9, 151.2, "Neptune", 12.268434732380673, 3.631778001875088),
        (2462668.4375, -33.9, 151.2, "Uranus", 77.61798188784806, 23.006109093005325),
    ]

    @Test func matchesWebAppJavaScript() throws {
        let planets = Planets(vsop: try VSOP87.loadBundled())
        for r in Self.reference {
            let p = planets.raDec(of: r.body, julianDayUTC: r.jd, lat: r.lat, lon: r.lon)
            #expect(close(p.ra, r.ra, 1e-7), "\(r.body) RA \(p.ra) vs \(r.ra)")
            #expect(close(p.de, r.de, 1e-7), "\(r.body) DE \(p.de) vs \(r.de)")
        }
    }

    @Test func earthVelocityIsAboutOneDegreePerDay() throws {
        let planets = Planets(vsop: try VSOP87.loadBundled())
        // ~29.8 km/s = 0.0172 AU/day
        #expect(close(length(planets.earthVelocity(2461341.5)), 0.0172, 0.0005))
    }
}

struct SkyMathTests {
    /// The web app's rayFromPos(), verbatim, for comparison.
    static func rayFromPosJS(ra: Double, de: Double, date: Date, lat: Double, lon: Double) -> Vec3 {
        let RA = ra * deg2rad, DE = de * deg2rad
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let tu = jd - 2451545.0
        let angle = Double.pi * 2 * (0.7790572732640 + 1.00273781191135448 * tu)
        let H = angle + lon * deg2rad - RA
        let f = deg2rad * lat
        let az = atan2(sin(H), cos(H) * sin(f) - tan(DE) * cos(f))
        let hz = asin(sin(f) * sin(DE) + cos(f) * cos(DE) * cos(H))
        return Vec3(-sin(az) * cos(hz), -cos(az) * cos(hz), sin(hz))
    }

    @Test func equatorialToENUMatchesRayFromPos() {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        for (lat, lon) in [(31.9, 34.8), (51.5, -0.12), (-33.9, 151.2)] {
            let m = Sky.equatorialToENU(date: date, latDegrees: lat, lonDegrees: lon)
            for ra in stride(from: 0.0, to: 360, by: 37) {
                for de in stride(from: -85.0, through: 85, by: 17) {
                    let ours = m * Sky.equatorial(ra: ra, de: de)
                    let js = Self.rayFromPosJS(ra: ra, de: de, date: date, lat: lat, lon: lon)
                    #expect(close(ours, js, 1e-9), "ra=\(ra) de=\(de)")
                }
            }
        }
    }

    @Test func attitudeSplitsIntoAlphaAndTilt() {
        for alpha in stride(from: -170.0, through: 170, by: 40) {
            for beta in stride(from: -80.0, through: 80, by: 20) {
                for gamma in stride(from: -80.0, through: 80, by: 40) {
                    let m = Mat3.deviceOrientation(alpha: alpha, beta: beta, gamma: gamma)
                    let a = try! #require(Attitude.alpha(of: m))
                    #expect(close(a, alpha, 1e-9))
                    let tilt = Mat3.rotZ(degrees: -a) * m
                    let (b, g) = Attitude.betaGamma(ofTilt: tilt)
                    #expect(close(b, beta, 1e-9) && close(g, gamma, 1e-9))
                }
            }
        }
    }

    @Test func rodriguesMatchesRotZ() {
        let r = Mat3.rotation(axis: Vec3(0, 0, 1), angle: 30 * deg2rad)
        let z = Mat3.rotZ(degrees: 30)
        for v in [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0.3, -0.2, 0.9)] {
            #expect(close(r * v, z * v))
        }
    }

    @Test func projectionCentersForwardDirection() {
        let p = Projection(fovDegrees: 60, width: 400, height: 800)
        let c = try! #require(p.project(Vec3(0, 0, 1)))
        #expect(close(c.x, 0.5) && close(c.y, 0.5))
        #expect(p.project(Vec3(0, 0, -1)) == nil)
        #expect(close(p.fovLR, 30, 1e-9))
    }
}

@MainActor
struct AlignmentTests {
    @Test func alignmentPutsStarInTheCenter() throws {
        let model = AppModel()
        let sirius = try #require(model.catalog.find("Sirius"))
        let date = Date()
        model.align()
        model.selectAlign(sirius, date: date)
        #expect(model.aligned)
        let fwd = model.cameraRays().fwd
        let star = model.equatorialToENU(date) * model.catalog[sirius].eq
        // the align matrix is exact unless Sirius is far below the horizon from the start
        #expect(dot(fwd, star) > cos(0.01 * deg2rad))
    }
}

struct CatalogTests {
    @Test func loadsBundledCatalog() throws {
        let c = try Catalog.loadBundled()
        #expect(c.count > 9000)
        #expect(c.planetIndices.count == 8)
        #expect(c.find("M31").map { c[$0].name } == "M31")
        #expect(c.find("andromeda galaxy").map { c[$0].name } == "M31")
        #expect(c.find("ngc 07000").map { c[$0].name } == "NGC7000")
        #expect(c.find("Sirius").map { c[$0].type } == .star)
        #expect(c.find("moon").map { c[$0].type } == .planet)
        #expect(c.find("") == nil)
        #expect(c.find("NGC") == nil)  // ambiguous prefix
    }

    @Test func normalizesNames() {
        #expect(normalizeName("ngc 0224") == "NGC224")
        #expect(normalizeName("M 31") == "M31")
        #expect(normalizeName("IC 1000") == "IC1000")
        #expect(normalizeName("Cor Caroli") == "CORCAROLI")  // same as the web app
    }

    @Test func userObjectsAreAppendedAndSearchable() throws {
        var c = try Catalog.loadBundled()
        let base = c.count
        let (objs, errors) = UserObjects.parse("V1405,23h 24m 48s, +61° 11′ 15″\nPluto,19:55:16,-22:13:42", existing: c.baseNames)
        #expect(errors.isEmpty)
        c.setUserObjects(objs)
        #expect(c.count == base + 2)
        #expect(c.find("pluto") == base + 1)
        c.setUserObjects([])
        #expect(c.count == base)
        #expect(c.find("pluto") == nil)
    }
}

struct ParsingTests {
    @Test(arguments: ["170.6358", "11:22:32.6", "11h 22m 32.6s", "11h 22' 32.6''", "11 22′ 32.6″", "11 22 32.6"])
    func parsesRA(_ s: String) throws {
        let ra = try #require(UserObjects.parseRA(s))
        #expect(close(ra, 170.6358, 0.001))
    }

    @Test(arguments: ["-87.3757", "-87:22:32.6", "-87d 22m 32.6s", "-87d 22' 32.6''", "-87° 22′ 32.6″", "-87 22 32.6", "−87 22 32.6"])
    func parsesDEC(_ s: String) throws {
        let de = try #require(UserObjects.parseDEC(s))
        #expect(close(de, -87.3757, 0.001))
    }

    @Test func parsesShortForms() {
        #expect(close(UserObjects.parseRA("11:32")!, 15 * (11 + 32.0 / 60)))
        #expect(close(UserObjects.parseDEC("-87:22")!, -(87 + 22.0 / 60)))
        #expect(close(UserObjects.parseDEC("+61 11 15")!, 61 + 11.0 / 60 + 15.0 / 3600))
    }

    @Test(arguments: ["400.0", "24:00:00", "12:60", "abc", "", "170"])
    func rejectsInvalidRA(_ s: String) {
        #expect(UserObjects.parseRA(s) == nil)
    }

    @Test(arguments: ["91.5", "-91:00", "12:60", "abc", ""])
    func rejectsInvalidDEC(_ s: String) {
        #expect(UserObjects.parseDEC(s) == nil)
    }

    @Test func reportsUserObjectErrors() {
        let (objs, errors) = UserObjects.parse("M31,1:00,2:00\nX\nY,99:00,0:00\nZ,1:00,+95:00\nW,1:00,2:00\nw,1:00,2:00", existing: ["M31"])
        #expect(objs.map(\.name) == ["W"])
        #expect(errors == [
            "Object M31 exists in data base",
            "Too few colums in line 2",
            "Invalid RA value 99:00",
            "Invalid DEC value +95:00",
            "Duplicate object w",
        ])
    }

    @Test func parsesWatchLists() {
        let text = """
        clusters: M41 M47 M49
         M50 M44 M45
        doublestars: Polaris, "Cor Caroli"
        Galaxies: M31 (Andromeda), M64 (Black Eye)
        """
        let (wl, notFound) = WatchList.parse(text) { $0 != "M49" }
        #expect(notFound == ["M49"])
        #expect(wl.names == ["clusters", "doublestars", "Galaxies"])
        #expect(wl.lists[0].map(\.name) == ["M41", "M47", "M49", "M50", "M44", "M45"])
        #expect(wl.lists[1].map(\.name) == ["Polaris", "Cor Caroli"])
        #expect(wl.lists[2] == [.init(name: "M31", comment: "Andromeda"), .init(name: "M64", comment: "Black Eye")])
    }

    @Test func defaultWatchListName() {
        let (wl, _) = WatchList.parse("M41, M47") { _ in true }
        #expect(wl.names == ["default"])
        #expect(wl.lists[0].map(\.name) == ["M41", "M47"])
    }

    @Test func formatsSizes() {
        #expect(Format.size(arcmin: 190) == "3°")
        #expect(Format.size(arcmin: 90) == "1°30′")
        #expect(Format.size(arcmin: 2.5) == "2′30″")
        #expect(Format.size(arcmin: 10.5) == "10′")
        #expect(Format.size(arcmin: 0.5) == "30″")
    }

    @Test func wikipediaSearchTerms() {
        #expect(Format.wikipediaSearchTerm("M31") == "Messier 31")
        #expect(Format.wikipediaSearchTerm("NGC7000") == "NGC 7000")
        #expect(Format.wikipediaSearchTerm("IC434") == "IC 434")
        #expect(Format.wikipediaSearchTerm("Sirius") == "Sirius")
    }
}

@MainActor
struct WikiButtonTests {
    @Test func wikiButtonShowsWhenOnlineWithNamedTarget() async throws {
        let model = AppModel()
        model.nightMode = false
        model.wikiMode = .dayOnly
        model.start()
        for _ in 0..<50 where !model.isOnline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(model.isOnline)
        #expect(!model.isWikiAllowed)  // no target selected yet
        #expect(model.findTarget("M31"))
        #expect(model.isWikiAllowed)
    }
}

struct SearchTests {
    @Test func searchListsExactMatchFirstThenPrefixMatches() throws {
        let c = try Catalog.loadBundled()
        let results = c.search("m4")
        #expect(results.first.map { c[$0].name } == "M4")
        let names = results.compactMap { c[$0].name }
        #expect(names.contains("M41") && names.contains("M42") && names.contains("M45"))
        #expect(Set(results).count == results.count)
        #expect(c.search("  ").isEmpty)
        #expect(c.search("zzzz").isEmpty)
    }

    @Test func searchFindsOtherNames() throws {
        let c = try Catalog.loadBundled()
        #expect(c.search("orion nebula").map { c[$0].name }.contains("M42"))
    }
}

@MainActor
struct CancelAlignTests {
    @Test func cancelRestoresPreviousAlignment() throws {
        let model = AppModel()
        let sirius = try #require(model.catalog.find("Sirius"))
        model.align()
        model.selectAlign(sirius)
        let before = model.cameraRays().fwd

        model.align()
        #expect(!model.aligned && model.selectMode == .align)
        model.cancelAlign()
        #expect(model.aligned && model.selectMode == .target)
        #expect(model.alignIndex == sirius)
        #expect(length(model.cameraRays().fwd - before) < 1e-9)
    }

    @Test func cancelWithoutPriorAlignmentStaysUnaligned() {
        let model = AppModel()
        model.align()
        model.cancelAlign()
        #expect(!model.aligned && model.selectMode == .target && model.alignIndex == nil)
    }
}
