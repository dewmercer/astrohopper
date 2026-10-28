import Foundation
import Network
import Observation
import SwiftUI

enum WikiMode: String, CaseIterable, Identifiable {
    case never = "no", dayOnly = "day", always = "always"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: "Never"
        case .dayOnly: "Day Only"
        case .always: "Always"
        }
    }
}

/// Screen positions of selectable objects from the last rendered frame.
/// Written by the renderer, read by tap handling; deliberately not observed.
final class HitTargets {
    var items: [(x: Double, y: Double, index: Int)] = []

    func nearest(x: Double, y: Double) -> Int? {
        var best: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for it in items {
            let d = (it.x - x) * (it.x - x) + (it.y - y) * (it.y - y)
            if d < bestDist {
                bestDist = d
                best = it.index
            }
        }
        return best
    }
}

@MainActor
@Observable
final class AppModel {
    static let fovValues: [Double] = [7, 15, 30, 60, 90, 120, 150]

    let motion = MotionTracker()
    let location = LocationProvider()
    private(set) var catalog: Catalog
    @ObservationIgnored private let planets: Planets?
    @ObservationIgnored let hitTargets = HitTargets()
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Reads the device's connection state; it does not contact any server.
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    private(set) var isOnline = false

    // MARK: Settings (persisted under the web app's localStorage key names)

    var fov: Double = 60
    var starMag: Int { didSet { defaults.set(starMag, forKey: "mag_mag_val") } }
    var dsoMag: Int { didSet { defaults.set(dsoMag, forKey: "mag_dso_level_val") } }
    var fontBoost: Int { didSet { defaults.set(fontBoost, forKey: "user_fs") } }
    var nightMode: Bool { didSet { save(nightMode, "NM_checked") } }
    var alignOnDSO: Bool { didSet { save(alignOnDSO, "align_dso_checked") } }
    var showStarNames: Bool { didSet { save(showStarNames, "show_star_names_checked") } }
    var pinchZoom: Bool { didSet { save(pinchZoom, "pinch_zoom") } }
    var showTutorial: Bool { didSet { defaults.set(showTutorial ? "0" : "1", forKey: "qs_hide_v2") } }
    var wikiMode: WikiMode { didSet { defaults.set(wikiMode.rawValue, forKey: "opt_wiki_info_opt") } }
    var shown: [ObjectType: Bool] { didSet { for (t, v) in shown { save(v, "\(t.rawValue)_checked") } } }
    /// Stars per alignment: 1 is the web app's single-star alignment.
    var alignStarsRequired: Int { didSet { defaults.set(alignStarsRequired, forKey: "align_stars") } }
    var finderCircle: Bool { didSet { defaults.set(finderCircle, forKey: "finder_circle") } }
    /// Finder's true field of view, degrees.
    var finderFOV: Double { didSet { defaults.set(finderFOV, forKey: "finder_fov") } }
    var eyepieceCircle: Bool { didSet { defaults.set(eyepieceCircle, forKey: "eyepiece_circle") } }
    var scopeFocalLength: Double { didSet { defaults.set(scopeFocalLength, forKey: "scope_fl") } }
    var eyepieceFocalLength: Double { didSet { defaults.set(eyepieceFocalLength, forKey: "eyepiece_fl") } }
    /// Eyepiece apparent field of view, degrees.
    var eyepieceAFOV: Double { didSet { defaults.set(eyepieceAFOV, forKey: "eyepiece_afov") } }

    /// Eyepiece true field of view in degrees (apparent field ÷ magnification).
    var eyepieceFOV: Double? {
        guard scopeFocalLength > 0, eyepieceFocalLength > 0, eyepieceAFOV > 0 else { return nil }
        return eyepieceAFOV * eyepieceFocalLength / scopeFocalLength
    }

    /// Diameters in degrees of the circles drawn around the view center.
    var fieldCircles: (finder: Double?, eyepiece: Double?) {
        (finderCircle && finderFOV > 0 ? finderFOV : nil, eyepieceCircle ? eyepieceFOV : nil)
    }

    // MARK: Pointing state

