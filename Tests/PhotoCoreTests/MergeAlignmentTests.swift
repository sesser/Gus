import CoreImage
import Foundation
import PhotoFixtures
import Testing
import simd
@testable import PhotoCore

extension MemoryHeavy {
    /// Alignment of an HDR merge's frames (issue #150, R9, AC7).
    @Suite("HDR merge alignment")
    struct MergeAlignmentTests {
        static let width = 1200
        static let height = 800

        static func bitmap(_ image: LinearImage) -> MergeBitmap {
            MergeBitmap(width: image.width, height: image.height, pixels: image.pixels)
        }

        /// Largest distance, over a grid of points, between where the measured
        /// homography puts a frame's pixel and where the fixture says it is.
        static func worstError(_ homography: MergeAlignment.Homography, frame: HDRBracket.Frame,
                               width: Int, height: Int) -> Double {
            var worst = 0.0
            for gy in 1..<8 {
                for gx in 1..<8 {
                    let top = SIMD2(Double(width) * Double(gx) / 8, Double(height) * Double(gy) / 8)
                    let truth = HDRBracket.positionInReference(top, frame: frame, width: width, height: height)
                    // Core Image coordinates: y up.
                    let measured = homography.apply(SIMD2(top.x, Double(height) - top.y))
                    worst = max(worst, simd_distance(SIMD2(measured.x, Double(height) - measured.y), truth))
                }
            }
            return worst
        }

        @Test("A hand-held bracket lines up: shifted and rotated frames land within half a pixel")
        func linesUpShiftedFrames() throws {
            let frames = [
                HDRBracket.Frame(ev: -2, shift: SIMD2(7.5, -4.25), rotationDegrees: 0.45),
                HDRBracket.Frame(ev: 0),
                HDRBracket.Frame(ev: 2, shift: SIMD2(-5.0, 6.5), rotationDegrees: -0.3),
            ]
            let images = frames.map { Self.bitmap(HDRBracket.image($0, width: Self.width, height: Self.height)) }
            let homographies = try MergeAlignment.align(images, reference: 1)
            for (index, frame) in frames.enumerated() {
                let error = Self.worstError(homographies[index], frame: frame, width: Self.width, height: Self.height)
                let h = homographies[index]
                for top in [SIMD2(0.0, 0.0), SIMD2(Double(Self.width), 0), SIMD2(600.0, 400.0)] {
                    let truth = HDRBracket.positionInReference(top, frame: frame, width: Self.width, height: Self.height)
                    let m = h.apply(SIMD2(top.x, Double(Self.height) - top.y))
                    let mi = h.inverse.apply(SIMD2(top.x, Double(Self.height) - top.y))
                    print("pt \(top) truth \(truth) H \(SIMD2(m.x, Double(Self.height) - m.y)) Hinv \(SIMD2(mi.x, Double(Self.height) - mi.y))")
                }
                print("frame \(index): worst error \(error) px, rotation \(homographies[index].rotationDegrees)°")
                #expect(error < 0.5, "frame \(index)")
            }
        }
    }
}
