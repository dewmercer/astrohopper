import Foundation
import Network
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
        model.alignStarsRequired = 1
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
        model.alignStarsRequired = 1
        model.align()
        model.cancelAlign()
        #expect(!model.aligned && model.selectMode == .target && model.alignIndex == nil)
    }
}

@MainActor
struct ConfirmAlignTests {
    @Test func choosingAStarWaitsForConfirmation() throws {
        let model = AppModel()
        model.alignStarsRequired = 1
        let sirius = try #require(model.catalog.find("Sirius"))
        let vega = try #require(model.catalog.find("Vega"))
        model.align()
        model.chooseAlignStar(sirius)
        #expect(model.selectMode == .confirm && !model.aligned)
        model.chooseAlignStar(vega)  // changed their mind
        model.confirmAlign()
        #expect(model.aligned && model.selectMode == .target && model.alignIndex == vega)
    }

    @Test func confirmUsesTheAttitudeFromBeforeTheTouch() async throws {
        let model = AppModel()
        model.alignStarsRequired = 1
        let sirius = try #require(model.catalog.find("Sirius"))
        model.align()
        model.chooseAlignStar(sirius)
        model.motion.demoMove(dAlpha: 0, dBeta: 0)  // the steady position
        try await Task.sleep(for: .milliseconds(400))
        model.alignButtonPressed()
        model.motion.demoMove(dAlpha: 3, dBeta: 2)  // the touch shakes the tube
        model.confirmAlign()
        #expect(model.aligned)
        model.motion.demoMove(dAlpha: -3, dBeta: -2)  // back to the steady position
        let star = model.equatorialToENU(Date()) * model.catalog[sirius].eq
        #expect(dot(model.cameraRays().fwd, star) > cos(0.05 * deg2rad))
    }

    @Test func cancellingTheChosenNextStarKeepsWaiting() throws {
        let model = AppModel()
        model.alignStarsRequired = 2
        defer { model.alignStarsRequired = 1 }
        let sirius = try #require(model.catalog.find("Sirius"))
        let vega = try #require(model.catalog.find("Vega"))
        model.align()
        model.selectAlign(sirius)
        model.chooseAlignStar(vega)
        model.cancelAlign()
        #expect(model.selectMode == .align && model.isAligningNextStar && model.alignIndex == sirius)
    }
}

struct MultiStarFitTests {
    /// Phone attitude with its top edge at roughly azimuth `az`, altitude `alt`.
    func attitude(_ az: Double, _ alt: Double) -> Mat3 {
        Mat3.rotZ(degrees: -az) * Mat3.tilt(beta: alt, gamma: 0)
    }

    func angle(_ a: Vec3, _ b: Vec3) -> Double {
        acos(max(-1, min(1, dot(normalize(a), normalize(b))))) * rad2deg
    }

    /// The phone is mounted 2° off the tube axis and the compass is 3° off.
    let truth2 = PointingModel(world: Mat3.rotZ(degrees: 3), tubeAxis: normalize(Vec3(0.035, 1, -0.02)))

    func samples(_ truth: PointingModel, _ points: [(Double, Double)]) -> [AlignmentSample] {
        points.enumerated().map { i, p in
            let d = attitude(p.0, p.1)
            return AlignmentSample(index: i, deviceToENU: d, star: normalize(truth.direction(deviceToENU: d)))
        }
    }

    @Test func twoStarsRecoverMountingOffset() {
        let s = samples(truth2, [(20, 30), (110, 60)])
        let fit = Alignment.fit(s)
        #expect(Alignment.rmsError(fit, s) < 0.01)
        for (az, alt) in [(250.0, 45.0), (330, 20), (180, 70)] {
            let d = attitude(az, alt)
            #expect(angle(fit.direction(deviceToENU: d), truth2.direction(deviceToENU: d)) < 0.1)
        }
    }

    @Test func twoStarsBeatOneStarAwayFromTheAlignmentStar() {
        let s = samples(truth2, [(20, 30), (110, 60)])
        let fit = Alignment.fit(s)
        let cam = CameraRays(deviceToENU: s[0].deviceToENU, alignment: nil)
        let one = PointingModel(world: Alignment.oneStar(camera: cam, star: s[0].star))
        let d = attitude(200, 65)
        let truth = truth2.direction(deviceToENU: d)
        let oneStarError = angle(one.direction(deviceToENU: d), truth)
        let twoStarError = angle(fit.direction(deviceToENU: d), truth)
        #expect(oneStarError > 1)
        #expect(twoStarError < 0.1)
    }

