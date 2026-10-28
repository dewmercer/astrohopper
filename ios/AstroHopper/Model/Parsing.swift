import Foundation

// MARK: Watch lists

struct WatchList: Equatable {
    struct Item: Equatable {
        var name: String
        var comment: String = ""
    }

    var names: [String] = []
    var lists: [[Item]] = []

    /// Port of `tokenizeWL()`: commas, colons, quoted strings, parentheses and
    /// words; whitespace and commas are dropped.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var i = text.startIndex
        let special: Set<Character> = [",", ":", "\"", "(", ")"]
        while i < text.endIndex {
            let c = text[i]
            if c.isWhitespace {
                i = text.index(after: i)
            } else if c == "\"", let close = text[text.index(after: i)...].firstIndex(of: "\"") {
                tokens.append(String(text[i...close]))
                i = text.index(after: close)
            } else if special.contains(c) {
                tokens.append(String(c))
                i = text.index(after: i)
            } else {
                var j = i
                while j < text.endIndex && !text[j].isWhitespace && !special.contains(text[j]) {
                    j = text.index(after: j)
                }
                tokens.append(String(text[i..<j]))
                i = j
            }
        }
        return tokens.filter { $0 != "," }
    }

    /// Port of `parseWatchList()`. Returns the lists and the names not found by
    /// `exists`.
    static func parse(_ text: String, exists: (String) -> Bool) -> (WatchList, notFound: [String]) {
        var wl = WatchList()
        var notFound: [String] = []
        var index: [String: Int] = [:]
        let items = tokenize(text)
        var listName = "default"
        var i = 0
        while i < items.count {
            let item = items[i].replacingOccurrences(of: "\"", with: "")
            if i + 1 < items.count && items[i + 1] == ":" {
                listName = item
                i += 2
                continue
            }
            if item == "(" {
                i += 1
                let start = i
                while i < items.count && items[i] != ")" { i += 1 }
                if i > start, let li = index[listName], !wl.lists[li].isEmpty {
                    wl.lists[li][wl.lists[li].count - 1].comment = items[start..<i].joined(separator: " ")
                }
                i += 1
                continue
            }
            if item == ")" || item.isEmpty {
                i += 1
                continue
            }
            if !exists(normalizeName(item)) { notFound.append(item) }
            if index[listName] == nil {
                index[listName] = wl.names.count
                wl.names.append(listName)
                wl.lists.append([])
            }
            wl.lists[index[listName]!].append(Item(name: item))
            i += 1
        }
        return (wl, notFound)
    }
}

// MARK: User objects

