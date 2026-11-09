import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// prd OQ5: the listed colors' values and starting Tolerances, and a pick's
/// starting Tolerance, follow from scene (a)'s fringes (the image the fringe
/// step sees, `TestScene.fringes`), not from trials.
///
/// - A listed color sits at the middle of its kind's hues in scene (a) (the
///   bluest and reddest purple, the yellowest and bluest green), at their
///   mean lightness and chroma.
/// - Its starting Tolerance is the smallest multiple of 5 whose full-gray
///   core (half the reach, `ColorFringes.hueReach`) covers every fringe of
///   its kind, so R1c holds with no slider move.
/// - A pick may land on any fringe of a kind, so a pick's starting Tolerance
///   is the smallest multiple of 5 whose core covers the widest spread of
///   hues within one kind.
/// - None of them may reach the sky (`FringeScene.sky`): "The blue sky stays blue".
@Suite("Fringe tolerance derivation")
struct FringeToleranceDerivationTests {
    struct Kind {
        var hues: [Double]
        var lightness: Double
        var chroma: Double
    }

    /// OkLab hues (degrees), mean lightness and chroma of a kind's fringe pixels in scene (a).
    static func kind(purple: Bool) -> Kind {
        let image = TestScene.fringes.image()
        var hues: [Double] = [], l = 0.0, c = 0.0
        for fringe in FringeScene.Fringe.allCases where fringe.isPurple == purple {
            for (x, y) in FringeScene.pixels(of: fringe) {
                let p = image[x, y]
                let lab = ColorRange.okLab(linearRec2020: SIMD3(Double(p.x), Double(p.y), Double(p.z)))
                hues.append(atan2(lab.z, lab.y) * 180 / .pi)
                l += lab.x
                c += (lab.y * lab.y + lab.z * lab.z).squareRoot()
            }
        }
        return Kind(hues: hues, lightness: l / Double(hues.count), chroma: c / Double(hues.count))
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// The smallest multiple of 5 whose core is at least `angle` degrees.
    static func tolerance(coreCovering angle: Double) -> Double {
        var tolerance = 0.0
        while ColorFringes.hueReach(tolerance: tolerance) / 2 < angle { tolerance += 5 }
        return tolerance
    }

    static func skyHue() -> Double {
        let lab = ColorRange.okLab(linearRec2020: SIMD3(TestScene.decode(FringeScene.sky.x),
                                                        TestScene.decode(FringeScene.sky.y),
                                                        TestScene.decode(FringeScene.sky.z)))
        return atan2(lab.z, lab.y) * 180 / .pi
    }

    @Test("The listed colors and their starting Tolerances follow from scene (a)",
          arguments: CommonFringeColor.allCases)
    func listedColors(listed: CommonFringeColor) {
        let kind = Self.kind(purple: listed == .purple)
        // The hues of one kind span far less than 180°: the middle of the two ends.
        let low = kind.hues.min()!, high = kind.hues.max()!
        let middle = (low + high) / 2 * .pi / 180
        let derived = SIMD3(kind.lightness, kind.chroma * cos(middle), kind.chroma * sin(middle))
        let rounded = SIMD3((derived.x * 1e4).rounded() / 1e4, (derived.y * 1e4).rounded() / 1e4,
                            (derived.z * 1e4).rounded() / 1e4)
        #expect(listed.color == rounded, "derived \(rounded)")
        let spread = kind.hues.map { Self.hueDistance($0, middle * 180 / .pi) }.max()!
        #expect(listed.startingTolerance == Self.tolerance(coreCovering: spread), "core must cover \(spread)°")
        let reach = ColorFringes.hueReach(tolerance: listed.startingTolerance)
        #expect(reach < Self.hueDistance(Self.skyHue(), middle * 180 / .pi))
        #expect(FringeHueName.band(of: listed.color) == (listed == .purple ? .purple : .green))
    }

    @Test("A pick's starting Tolerance follows from scene (a)")
    func pickTolerance() {
        var widest = 0.0
        for purple in [true, false] {
            let hues = Self.kind(purple: purple).hues
            widest = max(widest, hues.map { a in hues.map { Self.hueDistance(a, $0) }.max()! }.max()!)
        }
        #expect(ColorFringes.pickStartingTolerance == Self.tolerance(coreCovering: widest), "core must cover \(widest)°")
        // From any purple fringe, a pick's reach stops short of the sky.
        let reach = ColorFringes.hueReach(tolerance: ColorFringes.pickStartingTolerance)
        let nearest = Self.kind(purple: true).hues.map { Self.hueDistance($0, Self.skyHue()) }.min()!
        #expect(reach < nearest, "reach \(reach)°, sky \(nearest)° away")
    }
}