    @Test func threeStarsRecoverTilt() {
        let tilt = Mat3.rotation(axis: Vec3(1, 0, 0), angle: 0.6 * deg2rad) * Mat3.rotation(axis: Vec3(0, 1, 0), angle: -0.4 * deg2rad)
        let truth = PointingModel(world: Mat3.rotZ(degrees: -4) * tilt, tubeAxis: normalize(Vec3(-0.02, 1, 0.03)))
        let s = samples(truth, [(10, 25), (120, 55), (240, 40)])
        let fit = Alignment.fit(s)
        #expect(Alignment.rmsError(fit, s) < 0.02)
        for (az, alt) in [(300.0, 35.0), (60, 70), (180, 20)] {
            let d = attitude(az, alt)
            #expect(angle(fit.direction(deviceToENU: d), truth.direction(deviceToENU: d)) < 0.1)
        }
    }

    @Test func badlySpreadStarsStayReasonable() {
        // two stars almost on top of each other can't pin the model down
        let s = samples(truth2, [(20, 30), (22, 31)])
        let fit = Alignment.fit(s)
        #expect(Alignment.rmsError(fit, s) < 0.05)
        #expect(angle(fit.tubeAxis, Vec3(0, 1, 0)) < 10)
    }

    @Test func suggestsAStarAboutNinetyDegreesAway() {
        func dir(_ az: Double, _ alt: Double) -> Vec3 {
            let a = az * deg2rad, h = alt * deg2rad
            return Vec3(cos(h) * sin(a), cos(h) * cos(a), sin(h))
        }
        let used = [dir(0, 40)]
        let candidates: [(index: Int, enu: Vec3, mag: Double)] = [
            (1, dir(30, 40), 0.0),   // too close
            (2, dir(120, 30), 1.0),  // about 90° away
            (3, dir(180, -10), 0.0), // below the horizon
            (4, dir(0, 85), 0.0),    // near the zenith
            (5, dir(170, 30), 2.5),  // well away but faint
        ]
        #expect(Alignment.suggest(candidates: candidates, used: used) == 2)
        #expect(Alignment.suggest(candidates: [candidates[0], candidates[2]], used: used) == nil)
    }

    @Test func thirdStarAvoidsTheFirstTwosGreatCircle() {
        func dir(_ az: Double, _ alt: Double) -> Vec3 {
            let a = az * deg2rad, h = alt * deg2rad
            return Vec3(cos(h) * sin(a), cos(h) * cos(a), sin(h))
        }
        let used = [dir(0, 20), dir(90, 20)]
        let candidates: [(index: Int, enu: Vec3, mag: Double)] = [
            (1, dir(200, 20), 1.0), // near the same great circle
            (2, dir(225, 60), 1.0), // well off it
        ]
        #expect(Alignment.suggest(candidates: candidates, used: used) == 2)
    }
}

@MainActor
struct MultiStarFlowTests {
    @Test func twoStarAlignmentAsksForASecondStar() throws {
        let model = AppModel()
        model.alignStarsRequired = 2
        defer { model.alignStarsRequired = 1 }
        let sirius = try #require(model.catalog.find("Sirius"))
        let vega = try #require(model.catalog.find("Vega"))

        model.align()
        model.selectAlign(sirius)
        #expect(model.aligned && model.isAligningNextStar && model.selectMode == .align)
        #expect(model.suggestedAlignIndex != sirius)

        model.selectAlign(vega)
        #expect(model.aligned && !model.isAligningNextStar && model.selectMode == .target)
        #expect(model.alignSamples.map(\.index) == [sirius, vega])
        #expect(model.alignmentError != nil)
    }

    @Test func doneAfterOneStarKeepsThatAlignment() throws {
        let model = AppModel()
        model.alignStarsRequired = 3
        defer { model.alignStarsRequired = 1 }
        let sirius = try #require(model.catalog.find("Sirius"))
        model.align()
        model.selectAlign(sirius)
        let fwd = model.cameraRays().fwd
        model.finishAlign()
        #expect(model.aligned && model.selectMode == .target && model.alignIndex == sirius)
        #expect(length(model.cameraRays().fwd - fwd) < 1e-9)
        #expect(model.suggestedAlignIndex == nil)
    }