enum UserObjects {
    /// Port of `parseUserDSO()`. Returns parsed objects and error messages.
    static func parse(_ text: String, existing: Set<String>) -> ([SkyObject], errors: [String]) {
        var errors: [String] = []
        var objects: [SkyObject] = []
        var newNames = Set<String>()
        let rows = text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } }
        for (i, cols) in rows.enumerated() {
            if cols.count < 3 {
                errors.append("Too few colums in line \(i + 1)")
                continue
            }
            let name = cols[0]
            if name.isEmpty {
                errors.append("Empty object name in line \(i + 1)")
                continue
            }
            let sname = normalizeName(name)
            if existing.contains(sname) {
                errors.append("Object \(name) exists in data base")
                continue
            }
            if newNames.contains(sname) {
                errors.append("Duplicate object \(name)")
                continue
            }
            guard let ra = parseRA(cols[1]) else {
                errors.append("Invalid RA value \(cols[1])")
                continue
            }
            guard let de = parseDEC(cols[2]) else {
                errors.append("Invalid DEC value \(cols[2])")
                continue
            }
            newNames.insert(sname)
            objects.append(SkyObject(ra: ra, de: de, mag: -1, name: name, type: .user))
        }
        return (objects, errors)
    }

    private static let secondsMark = #"(?:s|S|′′|″|''|")"#

    /// RA as decimal degrees (0-360) or hours/minutes[/seconds].
    static func parseRA(_ s: String) -> Double? {
        if let m = s.wholeMatch(of: /(\d+\.\d+)/) {
            guard let deg = Double(m.1), deg >= 0, deg <= 360 else { return nil }
            return deg
        }
        let patterns = [
            #"(\d+):(\d+)(?::(\d+(?:\.\d+)?))?"#,
            #"(\d+)[hH \t]\s*(\d+)[mM'′]\s*(?:(\d+(?:\.\d+)?)"# + secondsMark + ")?",
            #"(\d+)\s+(\d+)(?:\s+(\d+(?:\.\d+)?))?"#,
        ]
        guard let (h, m, sec) = matchFields(s, patterns: patterns, signed: false) else { return nil }
        guard h < 24, m < 60, sec < 60 else { return nil }
        return 15 * (h + (60 * m + sec) / 3600)
    }

    /// DEC as decimal degrees (-90...90) or degrees/minutes[/seconds].
    static func parseDEC(_ s: String) -> Double? {
        let s = s.replacingOccurrences(of: "−", with: "-")
        if let m = s.wholeMatch(of: /([+-]?\d+\.\d+)/) {
            guard let deg = Double(m.1), deg >= -90, deg <= 90 else { return nil }
            return deg
        }
        let patterns = [
            #"([-+]?)(\d+):(\d+)(?::(\d+(?:\.\d+)?))?"#,
            #"([-+]?)(\d+)[dD° \t]\s*(\d+)[mM'′]\s*(?:(\d+(?:\.\d+)?)"# + secondsMark + ")?",
            #"([-+]?)(\d+)\s+(\d+)(?:\s+(\d+(?:\.\d+)?))?"#,
        ]
        let sign: Double = s.hasPrefix("-") ? -1 : 1
        guard let (d, m, sec) = matchFields(s, patterns: patterns, signed: true) else { return nil }
        guard d <= 90, m < 60, sec < 60 else { return nil }
        return sign * (d + (60 * m + sec) / 3600)
    }

    /// Matches the first pattern that fits the whole string and returns its
    /// (major, minutes, seconds) fields; a leading sign group is skipped.
    private static func matchFields(_ s: String, patterns: [String], signed: Bool) -> (Double, Double, Double)? {
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: "^" + p + "$"),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { continue }
            func group(_ i: Int) -> Double? {
                guard let r = Range(m.range(at: i), in: s) else { return nil }
                return Double(s[r])
            }
            let first = signed ? 2 : 1
            guard let major = group(first), let minutes = group(first + 1) else { return nil }
            return (major, minutes, group(first + 2) ?? 0)
        }
        return nil
    }
}

// MARK: Formatting

enum Format {
    /// Port of `formatSize()` (arcminutes to a short angle string).
    static func size(arcmin: Double) -> String {
        let limFactor = 3.0
        if arcmin >= 60 {
            let deg = (arcmin / 60).rounded(.down)
            var res = "\(Int(deg))°"
            let m = (arcmin - deg * 60).rounded(.down)
            if arcmin < 60 * limFactor && m != 0 { res += "\(Int(m))′" }
            return res
        } else if arcmin >= 1 {
            let m = arcmin.rounded(.down)
            var res = "\(Int(m))′"
            let s = ((arcmin - m) * 60).rounded(.down)
            if arcmin < limFactor && s != 0 { res += "\(Int(s))″" }
            return res
        }
        return "\(Int((arcmin * 60).rounded(.down)))″"
    }

    /// Port of `formatLatLon()`.
    static func dms(_ deg: Double, positive: String, negative: String) -> String {
        let direction = deg >= 0 ? positive : negative
        let d = abs(deg)
        let ideg = d.rounded(.down)
        let min = 60 * (d - ideg)
        let imin = min.rounded(.down)
        let sec = 60 * (min - imin)
        return "\(direction)\(Int(ideg))°\(Int(imin))'\(String(format: "%.1f", sec))''"
    }

    /// Wikipedia search term: "M31" -> "Messier 31", "NGC224" -> "NGC 224".
    static func wikipediaSearchTerm(_ name: String) -> String {
        if let m = name.wholeMatch(of: /M(\d*)/) { return "Messier \(m.1)" }
        if let m = name.wholeMatch(of: /(NGC|IC)(\d*)/) { return "\(m.1) \(m.2)" }
        return name
    }
}
