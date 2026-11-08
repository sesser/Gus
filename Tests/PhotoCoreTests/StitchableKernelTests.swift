import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The stitchable-kernel spike (`StitchableKernels`) against CPU references,
/// and the property that sets it apart from `RuntimeKernels`: Core Image fuses
/// it with neighboring filters. Needs a Metal device with dynamic libraries;
/// without one the suite is skipped with that reason.
@Suite("Stitchable kernels (spike)",
       .enabled(if: StitchableKernels.isSupported,
                "No Metal device with dynamic libraries: kernels from Metal source need one"))
struct StitchableKernelTests {
    /// Renders all of `image` as float RGBA in the working space, rows top
    /// down, and says how many passes Core Image ran.
    static func renderCountingPasses(_ image: CIImage) throws -> (pixels: [Float], passes: Int) {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let info = try pixels.withUnsafeMutableBytes { buffer in
            try ReferenceTests.engine.withContext { context in
                let destination = CIRenderDestination(bitmapData: buffer.baseAddress!, width: width, height: height,
                                                      bytesPerRow: width * 16, format: .RGBAf)
                destination.colorSpace = RenderEngine.workingColorSpace
                return try context.startTask(toRender: image, from: image.extent, to: destination, at: .zero)
                    .waitUntilCompleted()
            }
        }
        return (pixels, info.passCount)
    }

    @Test("The Metal source compiles into both kernels")
    func compiles() throws {
        #expect(try StitchableKernels.compile() == 2)
    }

    @Test("The gain kernel is input × 2^EV, as the exposure reference",
          arguments: [(TestScene.grayRamp, 1.5), (.hueRamp, -1.0)])
    func gainMatchesReference(scene: TestScene, ev: Double) throws {
        let input = scene.image()
        let output = try StitchableKernels.exposureGain(input.ciImage, ev: ev)
        let rendered = RuntimeKernelTests.render(output, bounds: output.extent)
        let expected = ExposureReference.apply(input, ev: ev)
        let failures = rendered.indices.filter { !ReferenceTests.withinHalfFloat(rendered[$0], expected.pixels[$0]) }
        #expect(failures.isEmpty, "\(failures.count) components beyond two half-float roundings")
    }

    /// These kernels run in the working format (`RGBAh`), so up to three
    /// half-float roundings reach an output pixel: the input as Core Image
    /// reads it, the horizontal pass's intermediate, and the output. Each is
    /// at most 2⁻¹¹ of the largest value in the neighborhood (the weights are
    /// positive and sum to 1), so 3 × 2⁻¹¹ of the image's largest value, plus
    /// the processor kernels' float32 allowance for the sums and weights.
    static func blurTolerance(_ image: LinearImage) -> Float {
        3 * 0x1p-11 * (image.pixels.map(abs).max() ?? 0) + RuntimeKernelTests.blurTolerance
    }

    @Test("The two-pass blur matches the reference over a whole odd-sized image", arguments: [0.8, 3.0, 6.0])
    func blurMatchesReference(sigma: Double) throws {
        let input = RuntimeKernelTests.oddScene
        let output = try StitchableKernels.gaussianBlur(input.ciImage, sigma: sigma)
        #expect(output.extent == input.ciImage.extent)
        let rendered = RuntimeKernelTests.render(output, bounds: output.extent)
        let expected = sigma == RuntimeKernelTests.tileSigma
            ? RuntimeKernelTests.tileReference : BlurReference.apply(input, sigma: sigma)
        let worst = zip(rendered, expected.pixels).map { abs($0 - $1) }.max() ?? 0
        #expect(worst <= Self.blurTolerance(input), "largest difference \(worst)")
    }

    /// Each rectangle asks Core Image for that region only, so the region of
    /// interest decides which input the kernel gets, as for tiles. The same
    /// rectangles as `RuntimeKernelTests.blurTilesMatchReference`.
    @Test("Odd rectangles of the blur, rendered alone, match the reference")
    func blurTilesMatchReference() throws {
        let input = RuntimeKernelTests.oddScene
        let output = try StitchableKernels.gaussianBlur(input.ciImage, sigma: RuntimeKernelTests.tileSigma)
        let expected = RuntimeKernelTests.tileReference
        let rects = [
            CGRect(x: 0, y: 0, width: 67, height: 49), CGRect(x: 67, y: 0, width: 129, height: 49),
            CGRect(x: 196, y: 0, width: 67, height: 197), CGRect(x: 0, y: 49, width: 31, height: 148),
            CGRect(x: 31, y: 49, width: 165, height: 97), CGRect(x: 31, y: 146, width: 165, height: 51),
            CGRect(x: 100, y: 75, width: 1, height: 1), CGRect(x: 7, y: 191, width: 255, height: 6),
        ]
        var worst: Float = 0
        for rect in rects {
            let rendered = RuntimeKernelTests.render(output, bounds: rect)
            let width = Int(rect.width)
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
        #expect(worst <= Self.blurTolerance(input), "largest difference \(worst)")
    }

    @Test("A sigma of zero leaves the image alone")
    func zeroSigmaIsIdentity() throws {
        let input = TestScene.patchChart.image().ciImage
        #expect(try StitchableKernels.gaussianBlur(input, sigma: 0) === input)
    }

    /// The point of the spike: three gains and a stock color matrix between
    /// them take as many passes as one gain, where each processor kernel adds
    /// a pass of its own.
    @Test("Core Image fuses a chain of stitchable gains with a stock filter; processor kernels it cannot")
    func pointwiseChainIsFused() throws {
        let input = TestScene.patchChart.image().ciImage
        func matrix(_ image: CIImage) -> CIImage {
            let filter = CIFilter.colorMatrix()
            filter.inputImage = image
            filter.rVector = CIVector(x: 0.9, y: 0.1, z: 0, w: 0)
            return filter.outputImage!
        }
        let single = try Self.renderCountingPasses(StitchableKernels.exposureGain(input, ev: 0.25)).passes
        let stitched = try Self.renderCountingPasses(StitchableKernels.exposureGain(
            matrix(StitchableKernels.exposureGain(StitchableKernels.exposureGain(input, ev: 0.25), ev: 0.25)),
            ev: 0.25)).passes
        let processor = try Self.renderCountingPasses(RuntimeKernels.exposureGain(
            matrix(RuntimeKernels.exposureGain(RuntimeKernels.exposureGain(input, ev: 0.25), ev: 0.25)),
            ev: 0.25)).passes
        #expect(stitched == single, "chain: \(stitched) passes; one gain: \(single)")
        #expect(processor > stitched, "processor chain: \(processor) passes; stitchable chain: \(stitched)")
    }
}