    /// `align`: waiting for the user to tap the alignment star; `confirm`:
    /// waiting for them to say the telescope is centered on it.
    enum SelectMode { case target, align, confirm }

    private(set) var selectMode: SelectMode = .target
    private(set) var targetIndex: Int?
    private(set) var alignIndex: Int?
    /// `global_use_gyro`: aligned on a star and tracking with the gyroscope.
    private(set) var aligned = false
    private(set) var useCompass = false
    private(set) var compassAvailable = false
    private var alignment = PointingModel()
    /// Stars used in the current alignment, in order.
    private(set) var alignSamples: [AlignmentSample] = []
    /// RMS mismatch of a multi-star alignment, degrees.
    private(set) var alignmentError: Double?
    /// The star suggested for the next step of a multi-star alignment.
    private(set) var suggestedAlignIndex: Int?
    @ObservationIgnored private var skippedSuggestions: Set<Int> = []
    /// Whether the target (or suggested star) is inside the finder or
    /// eyepiece circle; with some slack before it counts as having left.
    private(set) var guideInFinder = false
    private(set) var guideInEyepiece = false
    private var alphaUserOffset = 0.0
    private var alphaDiff = 0.0
    @ObservationIgnored private var pressStart: TimeInterval?
    /// Alignment in effect before `align()`, restored by `cancelAlign()`.
    @ObservationIgnored private var previousAlignment: (aligned: Bool, model: PointingModel, samples: [AlignmentSample],
                                                        error: Double?, alphaDiff: Double, offset: Double, index: Int?)?
    @ObservationIgnored private var planetsComputedAt: (date: Date, lat: Double, lon: Double)?

    // MARK: Watch lists and user objects

    private(set) var watchListText: String
    private(set) var watchList = WatchList()
    private(set) var currentList = -1
    private var currentItem = -1
    private var currentItemTarget: Int?
    private(set) var userObjectsText: String

    var loadError: String?