    @Test func cancellingNextStarCountdownKeepsWaiting() throws {
        let model = AppModel()
        model.alignStarsRequired = 2
        defer { model.alignStarsRequired = 1 }
        let sirius = try #require(model.catalog.find("Sirius"))
        model.align()
        model.selectAlign(sirius)
        model.cancelAlign()  // in align mode between stars: finishes
        #expect(model.selectMode == .target && model.aligned)
    }
}

@MainActor
struct FieldCircleTests {
    @Test func eyepieceTrueField() {
        let model = AppModel()
        let saved = (model.scopeFocalLength, model.eyepieceFocalLength, model.eyepieceAFOV, model.eyepieceCircle)
        defer {
            (model.scopeFocalLength, model.eyepieceFocalLength, model.eyepieceAFOV, model.eyepieceCircle) = saved
        }
        model.scopeFocalLength = 1200
        model.eyepieceFocalLength = 25
        model.eyepieceAFOV = 52
        model.eyepieceCircle = true
        #expect(abs((model.eyepieceFOV ?? 0) - 52.0 / 48) < 1e-9)
        model.eyepieceCircle = false
        #expect(model.fieldCircles.eyepiece == nil)
    }
}

struct AUXTests {
    @Test func encodesPacketsWithChecksum() {
        // MC_GET_POSITION from the app to the azimuth motor
        #expect(AUX.Packet(.getPosition, to: .azimuth).bytes == [0x3B, 0x03, 0x20, 0x10, 0x01, 0xCC])
        let p = AUX.Packet(.gotoFast, to: .altitude, data: AUX.encode(0x40_0000))
        #expect(p.bytes == [0x3B, 0x06, 0x20, 0x11, 0x02, 0x40, 0x00, 0x00, 0x87])
        #expect(p.value == 0x40_0000)
    }

    @Test func parsesAStreamWithNoiseAndSplitPackets() {
        var parser = AUX.Parser()
        let a = AUX.Packet(source: 0x10, destination: 0x20, command: 0x01, data: [0x12, 0x34, 0x56])
        let b = AUX.Packet(source: 0x11, destination: 0x20, command: 0x13, data: [0xFF])
        var bad = b.bytes
        bad[bad.count - 1] ^= 0x55
        let stream = [0x00, 0x3B] + bad + a.bytes + b.bytes
        #expect(parser.feed(Array(stream[0..<10])) == [])
        #expect(parser.feed(Array(stream[10...])) == [a, b])
        #expect(a.value == 0x12_3456)
    }

    @Test func stepConversionRoundTrips() {
        #expect(MountModel.steps(degrees: 90) == 0x40_0000)
        #expect(MountModel.steps(degrees: -90) == 0xC0_0000)
        #expect(MountModel.degrees(steps: 0xC0_0000) == -90)
        #expect(abs(MountModel.degrees(steps: MountModel.steps(degrees: 123.456)) - 123.456) < 1e-4)
    }
}

struct MountModelTests {
    func angle(_ a: Vec3, _ b: Vec3) -> Double {
        acos(max(-1, min(1, dot(normalize(a), normalize(b))))) * rad2deg
    }

    /// A mount whose encoders are 37° and -2° off, isn't quite level, and
    /// whose tube is 1° off square, optionally with a reversed axis.
    func truth(_ type: MountType, latitude: Double, signs: (axis1: Double, axis2: Double) = (1, 1),
               tilt tiltDegrees: Double = 0.3) -> MountModel {
        let az = Mat3.rotZ(degrees: 37)
        let tilt = Mat3.rotation(axis: Vec3(1, 0, 0), angle: tiltDegrees * deg2rad)
        var m = MountModel(type: type, latitude: latitude, signs: signs)
        m.pointing = PointingModel(world: az * tilt, tubeAxis: normalize(Vec3(0.017, 1, -0.035)))
        return m
    }

    func samples(_ m: MountModel, _ axes: [(Double, Double)]) -> [MountSample] {
        axes.enumerated().map { i, a in MountSample(index: i, axis1: a.0, axis2: a.1, star: m.direction(a.0, a.1)) }
    }

    @Test func threeStarAltAzGotoIsAccurate() throws {
        let t = truth(.altAz, latitude: 32)
        let s = samples(t, [(10, 30), (130, 50), (250, 20)])
        let fit = try #require(MountModel.fit(.altAz, latitude: 32, samples: s))
        #expect(fit.rmsError(s) < 0.05)
        for (a1, a2) in [(70.0, 60.0), (190, 35), (320, 15)] {
            let target = t.direction(a1, a2)
            let axes = fit.axes(for: target)
            #expect(angle(t.direction(axes.axis1, axes.axis2), target) < 0.1)
        }
    }

