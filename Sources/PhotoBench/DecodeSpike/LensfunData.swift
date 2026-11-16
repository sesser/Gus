import Foundation

// SPIKE for issue #194 (question 4): throwaway. A small reader of the lensfun
// database's XML (data only; no lensfun code), written from the database
// format as lensfun's manual describes it ("Database file format", "Lens
// calibration data format"): <camera> with maker, model, mount, cropfactor;
// <lens> with maker, model (several, by language), mount, cropfactor,
// aspect-ratio, center, type and <calibration> holding <distortion>, <tca>
// and <vignetting> entries. Nothing from the database is copied into the
// repository: the folder is read at run time (`--lensfun DIR`).

struct LensfunCamera {
    var maker = "", model = "", mount = "", variant = ""
    var cropFactor = 0.0
}

struct LensfunLens {
    var maker = "", models: [String] = [], mounts: [String] = []
    var cropFactor = 0.0
    /// Long edge over short edge of the calibration camera; 1.5 when not given (the manual's default).
    var aspectRatio = 1.5
    var centerX = 0.0, centerY = 0.0
    var type = "rectilinear"
    var distortion: [[String: String]] = []
    var tca: [[String: String]] = []
    var vignetting: [[String: String]] = []
    var file = ""
}

final class LensfunDatabase: NSObject, XMLParserDelegate {
    var cameras: [LensfunCamera] = []
    var lenses: [LensfunLens] = []
    var files = 0
    private var camera: LensfunCamera?
    private var lens: LensfunLens?
    private var text = ""
    private var attributes: [String: String] = [:]
    private var file = ""

