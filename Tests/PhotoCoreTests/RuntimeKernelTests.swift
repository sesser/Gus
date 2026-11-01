import CoreImage
import Foundation
import Metal
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The custom-kernel spike (`RuntimeKernels`) against CPU references. Needs a
/// Metal device; without one the suite is skipped with that reason.
@Suite("Runtime kernels (spike)",
       .enabled(if: RuntimeKernels.isSupported, "No Metal device: runtime-compiled kernels need one"))
struct RuntimeKernelTests {
    /// Renders the rectangle `bounds` (Core Image coordinates, y up) of
    /// `image` as float RGBA in the working space, rows top down.
    static func render(_ image: CIImage, bounds: CGRect) -> [Float] {
        let width = Int(bounds.width), height = Int(bounds.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            ReferenceTests.engine.withContext {
                $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: bounds,
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return pixels
    }

    @Test("The gain kernel is input × 2^EV, as the exposure reference",
          arguments: [(TestScene.grayRamp, 1.5), (.hueRamp, -1.0)])
    func gainMatchesReference(scene: TestScene, ev: Double) throws {
        let input = scene.image()
        let output = try RuntimeKernels.exposureGain(input.ciImage, ev: ev)
        let rendered = Self.render(output, bounds: output.extent)
        let expected = ExposureReference.apply(input, ev: ev)
        let failures = rendered.indices.filter { !ReferenceTests.withinHalfFloat(rendered[$0], expected.pixels[$0]) }
        #expect(failures.isEmpty, "\(failures.count) components beyond two half-float roundings")
    }

    /// The kernels declare 32-bit float input and output (`RGBAf`), so the
    /// input reaches them unrounded and only the float sums differ from the
    /// Double reference: at most (2 × 18 + 1) taps × 2 passes × 2⁻²⁴ ≈ 4.4e-6
    /// for values ≤ 1 and σ ≤ 6. Measured: 2.4e-7.
    static let blurTolerance: Float = 1e-5

    /// 263 × 197: a multiple of no tile size.
    static let oddScene = TestScene.edgeTarget.image(width: 263, height: 197)
    static let tileSigma = 3.0
    static let tileReference = BlurReference.apply(oddScene, sigma: tileSigma)

    @Test("The two-pass blur matches the reference over a whole odd-sized image", arguments: [0.8, 3.0, 6.0])
    func blurMatchesReference(sigma: Double) throws {
        let input = Self.oddScene
        let output = try RuntimeKernels.gaussianBlur(input.ciImage, sigma: sigma)
        #expect(output.extent == input.ciImage.extent)
        let rendered = Self.render(output, bounds: output.extent)
        let expected = sigma == Self.tileSigma ? Self.tileReference : BlurReference.apply(input, sigma: sigma)
        let worst = zip(rendered, expected.pixels).map { abs($0 - $1) }.max() ?? 0
        #expect(worst <= Self.blurTolerance, "largest difference \(worst)")
        // The blur did something: the edges moved by far more than the tolerance.
        let change = zip(input.pixels, expected.pixels).map { abs($0 - $1) }.max() ?? 0
        #expect(change > 0.1)
    }

    /// Each rectangle asks Core Image for that region only, so the kernel's
    /// region of interest decides which input it gets, as for tiles. Odd
    /// sizes and offsets, rectangles touching every edge, and one inside.
    @Test("Odd rectangles of the blur, rendered alone, match the reference")
    func blurTilesMatchReference() throws {
        let input = Self.oddScene
        let output = try RuntimeKernels.gaussianBlur(input.ciImage, sigma: Self.tileSigma)
        let expected = Self.tileReference
        let rects = [
            CGRect(x: 0, y: 0, width: 67, height: 49), CGRect(x: 67, y: 0, width: 129, height: 49),
            CGRect(x: 196, y: 0, width: 67, height: 197), CGRect(x: 0, y: 49, width: 31, height: 148),
            CGRect(x: 31, y: 49, width: 165, height: 97), CGRect(x: 31, y: 146, width: 165, height: 51),
            CGRect(x: 100, y: 75, width: 1, height: 1), CGRect(x: 7, y: 191, width: 255, height: 6),
        ]
        var worst: Float = 0
        for rect in rects {
            let rendered = Self.render(output, bounds: rect)
            let width = Int(rect.width)
            // Row 0 of the bitmap is the rectangle's top: image row height − maxY, counted from the top.
            let top = input.height - Int(rect.maxY)
            for row in 0..<Int(rect.height) {
                for column in 0..<width {
                    for c in 0..<4 {
                        let actual = rendered[(row * width + column) * 4 + c]
                        let reference = expected.pixels[((top + row) * input.width + Int(rect.minX) + column) * 4 + c]
                        worst = max(worst, abs(actual - reference))
                    }
                }
            }
        }
        #expect(worst <= Self.blurTolerance, "largest difference \(worst)")
    }

    @Test("A sigma of zero leaves the image alone")
    func zeroSigmaIsIdentity() throws {
        let input = TestScene.patchChart.image()
        let output = try RuntimeKernels.gaussianBlur(input.ciImage, sigma: 0)
        #expect(Self.render(output, bounds: output.extent) == input.pixels)
        #expect(RuntimeKernels.gaussianWeights(sigma: 0) == [1])
        let weights = RuntimeKernels.gaussianWeights(sigma: 2)
        #expect(weights.count == 13 && abs(weights.reduce(0, +) - 1) < 1e-6)
    }
}