    @Test func detectsAReversedAxis() throws {
        // level, so two stars can model it exactly; only three stars fit a tilt
        let t = truth(.altAz, latitude: 32, signs: (-1, 1), tilt: 0)
        let s = samples(t, [(10, 30), (130, 50)])
        let fit = try #require(MountModel.fit(.altAz, latitude: 32, samples: s))
        #expect(fit.signs.axis1 == -1 && fit.signs.axis2 == 1)
        let target = t.direction(200, 40)
        let axes = fit.axes(for: target)
        let error = angle(t.direction(axes.axis1, axes.axis2), target)
        #expect(error < 0.05, "goto error \(error)°")
    }

    @Test func equatorialMountUsesThePoleFrame() throws {
        for lat in [45.0, -33.0] {
            let t = truth(.equatorial, latitude: lat)
            let s = samples(t, [(-40, 20), (30, 60), (80, -10)])
            let fit = try #require(MountModel.fit(.equatorial, latitude: lat, samples: s))
            #expect(fit.rmsError(s) < 0.05)
            let target = t.direction(10, 35)
            let axes = fit.axes(for: target)
            #expect(angle(t.direction(axes.axis1, axes.axis2), target) < 0.1)
        }
        // the frame's vertical is the celestial pole
        let f = MountModel.frame(.equatorial, latitude: 45)
        #expect(angle(f * Vec3(0, cos(45 * deg2rad), sin(45 * deg2rad)), Vec3(0, 0, 1)) < 1e-9)
    }

    @Test func trackingRatesFollowTheTargetAndRemoveErrors() {
        let r = TelescopeController.trackingRates(here: (100, 40), ahead: (100.05, 39.98), current: (99.9, 40), offset: (0, 0))
        #expect(abs(r.axis1 - (0.005 + 0.025)) < 1e-9)
        #expect(abs(r.axis2 - (-0.002)) < 1e-9)
        // wrapping across ±180°
        let w = TelescopeController.trackingRates(here: (179.99, 0), ahead: (-179.99, 0), current: (179.99, 0), offset: (0, 0))
        #expect(abs(w.axis1 - 0.002) < 1e-9)
    }
}

/// A stand-in for the SkyPortal module: echoes every packet like the AUX
/// bus does, then answers as the two motor controllers. Gotos arrive
/// instantly.
final class FakeSkyPortal: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-skyportal")
    private let lock = NSLock()
    private var positions: [UInt8: UInt32] = [0x10: 0, 0x11: 0]
    private(set) var commands: [AUX.Packet] = []

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: cont.resume(returning: listener.port!.rawValue)
                case let .failed(e): cont.resume(throwing: e)
                default: break
                }
                listener.stateUpdateHandler = nil
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    func setAxes(_ a1: Double, _ a2: Double) {
        lock.withLock { positions = [0x10: MountModel.steps(degrees: a1), 0x11: MountModel.steps(degrees: a2)] }
    }

    var axes: (Double, Double) {
        lock.withLock { (MountModel.degrees(steps: positions[0x10]!), MountModel.degrees(steps: positions[0x11]!)) }
    }

    func received(_ command: UInt8) -> Bool { lock.withLock { commands.contains { $0.command == command } } }

    private var parsers: [ObjectIdentifier: AUX.Parser] = [:]

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn)
    }

    /// Runs on `queue` only.
    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, _ in
            guard let self, let data else { return }
            var parser = parsers[ObjectIdentifier(conn)] ?? AUX.Parser()
            for p in parser.feed([UInt8](data)) {
                // the bus echoes the request before the reply
                conn.send(content: Data(p.bytes + reply(to: p).bytes), completion: .idempotent)
            }
            parsers[ObjectIdentifier(conn)] = parser
            if !done { receive(conn) }
        }
    }

    private func reply(to p: AUX.Packet) -> AUX.Packet {
        lock.withLock {
            commands.append(p)
            var data: [UInt8] = []
            switch AUX.Command(rawValue: p.command) {
            case .getPosition: data = AUX.encode(positions[p.destination] ?? 0)
            case .gotoFast, .gotoSlow: positions[p.destination] = p.value
            case .slewDone: data = [0xFF]
            case .getVersion: data = [7, 11, 0, 0]
            default: break
            }
            return AUX.Packet(source: p.destination, destination: 0x20, command: p.command, data: data)
        }
    }
}

