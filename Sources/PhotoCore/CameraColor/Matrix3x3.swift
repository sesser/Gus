import Foundation

/// A 3 × 3 matrix of doubles, by rows: the camera color math is done in
/// double precision and only its result is handed to Core Image.
public struct Matrix3x3: Sendable, Hashable {
    public var r0: SIMD3<Double>
    public var r1: SIMD3<Double>
    public var r2: SIMD3<Double>

    public init(rows r0: SIMD3<Double>, _ r1: SIMD3<Double>, _ r2: SIMD3<Double>) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }

    /// Nine values, row by row. Fewer or more is a programming error.
    public init(_ values: [Double]) {
        precondition(values.count == 9, "a 3 × 3 matrix has nine values")
        self.init(rows: SIMD3(values[0], values[1], values[2]), SIMD3(values[3], values[4], values[5]),
                  SIMD3(values[6], values[7], values[8]))
    }

    public static let identity = Matrix3x3.diagonal(SIMD3(1, 1, 1))

    public static func diagonal(_ d: SIMD3<Double>) -> Matrix3x3 {
        Matrix3x3(rows: SIMD3(d.x, 0, 0), SIMD3(0, d.y, 0), SIMD3(0, 0, d.z))
    }

    /// The matrix whose columns are the given vectors.
    public init(columns c0: SIMD3<Double>, _ c1: SIMD3<Double>, _ c2: SIMD3<Double>) {
        self.init(rows: SIMD3(c0.x, c1.x, c2.x), SIMD3(c0.y, c1.y, c2.y), SIMD3(c0.z, c1.z, c2.z))
    }

    public var rows: [SIMD3<Double>] { [r0, r1, r2] }

    public var values: [Double] { rows.flatMap { [$0.x, $0.y, $0.z] } }

    public var transpose: Matrix3x3 { Matrix3x3(columns: r0, r1, r2) }

    public var determinant: Double {
        r0.x * (r1.y * r2.z - r1.z * r2.y) - r0.y * (r1.x * r2.z - r1.z * r2.x) + r0.z * (r1.x * r2.y - r1.y * r2.x)
    }

    /// Nil for a matrix that has none (or holds values that are not finite).
    public var inverse: Matrix3x3? {
        let d = determinant
        guard d.isFinite, abs(d) > 1e-12 else { return nil }
        let a = r0, b = r1, c = r2
        return Matrix3x3(rows:
            SIMD3(b.y * c.z - b.z * c.y, a.z * c.y - a.y * c.z, a.y * b.z - a.z * b.y) / d,
            SIMD3(b.z * c.x - b.x * c.z, a.x * c.z - a.z * c.x, a.z * b.x - a.x * b.z) / d,
            SIMD3(b.x * c.y - b.y * c.x, a.y * c.x - a.x * c.y, a.x * b.y - a.y * b.x) / d)
    }

    public var isFinite: Bool { values.allSatisfy(\.isFinite) }

    public static func * (m: Matrix3x3, v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3((m.r0 * v).sum(), (m.r1 * v).sum(), (m.r2 * v).sum())
    }

    public static func * (a: Matrix3x3, b: Matrix3x3) -> Matrix3x3 {
        let t = b.transpose
        return Matrix3x3(rows: SIMD3((a.r0 * t.r0).sum(), (a.r0 * t.r1).sum(), (a.r0 * t.r2).sum()),
                       SIMD3((a.r1 * t.r0).sum(), (a.r1 * t.r1).sum(), (a.r1 * t.r2).sum()),
                       SIMD3((a.r2 * t.r0).sum(), (a.r2 * t.r1).sum(), (a.r2 * t.r2).sum()))
    }

    public static func * (s: Double, m: Matrix3x3) -> Matrix3x3 {
        Matrix3x3(rows: m.r0 * s, m.r1 * s, m.r2 * s)
    }

    public static func + (a: Matrix3x3, b: Matrix3x3) -> Matrix3x3 {
        Matrix3x3(rows: a.r0 + b.r0, a.r1 + b.r1, a.r2 + b.r2)
    }
}
