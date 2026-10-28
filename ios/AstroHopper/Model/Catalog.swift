import Foundation

/// Object type codes, same as in jsdb.js / create_data.py.
enum ObjectType: String, Codable, CaseIterable {
    case star = "S"
    case constellation = "Ca"
    case openCluster = "Oc"
    case globularCluster = "Gc"
    case galaxy = "Ga"
    case nebula = "Ne"
    case planet = "P"
    case user = "U"
}

struct SkyObject {
    var ra: Double
    var de: Double
    var mag: Double
    var name: String?
    var type: ObjectType
    var size: Double
    var altNames: [String]
    /// Equatorial unit vector, cached from `ra`/`de`.
    var eq: Vec3

    init(ra: Double, de: Double, mag: Double, name: String?, type: ObjectType, size: Double = 0, altNames: [String] = []) {
        self.ra = ra
        self.de = de
        self.mag = mag
        self.name = name
        self.type = type
        self.size = size
        self.altNames = altNames
        self.eq = Sky.equatorial(ra: ra, de: de)
    }

    mutating func move(ra: Double, de: Double) {
        self.ra = ra
        self.de = de
        eq = Sky.equatorial(ra: ra, de: de)
    }
}

/// Port of `normalizeName()`: upper-cases and strips zeros/spaces after a catalog
/// prefix, so "ngc 0224" and "NGC224" match.
func normalizeName(_ name: String) -> String {
    var s = name.uppercased()
    while let m = s.wholeMatch(of: /^(.*)(([A-Z]+)[ 0]+)([^0].*)$/) {
        s = String(m.1) + String(m.3) + String(m.4)
    }
    return s
}

/// The object database: bundled catalog objects followed by user objects.
///
/// Objects are grouped by type and each group is sorted by magnitude, so the
/// renderer can skip the rest of a group once it passes the magnitude limit.
/// `typeEnd[t]` is the index one past the end of group `t`.
struct Catalog {
    private(set) var objects: [SkyObject]
    private(set) var typeEnd: [ObjectType: Int]
    let lines: [(ra0: Double, de0: Double, ra1: Double, de1: Double, eq0: Vec3, eq1: Vec3)]
    private(set) var names: [String] = []
    private(set) var nameIndex: [Int] = []
    private let baseCount: Int
    private let baseNameCount: Int

    private struct File: Decodable {
        struct Obj: Decodable {
            let RA: Double
            let DE: Double
            let AM: Double
            let name: String?
            let t: ObjectType
            let s: Double?
            let n2: [String]?
        }
        let objects: [Obj]
        let typeEnd: [String: Int]
        let lines: [[Double]]
    }

    static func loadBundled() throws -> Catalog {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Catalog(json: Data(contentsOf: url))
    }

    init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        objects = file.objects.map {
            SkyObject(ra: $0.RA, de: $0.DE, mag: $0.AM, name: $0.name, type: $0.t, size: $0.s ?? 0, altNames: $0.n2 ?? [])
        }
        var ends: [ObjectType: Int] = [:]
        for (k, v) in file.typeEnd {
            if let t = ObjectType(rawValue: k) { ends[t] = v }
        }
        typeEnd = ends
        lines = file.lines.map { l in
            (l[0], l[1], l[2], l[3], Sky.equatorial(ra: l[0], de: l[1]), Sky.equatorial(ra: l[2], de: l[3]))
        }
        baseCount = objects.count
        // Same order as DSODB.json in create_data.py.
        for (i, o) in objects.enumerated() where o.type != .constellation {
            guard let n = o.name else { continue }
            names.append(normalizeName(n))
            nameIndex.append(i)
            for alt in o.altNames {
                names.append(normalizeName(alt))
                nameIndex.append(i)
            }
        }
        baseNameCount = names.count
    }

    var count: Int { objects.count }

    subscript(i: Int) -> SkyObject { objects[i] }

    var baseNames: Set<String> { Set(names[0..<baseNameCount]) }

    func contains(normalizedName: String) -> Bool { names.contains(normalizedName) }

    mutating func movePlanet(at i: Int, ra: Double, de: Double) {
        objects[i].move(ra: ra, de: de)
    }

    var planetIndices: Range<Int> {
        let end = typeEnd[.planet] ?? 0
        var start = end
        while start > 0 && objects[start - 1].type == .planet { start -= 1 }
        return start..<end
    }

    /// Port of `resetUserDSOsAndMergeNewToAllStars()`.
    mutating func setUserObjects(_ list: [SkyObject]) {
        objects.removeSubrange(baseCount...)
        names.removeSubrange(baseNameCount...)
        nameIndex.removeSubrange(baseNameCount...)
        for o in list {
            names.append(normalizeName(o.name ?? ""))
            nameIndex.append(objects.count)
            objects.append(o)
        }
        typeEnd[.user] = objects.count
    }

    /// Port of `findTargetByName()`: an exact match wins, otherwise a prefix
    /// that matches exactly one name.
    func find(_ query: String) -> Int? {
        let name = normalizeName(query)
        guard !name.isEmpty else { return nil }
        var found = -1
        for (i, candidate) in names.enumerated() {
            if candidate == name {
                found = i
                break
            } else if found != -2 && candidate.hasPrefix(name) {
                found = found == -1 ? i : -2
            }
        }
        return found >= 0 ? nameIndex[found] : nil
    }
}
