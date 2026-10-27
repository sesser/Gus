import Foundation
import simd

/// A few simple looks that ship with the app, generated as `.cube` files (sRGB
/// input) so they go through the same store and renderer as imported tables.
/// Their content hashes name them, so changing a look here gives it a new
/// identifier and edits made with the old one keep their file.
public enum BuiltInLookTables {
    public struct Table: Sendable {
        /// Stable key for the localized name.
        public let key: String
        public let identifier: String
        public let data: Data
    }

    static let dimension = 25

    /// The built-in tables, in menu order.
    public static let all: [Table] = looks.map { key, transform in
        let data = Data(cubeText(title: key, transform).utf8)
        return Table(key: key, identifier: Digest.sha256Hex(data), data: data)
    }

    public static func table(identifier: String) -> Table? {
        all.first { $0.identifier == identifier }
    }

    /// The built-in collection, with names from `name(key)`.
    public static func collection(named name: String, entryName: (String) -> String) -> LookTableCollection {
        LookTableCollection(rowID: nil, uuid: "builtIn", name: name, entries: all.map {
            LookTableEntry(identifier: $0.identifier, name: entryName($0.key), builtInKey: $0.key)
        })
    }

    // MARK: Looks

    typealias Transform = @Sendable (SIMD3<Double>) -> SIMD3<Double>

    static let looks: [(String, Transform)] = [
        ("warm", { rgb in
            SIMD3(rgb.x * 1.05 + 0.015, rgb.y * 1.01 + 0.005, rgb.z * 0.9)
        }),
        ("cool", { rgb in
            SIMD3(rgb.x * 0.92, rgb.y * 0.99 + 0.005, rgb.z * 1.06 + 0.015)
        }),
        ("fade", { rgb in
            let faded = mixWithLuma(rgb, 0.2)
            return SIMD3(repeating: 0.08) + faded * 0.86
        }),
        ("mono", { rgb in
            SIMD3(repeating: sCurve(luma(rgb), 0.25))
        }),
        ("sepia", { rgb in
            let l = sCurve(luma(rgb), 0.15)
            return SIMD3(l * 1.06 + 0.03, l * 0.96 + 0.015, l * 0.78)
        }),
        ("tealOrange", { rgb in
            let l = luma(rgb)
            let shadows = 1 - smoothstep(0.1, 0.55, l)
            let highlights = smoothstep(0.45, 0.9, l)
            let teal = SIMD3(-0.06, 0.015, 0.05)
            let orange = SIMD3(0.06, 0.01, -0.06)
            return mixWithLuma(rgb, -0.1) + teal * shadows + orange * highlights
        }),
        ("crossProcess", { rgb in
            SIMD3(sCurve(rgb.x, 0.45), sCurve(rgb.y, 0.2) * 0.97 + 0.02, 0.12 + rgb.z * 0.72)
        }),
        ("bleach", { rgb in
            let mixed = mixWithLuma(rgb, 0.55)
            return SIMD3(sCurve(mixed.x, 0.35), sCurve(mixed.y, 0.35), sCurve(mixed.z, 0.35))
        }),
    ]

    static func luma(_ rgb: SIMD3<Double>) -> Double {
        0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }

    /// Moves toward grey by `amount` (negative adds saturation).
    static func mixWithLuma(_ rgb: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        rgb + (SIMD3(repeating: luma(rgb)) - rgb) * amount
    }

    /// Contrast around mid grey that keeps black and white in place.
    static func sCurve(_ x: Double, _ strength: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        let smooth = clamped * clamped * (3 - 2 * clamped)
        return clamped + (smooth - clamped) * strength * 2
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The `.cube` text for a transform, values clamped to 0 … 1.
    static func cubeText(title: String, _ transform: Transform) -> String {
        var text = "TITLE \"\(title)\"\nLUT_3D_SIZE \(dimension)\n"
        text.reserveCapacity(dimension * dimension * dimension * 28)
        let step = 1 / Double(dimension - 1)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let out = transform(SIMD3(Double(r) * step, Double(g) * step, Double(b) * step))
                    text += fixed(out.x) + " " + fixed(out.y) + " " + fixed(out.z) + "\n"
                }
            }
        }
        return text
    }

    /// Six decimals, without `String(format:)` (thousands of calls).
    static func fixed(_ value: Double) -> String {
        let micro = Int((min(max(value, 0), 1) * 1_000_000).rounded())
        let fraction = String(micro % 1_000_000)
        return "\(micro / 1_000_000)." + String(repeating: "0", count: 6 - fraction.count) + fraction
    }
}
