import CoreImage
import Foundation
import Synchronization
import simd

/// A 3-D color table ready for `CIColorCubeWithColorSpace`: RGBA floats, red
/// varying fastest, over 0 … 1 in each channel.
public struct ColorCube: Sendable, Hashable {
    public let dimension: Int
    public let data: Data

    public init(dimension: Int, data: Data) {
        self.dimension = dimension
        self.data = data
    }

    /// Builds a cube by evaluating `transform` at every lattice point.
    static func evaluating(dimension: Int, _ transform: (SIMD3<Double>) -> SIMD3<Double>) -> ColorCube {
        var values = [Float](repeating: 1, count: dimension * dimension * dimension * 4)
        let step = 1 / Double(dimension - 1)
        var index = 0
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let out = transform(SIMD3(Double(r) * step, Double(g) * step, Double(b) * step))
                    values[index] = Float(out.x)
                    values[index + 1] = Float(out.y)
                    values[index + 2] = Float(out.z)
                    index += 4
                }
            }
        }
        return ColorCube(dimension: dimension, data: values.withUnsafeBytes { Data($0) })
    }
}

/// Color grading baked into a cube, in the same perceptual encoding as the
/// tone table (Rec. 2020 primaries, sRGB transfer curve).
enum ColorGradeCube {
    static let dimension = 33

    static func make(_ grade: ColorGrade) -> ColorCube {
        let balance = grade.balance / 100
        let width = 0.12 + 0.3 * (grade.blending / 100)
        // Positive balance moves both splits down: more of the image counts as highlights.
        let shadowSplit = 0.3 - 0.15 * balance
        let highlightSplit = 0.7 - 0.15 * balance
        let offsets = ColorGrade.Range.allCases.map { offset(for: grade[$0]) }
        return ColorCube.evaluating(dimension: dimension) { rgb in
            let luma = 0.2627 * rgb.x + 0.6780 * rgb.y + 0.0593 * rgb.z
            let shadows = 1 - ToneTable.smoothstep(shadowSplit - width, shadowSplit + width, luma)
            let highlights = ToneTable.smoothstep(highlightSplit - width, highlightSplit + width, luma)
            let midtones = max(0, 1 - shadows - highlights)
            let out = rgb + shadows * offsets[0] + midtones * offsets[1] + highlights * offsets[2]
            return SIMD3(max(out.x, 0), max(out.y, 0), max(out.z, 0))
        }
    }

    /// The color a wheel adds: a zero-sum tint of its hue plus a luminance shift.
    static func offset(for wheel: GradeWheel) -> SIMD3<Double> {
        let hue = SIMD3(huePrimary(wheel.hue))
        let tint = hue - SIMD3(repeating: (hue.x + hue.y + hue.z) / 3)
        return tint * (wheel.amount / 100) * 0.25 + SIMD3(repeating: wheel.luminance / 100 * 0.15)
    }

    /// Fully saturated RGB for a hue in degrees.
    static func huePrimary(_ degrees: Double) -> (Double, Double, Double) {
        let h = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        switch Int(h) {
        case 0: return (1, x, 0)
        case 1: return (x, 1, 0)
        case 2: return (0, 1, x)
        case 3: return (0, x, 1)
        case 4: return (x, 0, 1)
        default: return (1, 0, x)
        }
    }
}

extension SIMD3 where Scalar == Double {
    init(_ tuple: (Double, Double, Double)) {
        self.init(tuple.0, tuple.1, tuple.2)
    }
}

/// A parsed `.cube` file (1-D or 3-D).
public struct CubeLUT: Sendable, Equatable {
    public enum Failure: Error, Equatable {
        case missingSize
        case unsupportedSize(Int)
        case wrongEntryCount(expected: Int, found: Int)
        case malformedLine(Int)
        case invalidDomain
    }

    public static let maximumSize3D = 65
    public static let maximumSize1D = 65536

    public var title: String?
    public var size: Int
    public var isThreeDimensional: Bool
    /// RGB triplets in file order (red varying fastest for 3-D tables).
    public var entries: [SIMD3<Float>]
    public var domainMin = SIMD3<Float>(0, 0, 0)
    public var domainMax = SIMD3<Float>(1, 1, 1)