@MainActor
struct TelescopeSessionTests {
    func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw TelescopeError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func connectsAlignsSlewsAndTracks() async throws {
        let fake = try FakeSkyPortal()
        let port = try await fake.start()
        defer { fake.stop() }

        let scope = TelescopeController()
        let saved = (scope.enabled, scope.connectionMode, scope.networkHost, scope.mountType, scope.trackAfterGoto, scope.minAltitude)
        defer {
            scope.disconnect()
            (scope.enabled, scope.connectionMode, scope.networkHost, scope.mountType, scope.trackAfterGoto, scope.minAltitude) = saved
        }
        scope.enabled = true
        scope.mountType = .altAz
        scope.connectionMode = .network
        scope.networkHost = "127.0.0.1"
        scope.trackAfterGoto = true
        scope.minAltitude = 0
        scope.port = port
        scope.connect()
        try await waitUntil { scope.state == .connected }

        // the mount's true pointing: encoders 20° off in azimuth
        var truth = MountModel(type: .altAz, latitude: 32)
        truth.pointing = PointingModel(world: Mat3.rotZ(degrees: 20))
        for (i, (a1, a2)) in [(30.0, 40.0), (150, 55)].enumerated() {
            fake.setAxes(a1, a2)
            scope.addAlignmentStar(index: i, star: truth.direction(a1, a2), latitude: 32, restart: i == 0)
            try await waitUntil { scope.samples.count == i + 1 }
        }
        #expect(scope.isAligned)
        #expect((scope.alignmentError ?? 1) < 0.01)

        let target = truth.direction(250, 30)
        scope.goto(name: "Test Star") { _ in target }
        try await waitUntil { scope.activity == .tracking }
        let reached = fake.axes
        #expect(abs(MountModel.wrap180(reached.0 - 250)) < 0.01 && abs(reached.1 - 30) < 0.01)
        #expect(fake.received(AUX.Command.gotoFast.rawValue) && fake.received(AUX.Command.gotoSlow.rawValue))
        try await waitUntil { fake.received(AUX.Command.setPosGuideRate.rawValue) || fake.received(AUX.Command.setNegGuideRate.rawValue) }

        // tracking can be turned off and back on without another goto
        scope.setTracking(false)
        #expect(scope.activity == .idle && !scope.trackAfterGoto)
        scope.setTracking(true)
        #expect(scope.activity == .tracking)

        scope.stop()
        try await waitUntil { scope.activity == .idle }
    }

    @Test func gotoWithoutTrackingStopsAtTheTarget() async throws {
        let fake = try FakeSkyPortal()
        let port = try await fake.start()
        defer { fake.stop() }
        let scope = TelescopeController()
        let saved = (scope.enabled, scope.connectionMode, scope.networkHost, scope.trackAfterGoto, scope.minAltitude)
        defer {
            scope.disconnect()
            (scope.enabled, scope.connectionMode, scope.networkHost, scope.trackAfterGoto, scope.minAltitude) = saved
        }
        scope.enabled = true
        scope.connectionMode = .network
        scope.networkHost = "127.0.0.1"
        scope.minAltitude = 0
        scope.port = port
        scope.setTracking(false)
        scope.connect()
        try await waitUntil { scope.state == .connected }
        fake.setAxes(0, 45)
        let truth = MountModel(type: scope.mountType, latitude: 32)
        scope.addAlignmentStar(index: 0, star: truth.direction(0, 45), latitude: 32, restart: true)
        try await waitUntil { scope.isAligned }

        let target = truth.direction(90, 50)
        scope.goto(name: "Test Star") { _ in target }
        try await waitUntil { scope.activity == .idle && fake.received(AUX.Command.gotoSlow.rawValue) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!fake.received(AUX.Command.setPosGuideRate.rawValue) || fake.commands.filter {
            $0.command == AUX.Command.setPosGuideRate.rawValue || $0.command == AUX.Command.setNegGuideRate.rawValue
        }.allSatisfy { $0.value == 0 })
        #expect(scope.targetName == "Test Star")
    }

    @Test func reportsAMissingModule() async throws {
        let scope = TelescopeController()
        let saved = (scope.connectionMode, scope.networkHost)
        defer { (scope.connectionMode, scope.networkHost) = saved }
        scope.connectionMode = .network
        scope.networkHost = "127.0.0.1"
        scope.port = 1  // nothing listens here
        scope.connect()
        try await waitUntil(.seconds(8)) { scope.state == .disconnected && scope.lastError != nil }
    }
}
