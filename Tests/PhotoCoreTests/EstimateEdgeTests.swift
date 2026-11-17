import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #73 (docs/features/dehaze-above-white/status.md): the whole-frame
/// estimates of dehaze and local tone at the frame's edge.
///
/// Both estimates reduce the image to a 256-pixel copy with a Lanczos filter,
/// which reads past the frame's edge. Outside the frame the image is
/// transparent, so before the fix the reduced copy's outermost pixels came
/// out partly transparent (alpha 0.88 here). Both are now measured on the
/// image with its edge pixels repeated outward. Scenes are larger than 256
/// pixels so that the reduction happens: the goldens (256 × 192) never
/// reduce and so never saw this.
@Suite("Whole-frame estimates at the frame's edge")
struct EstimateEdgeTests {
    /// Renders `image` once to a half-float image in the working space, as
    /// the live session's stage cache does (`LiveRenderSession.materialize`).
    static func materialize(_ image: CIImage) throws -> CIImage {
        let extent = image.extent.integral
        let rendered = try #require(ReferenceTests.engine.withContext {
            $0.createCGImage(image, from: extent, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
        })
        return CIImage(cgImage: rendered).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    static func pixels(_ image: CIImage, in extent: CGRect) -> [Float] {
        ReferenceTests.renderLinear(image.cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))).pixels
    }

    /// The largest difference of the color components (alpha left out).
    static func largestDifference(_ a: [Float], _ b: [Float]) -> Float {
        var worst: Float = 0
        for i in a.indices where i % 4 != 3 { worst = max(worst, abs(a[i] - b[i])) }
        return worst
    }

    /// The image entering an estimate: the synthetic hazy landscape (values up
    /// to 0.74) through `exposure` and `shadows`, as `upstream` builds it.
    static func entering(exposure: Double, shadows: Double) throws -> CIImage {
        let scene = try materialize(TestScene.hazyLandscape.image(width: 640, height: 480).ciImage)
        var values = Adjustments()
        values.exposure.ev = exposure
        values.tone.shadows = shadows
        let renderer = AdjustmentRenderer()
        return renderer.upstream(values, to: scene, crop: AdjustmentRenderer.crop(values, context: RenderContext()),
                                 context: RenderContext())
    }

    /// The same image, evaluated as one graph (a whole render) or rendered to
    /// a half-float image first (the live session's cached stages), must give
    /// the same haze estimate. The two inputs differ by one half-float
    /// rounding (2⁻¹¹ relative); the haze is a ratio of minima and blurs of
    /// the input, 0 … 1, so 2⁻⁹ is several roundings' worth. Shifting the
    /// whole input by 2⁻⁹ relative moved it by 0.0013 to 0.0025 at most.
    ///
    /// Failed before the fix when the input had been through local tone
    /// (Shadows here), with or without values above white: 0.094. The reduced
    /// copy's partly transparent edge was made opaque by the clamp's alpha
    /// floor, which divided its colors by alpha when Core Image computed that
    /// alpha (the materialized image) and left them as they were when it
    /// took the image for opaque (one graph after local tone's
    /// `settingAlphaOne`).
    @Test("The haze estimate does not depend on how its input is evaluated",
          arguments: [(0.0, 0.0), (2.0, 0.0), (0.0, 40.0), (2.0, 40.0)])
    func hazeEstimateIsEvaluationIndependent(exposure: Double, shadows: Double) throws {
        let whole = try Self.entering(exposure: exposure, shadows: shadows)
        let cached = try Self.materialize(whole)
        let extent = whole.extent
        let a = try #require(AdjustmentRenderer.hazeEstimate(whole, extent: extent))
        let b = try #require(AdjustmentRenderer.hazeEstimate(cached, extent: extent))
        let small = a.haze.extent
        let difference = Self.largestDifference(Self.pixels(a.haze, in: small), Self.pixels(b.haze, in: small))
        let airlight = CGRect(x: 0, y: 0, width: 1, height: 1)
        let airlightDifference = Self.largestDifference(Self.pixels(a.airlight, in: airlight),
                                                        Self.pixels(b.airlight, in: airlight))
        #expect(difference <= 0x1p-9, "exposure \(exposure), shadows \(shadows): the reduced haze differs by \(difference)")
        #expect(airlightDifference <= 0x1p-9 * Float(pow(2, exposure)), "the airlight differs by \(airlightDifference)")
    }

    /// Values above white alone do not disturb the haze estimate: it scales
    /// with exposure (the airlight by 2^EV, the haze, a ratio, not at all)
    /// from a quarter of the scene's level to four times it (values to 2.9).
    /// Passed before the fix too: above-white input is not what #73 was about.
    @Test("The haze estimate scales with exposure, above white included")
    func hazeEstimateScalesWithExposure() throws {
        var reference: (haze: [Float], airlight: Float)?
        for ev in [-2.0, 0, 1, 1.5, 2] {
            let image = try Self.entering(exposure: ev, shadows: 0)
            let extent = image.extent
            let estimate = try #require(AdjustmentRenderer.hazeEstimate(image, extent: extent))
            let haze = Self.pixels(estimate.haze, in: estimate.haze.extent)
            let airlight = Self.pixels(estimate.airlight, in: CGRect(x: 0, y: 0, width: 1, height: 1))[0] / Float(pow(2, ev))
            guard let reference else { reference = (haze, airlight); continue }
            // Each level rounds the input once more in half float (2⁻¹¹ relative).
            #expect(abs(airlight - reference.airlight) <= reference.airlight * 0x1p-9, "EV \(ev): airlight / 2^EV \(airlight)")
            #expect(Self.largestDifference(haze, reference.haze) <= 0x1p-8, "EV \(ev)")
        }
    }

    /// Shadows lifts; it never darkens. At Shadows 1 the gain is between 1
    /// and 2^0.03 everywhere, so each output pixel is at least its input,
    /// less two half-float roundings.
    ///
    /// Failed before the fix: the smoothed luminance was partly transparent
    /// over the frame's outer pixels (alpha 0.908 at the corner, 0.953 in the
    /// middle of the top edge) and is multiplied in premultiplied, so turning
    /// on any Shadows or negative Highlights darkened the border by up to 9%
    /// (0.9086 of its input at the corner). 1200 pixels: on larger frames the
    /// upsample leaves the estimate's alpha at 0.9996 everywhere, the edge
    /// included (`AdjustmentRenderer.luminanceMargin`), which this bound
    /// would not allow.
    @Test("Shadows never darkens a pixel, at the frame's edge included")
    func shadowsNeverDarkensTheEdge() throws {
        let scene = try Self.materialize(TestScene.hazyLandscape.image(width: 1200, height: 900).ciImage)
        let extent = scene.extent
        let input = Self.pixels(scene, in: extent)
        let output = Self.pixels(AdjustmentRenderer.localTone(scene, LocalToneCurve(shadows: 0.01, recovery: 0),
                                                              extent: extent), in: extent)
        var worst: (ratio: Float, x: Int, y: Int) = (1, 0, 0)
        for i in input.indices where i % 4 != 3 && input[i] > 0.01 {
            let ratio = output[i] / input[i]
            if ratio < worst.ratio { worst = (ratio, i / 4 % 1200, i / 4 / 1200) }
        }
        #expect(worst.ratio >= 1 - 0x1p-10, "darkened to \(worst.ratio) of its input at (\(worst.x), \(worst.y))")
    }

    /// The masks' estimate and global local tone's are one function, with
    /// the same margin, so a mask's Shadows and the global slider measure the
    /// same image the same way.
    @Test("The masks' luminance estimate is global local tone's")
    func maskEstimateIsTheGlobalOne() throws {
        let scene = try Self.materialize(TestScene.hazyLandscape.image(width: 1200, height: 900).ciImage)
        let extent = scene.extent
        let mask = GoldenCase.mask([.luminanceRange(LuminanceRange(lower: 0, upper: 1))]) { $0.shadows = 40 }
        let renderer = AdjustmentRenderer()
        let estimate = try #require(renderer.localEstimates([mask], over: scene).luminance)
        let global = try #require(AdjustmentRenderer.smoothedLuminance(scene, extent: extent))
        #expect(Self.largestDifference(Self.pixels(estimate, in: extent), Self.pixels(global, in: extent)) == 0)
    }

    /// A plain bump: every preview cached under version 10 may hold the old
    /// edges, and a key cannot say which stacks use the estimates.
    @Test("Previews cached before the fix are not used")
    func pipelineVersionBumped() {
        #expect(PreviewCacheKey.currentPipelineVersion >= 11)
    }
}