    public init(contentsOf url: URL) throws {
        try self.init(parsing: String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    public init(parsing text: String) throws {
        var title: String?
        var size3D: Int?
        var size1D: Int?
        var entries: [SIMD3<Float>] = []
        var lineNumber = 0
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            let keyword = fields[0].uppercased()
            switch keyword {
            case "TITLE":
                title = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard fields.count == 2, let value = Int(fields[1]) else { throw Failure.malformedLine(lineNumber) }
                size3D = value
            case "LUT_1D_SIZE":
                guard fields.count == 2, let value = Int(fields[1]) else { throw Failure.malformedLine(lineNumber) }
                size1D = value
            case "DOMAIN_MIN", "DOMAIN_MAX":
                guard fields.count == 4, let vector = Self.vector(fields[1...]) else {
                    throw Failure.malformedLine(lineNumber)
                }
                if keyword == "DOMAIN_MIN" { domainMin = vector } else { domainMax = vector }
            case "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE":
                guard fields.count == 3, let low = Float(fields[1]), let high = Float(fields[2]) else {
                    throw Failure.malformedLine(lineNumber)
                }
                domainMin = SIMD3(repeating: low)
                domainMax = SIMD3(repeating: high)
            default:
                if let first = fields.first?.first, first.isNumber || first == "-" || first == "." {
                    guard fields.count == 3, let vector = Self.vector(fields[...]) else {
                        throw Failure.malformedLine(lineNumber)
                    }
                    entries.append(vector)
                }
                // Other keywords (vendor extensions) are ignored.
            }
        }
        if let size3D {
            guard (2...Self.maximumSize3D).contains(size3D) else { throw Failure.unsupportedSize(size3D) }
            size = size3D
            isThreeDimensional = true
        } else if let size1D {
            guard (2...Self.maximumSize1D).contains(size1D) else { throw Failure.unsupportedSize(size1D) }
            size = size1D
            isThreeDimensional = false
        } else {
            throw Failure.missingSize
        }
        let expected = isThreeDimensional ? size * size * size : size
        guard entries.count == expected else { throw Failure.wrongEntryCount(expected: expected, found: entries.count) }
        guard all(domainMax .> domainMin) else { throw Failure.invalidDomain }
        self.title = title
        self.entries = entries
    }

    private static func vector(_ fields: ArraySlice<Substring>) -> SIMD3<Float>? {
        let values = fields.compactMap { Float($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    /// The table as a cube over 0 … 1 for Core Image. 1-D tables and tables
    /// with another domain are resampled.
    public func colorCube() -> ColorCube {
        if isThreeDimensional, domainMin == SIMD3(0, 0, 0), domainMax == SIMD3(1, 1, 1) {
            var values = [Float]()
            values.reserveCapacity(entries.count * 4)
            for entry in entries {
                values += [entry.x, entry.y, entry.z, 1]
            }
            return ColorCube(dimension: size, data: values.withUnsafeBytes { Data($0) })
        }
        let dimension = isThreeDimensional ? size : 33
        return ColorCube.evaluating(dimension: dimension) { rgb in
            let position = (SIMD3<Float>(Float(rgb.x), Float(rgb.y), Float(rgb.z)) - domainMin) / (domainMax - domainMin)
            let clamped = simd_clamp(position, SIMD3(repeating: 0), SIMD3(repeating: 1))
            let out = isThreeDimensional ? sample3D(clamped) : sample1D(clamped)
            return SIMD3(Double(out.x), Double(out.y), Double(out.z))
        }
    }

    /// Trilinear lookup at a position in 0 … 1.
    func sample3D(_ position: SIMD3<Float>) -> SIMD3<Float> {
        let scaled = position * Float(size - 1)
        let low = SIMD3<Int>(Int(scaled.x.rounded(.down)), Int(scaled.y.rounded(.down)), Int(scaled.z.rounded(.down)))
        let lo = simd_clamp(low, SIMD3(repeating: 0), SIMD3(repeating: size - 2))
        let t = scaled - SIMD3<Float>(Float(lo.x), Float(lo.y), Float(lo.z))
        func at(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> { entries[r + g * size + b * size * size] }
        let c00 = mix(at(lo.x, lo.y, lo.z), at(lo.x + 1, lo.y, lo.z), t.x)
        let c10 = mix(at(lo.x, lo.y + 1, lo.z), at(lo.x + 1, lo.y + 1, lo.z), t.x)
        let c01 = mix(at(lo.x, lo.y, lo.z + 1), at(lo.x + 1, lo.y, lo.z + 1), t.x)
        let c11 = mix(at(lo.x, lo.y + 1, lo.z + 1), at(lo.x + 1, lo.y + 1, lo.z + 1), t.x)
        return mix(mix(c00, c10, t.y), mix(c01, c11, t.y), t.z)
    }

    /// Per-channel linear lookup at a position in 0 … 1.
    func sample1D(_ position: SIMD3<Float>) -> SIMD3<Float> {
        func channel(_ value: Float, _ component: KeyPath<SIMD3<Float>, Float>) -> Float {
            let scaled = value * Float(size - 1)
            let low = min(max(Int(scaled.rounded(.down)), 0), size - 2)
            let t = scaled - Float(low)
            return entries[low][keyPath: component] * (1 - t) + entries[low + 1][keyPath: component] * t
        }
        return SIMD3(channel(position.x, \.x), channel(position.y, \.y), channel(position.z, \.z))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}

/// Look-up tables copied into the library, named by the SHA-256 of their
/// contents, so an edit keeps rendering when the folder it came from moves.
public final class LookTableStore: Sendable {
    public static let folderName = "LUTs"
    public static let fileExtension = "cube"

    public let directory: URL
    private let cubes = Mutex<[String: ColorCube]>([:])

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store inside a library's catalog folder.
    public convenience init(locations: LibraryLocations) {
        self.init(directory: locations.catalogDirectory.appending(path: Self.folderName, directoryHint: .isDirectory))
    }

    /// Validates `url` as a `.cube` file and copies it into the store (once per
    /// content). Returns the operation that applies it at full intensity, named
    /// from the file's header or its file name.
    public func importFile(at url: URL) throws -> LookTable {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let lut = try CubeLUT(parsing: text)
        let identifier = try install(data)
        cubes.withLock { $0[identifier] = lut.colorCube() }
        let name = LookTableNaming.descriptiveName(in: text) ?? LookTableNaming.cleanedFileName(url.lastPathComponent)
        return LookTable(identifier: identifier, name: name)
    }

    /// Writes a table's file unless the store has it; returns its identifier.
    @discardableResult
    public func install(_ data: Data) throws -> String {
        let identifier = Digest.sha256Hex(data)
        let destination = fileURL(for: identifier)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return identifier
    }

    /// Writes the built-in tables' files, so edits that use them keep their
    /// file even after the looks change in a later build.
    public func installBuiltIns() {
        for table in BuiltInLookTables.all {
            _ = try? install(table.data)
        }
    }

    public func contains(_ identifier: String) -> Bool {
        guard Self.isValid(identifier) else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: identifier).path)
    }

    /// The prepared cube for an imported table, or nil when it is missing or unreadable.
    public func cube(for identifier: String) -> ColorCube? {
        guard Self.isValid(identifier) else { return nil }
        if let cube = cubes.withLock({ $0[identifier] }) { return cube }
        if !contains(identifier), let builtIn = BuiltInLookTables.table(identifier: identifier) {
            _ = try? install(builtIn.data)
        }
        guard let lut = try? CubeLUT(contentsOf: fileURL(for: identifier)) else { return nil }
        let cube = lut.colorCube()
        cubes.withLock { $0[identifier] = cube }
        return cube
    }

    func fileURL(for identifier: String) -> URL {
        directory.appending(path: "\(identifier).\(Self.fileExtension)", directoryHint: .notDirectory)
    }

    /// Identifiers are lowercase hex, which also keeps paths inside the store.
    static func isValid(_ identifier: String) -> Bool {
        identifier.count == 64 && PreviewCacheKey.isHex(identifier)
    }
}

/// Finding `.cube` files in a folder and previewing tables on a photo.
public enum LookTableBrowsing {
    /// At most this many files are listed.
    public static let fileLimit = 300

    /// `.cube` files in `folder` and its subfolders, sorted by name.
    public static func files(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == LookTableStore.fileExtension {
            found.append(url)
            if found.count >= fileLimit { break }
        }
        return found.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// `base` reduced to at most `longEdge` pixels, to preview many tables on.
    public static func reduced(_ base: CGImage, longEdge: Int, engine: RenderEngine) -> CGImage? {
        engine.makeCGImage(CIImage(cgImage: base).scaledToFit(longEdge: longEdge), colorSpace: base.colorSpace)
    }

    /// `base` (a rendered photo) with the table applied, at most `longEdge` pixels.
    public static func preview(of base: CGImage, with table: ColorCube, colorSpace: LookTable.ColorSpace = .sRGB,
                               engine: RenderEngine, longEdge: Int = 192) -> CGImage? {
        let image = CIImage(cgImage: base).scaledToFit(longEdge: longEdge)
        return engine.makeCGImage(AdjustmentRenderer.lookTable(image, table, intensity: 1, colorSpace: colorSpace),
                                  colorSpace: base.colorSpace)
    }
}