    init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ def: Bool) -> Bool {
            (d.string(forKey: "opt_" + key)).map { $0 == "1" } ?? def
        }
        starMag = d.object(forKey: "mag_mag_val") as? Int ?? 4
        dsoMag = d.object(forKey: "mag_dso_level_val") as? Int ?? 5
        fontBoost = d.object(forKey: "user_fs") as? Int ?? 0
        nightMode = flag("NM_checked", false)
        alignOnDSO = flag("align_dso_checked", false)
        showStarNames = flag("show_star_names_checked", true)
        pinchZoom = flag("pinch_zoom", true)
        showTutorial = d.string(forKey: "qs_hide_v2") != "1"
        wikiMode = WikiMode(rawValue: d.string(forKey: "opt_wiki_info_opt") ?? "") ?? .dayOnly
        alignStarsRequired = min(3, max(1, d.object(forKey: "align_stars") as? Int ?? 1))
        finderCircle = d.object(forKey: "finder_circle") as? Bool ?? false
        finderFOV = d.object(forKey: "finder_fov") as? Double ?? 6
        eyepieceCircle = d.object(forKey: "eyepiece_circle") as? Bool ?? false
        scopeFocalLength = d.object(forKey: "scope_fl") as? Double ?? 1200
        eyepieceFocalLength = d.object(forKey: "eyepiece_fl") as? Double ?? 25
        eyepieceAFOV = d.object(forKey: "eyepiece_afov") as? Double ?? 52
        var shown: [ObjectType: Bool] = [:]
        for t in ObjectType.allCases where t != .star {
            shown[t] = flag("\(t.rawValue)_checked", true)
        }
        shown[.star] = true
        self.shown = shown
        watchListText = d.string(forKey: "watch_list") ?? ""
        userObjectsText = d.string(forKey: "user_dso") ?? ""

        do {
            catalog = try Catalog.loadBundled()
        } catch {
            catalog = try! Catalog(json: Data(#"{"objects":[],"typeEnd":{},"lines":[]}"#.utf8))
            loadError = "Could not load the star catalog: \(error.localizedDescription)"
        }
        planets = (try? VSOP87.loadBundled()).map(Planets.init)

        let user = UserObjects.parse(userObjectsText, existing: catalog.baseNames).0
        catalog.setUserObjects(user)
        watchList = WatchList.parse(watchListText) { [catalog] in catalog.contains(normalizedName: $0) }.0
    }

    private func save(_ v: Bool, _ key: String) {
        defaults.set(v ? "1" : "0", forKey: "opt_" + key)
    }

    // MARK: Startup

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated { self?.isOnline = path.status == .satisfied }
        }
        pathMonitor.start(queue: .main)
        location.start()
        motion.start(trueNorth: location.authorized)
        compassAvailable = motion.hasCompass
        if compassAvailable { compassMode() } else { noCompass() }
        setAligned(false)
        updatePlanets(force: true)
    }

    /// Called periodically: switches to the true-north frame once location is
    /// authorized and refreshes planet positions.
    func tick() {
        motion.start(trueNorth: location.authorized)
        if motion.hasCompass != compassAvailable {
            compassAvailable = motion.hasCompass
            if !compassAvailable { noCompass() }
        }
        updatePlanets(force: false)
    }

    private func updatePlanets(force: Bool) {
        guard let planets else { return }
        let now = Date()
        let lat = location.latitude, lon = location.longitude
        if !force, let last = planetsComputedAt,
           now.timeIntervalSince(last.date) < 30, last.lat == lat, last.lon == lon {
            return
        }
        planetsComputedAt = (now, lat, lon)
        let jd = Sky.julianDay(now)
        for i in catalog.planetIndices {
            guard let name = catalog[i].name else { continue }
            let p = planets.raDec(of: name, julianDayUTC: jd, lat: lat, lon: lon)
            catalog.movePlanet(at: i, ra: p.ra, de: p.de)
        }
    }

    // MARK: Pointing model

    /// `gdata.alpha`: the compass in compass mode, fixed at 0 in manual mode.
    private var baseAlpha: Double { useCompass ? (motion.compassAlpha ?? 0) : 0 }

    var currentAlpha: Double {
        aligned ? motion.gyroAlpha + alphaDiff : baseAlpha + alphaUserOffset
    }

    func cameraRays() -> CameraRays {
        CameraRays(deviceToENU: measuredAttitude, alignment: aligned ? alignment : nil)
    }

    /// Device-to-ENU attitude from the sensors, before alignment corrections.
    private var measuredAttitude: Mat3 {
        Mat3.rotZ(degrees: currentAlpha) * motion.tilt
    }

    func equatorialToENU(_ date: Date) -> Mat3 {
        Sky.equatorialToENU(date: date, latDegrees: location.latitude, lonDegrees: location.longitude)
    }

    private func setAligned(_ value: Bool) {
        aligned = value
    }

    /// Altitude/azimuth of the view and, with a target, how far to move:
    /// positive `up` means move up, positive `right` means move right (degrees).
    func pointing(at date: Date) -> (alt: Double, az: Double, up: Double?, right: Double?) {
        let cam = cameraRays()
        let (alt, az) = cam.altAz
        guard let t = guideObject else { return (alt, az, nil, nil) }
        let ray = equatorialToENU(date) * t.eq
        let x = -dot(cam.left, ray), y = dot(cam.top, ray), z = dot(cam.fwd, ray)
        return (alt, az, atan2(y, z) * rad2deg, atan2(x, z) * rad2deg)
    }

    func compassMode() {
        guard compassAvailable else { return }
        useCompass = true
        alphaUserOffset = 0
    }

    func manualMode() {
        alphaUserOffset = baseAlpha
        useCompass = false
    }

    private func noCompass() {
        useCompass = false
        compassAvailable = false
    }

    /// Port of `align()`.
    func align() {
        if aligned && !useCompass {
            // realign in manual mode: keep bearing
            alphaUserOffset = motion.gyroAlpha + alphaDiff - baseAlpha
        }
        previousAlignment = (aligned, alignment, alignSamples, alignmentError, alphaDiff, alphaUserOffset, alignIndex)
        setAligned(false)
        alignIndex = nil
        alignSamples = []
        alignmentError = nil
        skippedSuggestions = []
        suggestedAlignIndex = nil
        selectMode = .align
    }

    /// Between the stars of a multi-star alignment: already aligned on at
    /// least one star and waiting for the next.
    var isAligningNextStar: Bool { selectMode != .target && !alignSamples.isEmpty }

    /// Ends a multi-star alignment with the stars aligned so far.
    func finishAlign() {
        selectMode = .target
        suggestedAlignIndex = nil
        skippedSuggestions = []
        if let last = alignSamples.last { alignIndex = last.index }
    }

    /// Suggests a different star for the next alignment step.
    func suggestAnotherStar() {
        if let s = suggestedAlignIndex { skippedSuggestions.insert(s) }
        suggestNextStar()
        if suggestedAlignIndex == nil, !skippedSuggestions.isEmpty {
            skippedSuggestions = []
            suggestNextStar()
        }
    }

    private func suggestNextStar(date: Date = Date()) {
        let toENU = equatorialToENU(date)
        let used = Set(alignSamples.map(\.index))
        var candidates: [(index: Int, enu: Vec3, mag: Double)] = []
        let maxMag = min(Double(starMag), 2.5)
        for i in 0..<catalog.count where !used.contains(i) && !skippedSuggestions.contains(i) {
            let o = catalog[i]
            guard o.name != nil, o.name != "Moon", shown[o.type] == true else { continue }
            guard (o.type == .star && o.mag <= maxMag) || o.type == .planet else { continue }
            candidates.append((i, toENU * o.eq, o.mag))
        }
        suggestedAlignIndex = Alignment.suggest(candidates: candidates, used: alignSamples.map(\.star))
    }

    /// The suggested alignment star while aligning, otherwise the target.
    var guideObject: SkyObject? {
        if isAligningNextStar, let s = suggestedAlignIndex { return catalog[s] }
        return target
    }

    /// Leaves alignment mode (or drops the chosen star) and restores the
    /// alignment that was in effect before.
    func cancelAlign() {
        guard selectMode != .target else { return }
        if !alignSamples.isEmpty {
            // multi-star: cancelling a chosen star waits for another one;
            // otherwise keep the stars aligned so far
            if selectMode == .confirm {
                selectMode = .align
                alignIndex = alignSamples.last?.index
            } else {
                finishAlign()
            }
            return
        }
        selectMode = .target
        if let p = previousAlignment {
            alignment = p.model
            alignSamples = p.samples
            alignmentError = p.error
            alphaDiff = p.alphaDiff
            alphaUserOffset = p.offset
            alignIndex = p.index
            setAligned(p.aligned)
        }
        previousAlignment = nil
    }

    var alignObject: SkyObject? { alignIndex.map { catalog[$0] } }

    /// Port of `resetAll()`.
    func resetAll() {
        alignSamples = []
        alignmentError = nil
        suggestedAlignIndex = nil
        selectMode = .target
        targetIndex = nil
        alignIndex = nil
        setAligned(false)
    }

    func validAlignType(_ t: ObjectType) -> Bool {
        alignOnDSO ? t != .constellation : (t == .star || t == .planet)
    }

    var waitingForAlign: Bool { selectMode != .target }

    /// Tap on the map at a screen point (selectionEvent).
    func tap(x: Double, y: Double) {
        let index = hitTargets.nearest(x: x, y: y)
        switch selectMode {
        case .target:
            targetIndex = index
        case .align, .confirm:
            // while confirming, tapping another star changes the choice
            if let index { chooseAlignStar(index) }
        }
    }

    /// Replaces `selectAlignWithTimer()`: the chosen star waits for the user
    /// to confirm that the telescope is centered on it.
    func chooseAlignStar(_ index: Int) {
        alignIndex = index
        selectMode = .confirm
    }

    /// How long before the finger touches the Aligned button the attitude
    /// is taken, so the touch itself can't move the alignment.
    static let touchLead: TimeInterval = 0.25

    /// Called when a finger lands on the Aligned button.
    func alignButtonPressed() {
        pressStart = ProcessInfo.processInfo.systemUptime
    }

    /// The user says the telescope is centered on the chosen star.
    func confirmAlign() {
        guard selectMode == .confirm, let index = alignIndex else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let t = min(pressStart ?? now, now) - Self.touchLead
        pressStart = nil
        selectAlign(index, date: Date(timeIntervalSinceNow: t - now), reading: motion.reading(at: t))
    }

    /// Port of `selectAlign()`, extended to several stars. The first star
    /// centers the view exactly, like the web app; each further star refits
    /// the pointing model to all of them.
    /// `reading` is the sensor reading to align with (by default the latest).
    func selectAlign(_ index: Int, date: Date = Date(), reading: MotionTracker.Reading? = nil) {
        let star = equatorialToENU(date) * catalog[index].eq
        let r = reading ?? motion.current
        let base = useCompass ? (r.compassAlpha ?? 0) : 0
        let attitude = Mat3.rotZ(degrees: aligned ? r.gyroAlpha + alphaDiff : base + alphaUserOffset) * r.tilt
        if alignSamples.isEmpty || !aligned {
            let cam = CameraRays(deviceToENU: attitude, alignment: nil)
            alignment = PointingModel(world: Alignment.oneStar(camera: cam, star: star))
            alphaDiff = (base + alphaUserOffset) - r.gyroAlpha
            alignSamples = [AlignmentSample(index: index, deviceToENU: attitude, star: star)]
            alignmentError = nil
        } else {
            // the gyroscope frame from the first star is kept, so all samples agree
            alignSamples.append(AlignmentSample(index: index, deviceToENU: attitude, star: star))
            alignment = Alignment.fit(alignSamples)
            alignmentError = Alignment.rmsError(alignment, alignSamples)
        }
        setAligned(true)
        alignIndex = index
        previousAlignment = nil
        if alignSamples.count < alignStarsRequired {
            selectMode = .align
            skippedSuggestions = []
            suggestNextStar(date: date)
        } else {
            finishAlign()
        }
    }

    /// Called several times a second: tracks whether the target (or the
    /// suggested alignment star) has entered the finder or eyepiece circle.
    func updateProximity(date: Date = Date()) {
        guard aligned, let g = guideObject else {
            guideInFinder = false
            guideInEyepiece = false
            return
        }
        let ray = equatorialToENU(date) * g.eq
        let distance = acos(max(-1, min(1, dot(cameraRays().fwd, ray)))) * rad2deg
        func inside(_ diameter: Double?, _ was: Bool) -> Bool {
            guard let diameter else { return false }
            return distance < diameter / 2 * (was ? 1.15 : 1)
        }
        let circles = fieldCircles
        let finder = inside(circles.finder, guideInFinder)
        let eyepiece = inside(circles.eyepiece, guideInEyepiece)
        if finder != guideInFinder { guideInFinder = finder }
        if eyepiece != guideInEyepiece { guideInEyepiece = eyepiece }
    }

    /// Horizontal drag in manual mode moves the map (`moveSky()`); in demo mode
    /// the drag moves the virtual telescope instead.
    func drag(dx: Double, dy: Double, size: CGSize) {
        let proj = Projection(fovDegrees: fov, width: size.width, height: size.height)
        let fovLR = proj.fovLR
        let fovTD = asin(proj.limY) * 2 * rad2deg
        if motion.isDemo {
            motion.demoMove(dAlpha: dx / size.width * fovLR, dBeta: dy / size.height * fovTD)
        }
        if !useCompass {
            alphaUserOffset += dx / size.width * fovLR
        }
    }

    // MARK: Field of view

    func zoomOut() {
        let v = Self.fovValues
        for i in 0..<(v.count - 1) where fov == v[i] || (v[i] < fov && fov < v[i + 1]) {
            fov = v[i + 1]
            return
        }
    }

    func zoomIn() {
        let v = Self.fovValues
        for i in stride(from: v.count - 1, to: 0, by: -1) where fov == v[i] || (v[i - 1] < fov && fov < v[i]) {
            fov = v[i - 1]
            return
        }
    }

    func pinch(startFOV: Double, scale: Double) {
        guard pinchZoom, scale > 0 else { return }
        let f = 2 * atan(tan(startFOV * deg2rad / 2) / scale) * rad2deg
        fov = max(Self.fovValues.first!, min(Self.fovValues.last!, f.rounded()))
    }

    // MARK: Targets

    var target: SkyObject? { targetIndex.map { catalog[$0] } }

    func selectTarget(_ index: Int?) {
        targetIndex = index
    }

    func clearTarget() {
        targetIndex = nil
    }

    /// Objects matching a search, best matches first.
    func search(_ query: String) -> [Int] {
        catalog.search(query)
    }

    /// Port of `findTargetByName()`.
    @discardableResult
    func findTarget(_ name: String) -> Bool {
        targetIndex = catalog.find(name.trimmingCharacters(in: .whitespaces))
        return targetIndex != nil
    }

    /// The Wikipedia button needs a named target and a network connection.
    var isWikiAllowed: Bool {
        guard isOnline, target?.name != nil else { return false }
        switch wikiMode {
        case .never: return false
        case .dayOnly: return !nightMode
        case .always: return true
        }
    }

    var wikipediaURL: URL? {
        guard let name = target?.name else { return nil }
        var c = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
        c.queryItems = [URLQueryItem(name: "search", value: Format.wikipediaSearchTerm(name))]
        return c.url
    }

    // MARK: Watch lists

    var currentListName: String { currentList >= 0 ? watchList.names[currentList] : "None" }

    /// Port of `markTarget()`.
    var watchListLabel: String {
        guard currentList >= 0, currentItem >= 0 else { return "" }
        let item = watchList.lists[currentList][currentItem]
        if targetIndex == nil { return "?\(item.name)?" }
        return item.comment.isEmpty ? item.name : "\(item.name) (\(item.comment))"
    }

    func nextWatchList() {
        selectWatchList(currentList + 1 >= watchList.lists.count ? -1 : currentList + 1)
    }

    func prevWatchList() {
        selectWatchList(currentList <= -1 ? watchList.lists.count - 1 : currentList - 1)
    }

    var currentWatchItem: WatchList.Item? {
        guard currentList >= 0, currentItem >= 0 else { return nil }
        return watchList.lists[currentList][currentItem]
    }

    /// Watch list position of the target, such as "2 of 6".
    var watchListPosition: String? {
        guard currentList >= 0, currentItem >= 0 else { return nil }
        return "\(currentItem + 1) of \(watchList.lists[currentList].count)"
    }

    func selectWatchList(_ index: Int) {
        if index < 0 || index >= watchList.lists.count {
            targetIndex = nil
            currentList = -1
            currentItem = -1
            currentItemTarget = nil
        } else {
            currentList = index
            currentItem = 0
            findTarget(watchList.lists[index][0].name)
            currentItemTarget = targetIndex
        }
    }

    /// Port of `watchListItemUpdate()`.
    func watchListStep(_ offset: Int) {
        guard currentList >= 0, currentList < watchList.lists.count else { return }
        let list = watchList.lists[currentList]
        // if another object was selected meanwhile, first return to the current item
        let step = currentItemTarget != targetIndex ? 0 : offset
        currentItem = (currentItem + step + list.count) % list.count
        findTarget(list[currentItem].name)
        currentItemTarget = targetIndex
    }

    /// Returns the names that were not found; the list is saved only when empty.
    func saveWatchList(_ text: String) -> [String] {
        let (wl, notFound) = WatchList.parse(text) { catalog.contains(normalizedName: $0) }
        guard notFound.isEmpty else { return notFound }
        selectWatchList(-1)
        watchList = wl
        watchListText = text
        defaults.set(text, forKey: "watch_list")
        return []
    }

    // MARK: User objects

    /// Returns error messages; the objects are saved only when there are none.
    func saveUserObjects(_ text: String) -> [String] {
        let (objects, errors) = UserObjects.parse(text, existing: catalog.baseNames)
        guard errors.isEmpty else { return errors }
        let targetName = target?.name
        catalog.setUserObjects(objects)
        userObjectsText = text
        defaults.set(text, forKey: "user_dso")
        if let t = targetIndex, t >= catalog.count || catalog[t].name != targetName {
            targetIndex = nil
        }
        if let a = alignIndex, a >= catalog.count { alignIndex = nil }
        return []
    }
}