    init(folder: URL) throws {
        super.init()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".xml") }.sorted()
        for name in names {
            file = name
            guard let parser = XMLParser(contentsOf: folder.appending(path: name)) else { continue }
            parser.delegate = self
            guard parser.parse() else { throw BenchError("\(name): \(parser.parserError.map(String.init(describing:)) ?? "parse error")") }
            files += 1
        }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        self.attributes = attributes
        switch element {
        case "camera": camera = LensfunCamera()
        case "lens": lens = LensfunLens(file: file)
        case "center": lens?.centerX = Double(attributes["x"] ?? "0") ?? 0; lens?.centerY = Double(attributes["y"] ?? "0") ?? 0
        case "distortion": lens?.distortion.append(attributes)
        case "tca": lens?.tca.append(attributes)
        case "vignetting": lens?.vignetting.append(attributes)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if var c = camera {
            switch element {
            case "maker" where attributes["lang"] == nil: c.maker = value
            case "model" where attributes["lang"] == nil: c.model = value
            case "mount": c.mount = value
            case "variant": c.variant = value
            case "cropfactor": c.cropFactor = Double(value) ?? 0
            case "camera": cameras.append(c); camera = nil; return
            default: break
            }
            camera = c
        } else if var l = lens {
            switch element {
            case "maker" where attributes["lang"] == nil: l.maker = value
            case "model": l.models.append(value)
            case "mount": l.mounts.append(value)
            case "cropfactor": l.cropFactor = Double(value) ?? 0
            case "aspect-ratio":
                let parts = value.split(separator: ":").compactMap { Double($0) }
                l.aspectRatio = parts.count == 2 ? parts[0] / parts[1] : (Double(value) ?? 1.5)
            case "type": l.type = value
            case "lens": lenses.append(l); lens = nil; return
            default: break
            }
            lens = l
        }
        text = ""
    }

    // MARK: Matching (our own rules, not lensfun's)

    static func normalized(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !($0.isLetter || $0.isNumber || $0 == ".") }.map(String.init).filter { !$0.isEmpty })
    }

    /// Focal range and smallest f-number in a lens name, by the manual's two
    /// patterns ("12-32mm f/3.5-5.6" and "3.5-5.6/12-32"); camera strings
    /// like "12-32/F3.5-5.6" are the first with "mm" left out.
    static func parameters(_ name: String) -> (focal: ClosedRange<Double>, aperture: Double?)? {
        // "1:4" is an f-number written as a ratio (older lenses).
        let s = name.lowercased().replacingOccurrences(of: "mm", with: " ").replacingOccurrences(of: "f/", with: " f")
            .replacingOccurrences(of: "1:", with: " f")
        let pattern = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?"#)
        let matches = pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m -> (Double, Double?, Bool) in
            let a = Double(s[Range(m.range(at: 1), in: s)!])!
            let b = m.range(at: 2).location == NSNotFound ? nil : Double(s[Range(m.range(at: 2), in: s)!])
            let start = Range(m.range, in: s)!.lowerBound
            let afterF = start > s.startIndex && s[s.index(before: start)] == "f"
            return (a, b, afterF)
        }
        // A number after "f" is an aperture; otherwise the first number group is the focal range.
        guard let focal = matches.first(where: { !$0.2 && $0.0 >= 4 }), (focal.1 ?? focal.0) >= focal.0 else { return nil }
        let aperture = matches.first(where: { $0.2 })?.0 ?? matches.first(where: { $0.0 < 4 && $0.0 >= 0.7 })?.0
        return (focal.0...(focal.1 ?? focal.0), aperture)
    }

    func camera(maker: String, model: String) -> LensfunCamera? {
        // LibRaw leaves the maker out of the model ("EOS 5D Mark II"); lensfun often repeats it ("Canon EOS 5D Mark II").
        let m = Self.normalized(model), k = Self.normalized(maker)
        let sameMaker = { (c: LensfunCamera) in k.hasPrefix(Self.normalized(c.maker).prefix(5)) || Self.normalized(c.maker).hasPrefix(k.prefix(5)) }
        return cameras.first { Self.normalized($0.model) == m && sameMaker($0) }
            ?? cameras.first { Self.normalized($0.model) == k + m || Self.normalized($0.model) == Self.normalized(maker.split(separator: " ").first.map(String.init) ?? "") + m }
            ?? cameras.first { Self.normalized($0.model) == m }
    }

    /// Lenses scored against the camera's lens string: the focal range must
    /// agree; then the smallest f-number, the maker and shared words count.
    func candidates(for lensName: String, maker: String, mount: String?) -> [(lens: LensfunLens, score: Int)] {
        guard let wanted = Self.parameters(lensName) else { return [] }
        let words = Self.tokens(lensName)
        // Every word of two letters or more in the camera's string must be in the lens's name ("FD" is not "EF").
        func letterWords(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 && $0 != "mm" })
        }
        let required = letterWords(lensName)
        var scored: [(LensfunLens, Int)] = []
        for lens in lenses {
            guard let model = lens.models.first, let p = Self.parameters(model), p.focal == wanted.focal,
                  required.isSubset(of: letterWords(lens.maker + " " + model)) else { continue }
            var score = 10
            if let a = wanted.aperture, let b = p.aperture, abs(a - b) < 0.05 { score += 5 }
            if let mount, lens.mounts.contains(mount) { score += 5 }
            if Self.normalized(maker).contains(Self.normalized(lens.maker)) || Self.normalized(lens.maker).contains(Self.normalized(maker)) { score += 3 }
            score += words.intersection(Self.tokens(model)).count
            scored.append((lens, score))
        }
        return scored.sorted { $0.1 > $1.1 }
    }
}

/// One lens's corrections at one focal length and aperture, as numbers.
struct LensCorrection {
    var distortionModel = "none"
    /// ptlens a, b, c (poly3: k1 as b = k1, a = c = 0 is not the same form; kept separately) or poly5 k1, k2.
    var a = 0.0, b = 0.0, c = 0.0, k1 = 0.0, k2 = 0.0
    var tcaModel = "none"
    var vr = 1.0, cr = 0.0, br = 0.0, vb = 1.0, cb = 0.0, bb = 0.0
    var vignettingModel = "none"
    var v1 = 0.0, v2 = 0.0, v3 = 0.0
    var lensCropFactor = 0.0, aspectRatio = 1.5, centerX = 0.0, centerY = 0.0
    var notes: [String] = []

    /// Linear interpolation of an entry's numbers between the two nearest
    /// `key` values (the manual says the library interpolates, not how: this
    /// is our choice).
    static func interpolated(_ entries: [[String: String]], key: String, at value: Double, fields: [String]) -> ([String: Double], String)? {
        let keyed = entries.compactMap { e -> (Double, [String: String])? in Double(e[key] ?? "").map { ($0, e) } }.sorted { $0.0 < $1.0 }
        guard !keyed.isEmpty else { return nil }
        func numbers(_ e: [String: String]) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: fields.map { ($0, Double(e[$0] ?? "") ?? Self.fieldDefault($0)) })
        }
        if let exact = keyed.first(where: { abs($0.0 - value) < 1e-6 }) { return (numbers(exact.1), exact.1["model"] ?? "") }
        let below = keyed.last { $0.0 < value }, above = keyed.first { $0.0 > value }
        guard let lo = below ?? above, let hi = above ?? below else { return nil }
        let t = hi.0 == lo.0 ? 0 : (value - lo.0) / (hi.0 - lo.0)
        let a = numbers(lo.1), b = numbers(hi.1)
        return (Dictionary(uniqueKeysWithValues: fields.map { ($0, a[$0]! * (1 - t) + b[$0]! * t) }), lo.1["model"] ?? "")
    }

    static func fieldDefault(_ name: String) -> Double { ["vr", "vb", "kr", "kb"].contains(name) ? 1 : 0 }

    init() {}

    init(lens: LensfunLens, focal: Double, aperture: Double) {
        lensCropFactor = lens.cropFactor
        aspectRatio = lens.aspectRatio
        centerX = lens.centerX; centerY = lens.centerY
        if let (d, model) = Self.interpolated(lens.distortion, key: "focal", at: focal, fields: ["a", "b", "c", "k1", "k2"]) {
            distortionModel = model
            a = d["a"]!; b = d["b"]!; c = d["c"]!; k1 = d["k1"]!; k2 = d["k2"]!
        }
        if let (t, model) = Self.interpolated(lens.tca, key: "focal", at: focal, fields: ["kr", "kb", "vr", "cr", "br", "vb", "cb", "bb"]) {
            tcaModel = model
            if model == "linear" {
                vr = t["kr"]!; vb = t["kb"]!
            } else {
                vr = t["vr"]!; cr = t["cr"]!; br = t["br"]!; vb = t["vb"]!; cb = t["cb"]!; bb = t["bb"]!
            }
        }
        // Vignetting: the entries at the nearest focal lengths, each read at the aperture (f-number,
        // linearly), at the largest distance given; then between the focal lengths, linearly.
        let byFocal = Dictionary(grouping: lens.vignetting) { Double($0["focal"] ?? "") ?? 0 }
        let focals = byFocal.keys.sorted()
        func atAperture(_ entries: [[String: String]]) -> [String: Double]? {
            let farthest = entries.compactMap { Double($0["distance"] ?? "") }.max()
            let chosen = entries.filter { Double($0["distance"] ?? "") == farthest }
            return Self.interpolated(chosen, key: "aperture", at: aperture, fields: ["k1", "k2", "k3"])?.0
        }
        if !focals.isEmpty {
            let lo = focals.last { $0 <= focal } ?? focals[0], hi = focals.first { $0 >= focal } ?? focals.last!
            if let vl = atAperture(byFocal[lo]!), let vh = atAperture(byFocal[hi]!) {
                let t = hi == lo ? 0 : (focal - lo) / (hi - lo)
                vignettingModel = byFocal[lo]!.first?["model"] ?? "pa"
                v1 = vl["k1"]! * (1 - t) + vh["k1"]! * t
                v2 = vl["k2"]! * (1 - t) + vh["k2"]! * t
                v3 = vl["k3"]! * (1 - t) + vh["k3"]! * t
            }
        }
    }

    /// Distorted radius for an undistorted one (both normalized), per the model.
    func distorted(_ r: Double) -> Double {
        switch distortionModel {
        case "ptlens": r * (a * r * r * r + b * r * r + c * r + 1 - a - b - c)
        case "poly3": r * (1 - k1 + k1 * r * r)
        case "poly5": r * (1 + k1 * r * r + k2 * r * r * r * r)
        default: r
        }
    }

    var description: String {
        String(format: "distortion %@ (a %.5f b %.5f c %.5f k1 %.5f k2 %.5f); TCA %@ (red v %.7f c %.7f b %.7f, blue v %.7f c %.7f b %.7f); "
               + "vignetting %@ (k1 %.4f k2 %.4f k3 %.4f); calibration crop factor %.3f, aspect %.3f, center %.3f, %.3f",
               distortionModel as NSString, a, b, c, k1, k2, tcaModel as NSString, vr, cr, br, vb, cb, bb,
               vignettingModel as NSString, v1, v2, v3, lensCropFactor, aspectRatio, centerX, centerY)
    }
}
