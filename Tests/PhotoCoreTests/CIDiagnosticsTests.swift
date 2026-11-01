import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Temporary: prints, stage by stage, where the CI runners' renders depart
/// from this Mac's (PR #17's first run: `mask-combined-hazyLandscape` at the
/// border columns on macOS 15; cached against whole renders on both runners).
/// Prints only; never fails. Runs where `CI` is set (GitHub Actions) or with
/// `CI_DIAGNOSTICS=1`.
@Suite("CI diagnostics (temporary)",
       .enabled(if: ProcessInfo.processInfo.environment["CI"] != nil
                    || ProcessInfo.processInfo.environment["CI_DIAGNOSTICS"] == "1"))
struct CIDiagnosticsTests {
    static func linear(_ image: CIImage) -> LinearImage { ReferenceTests.renderLinear(image) }

    /// The image rendered out to half float and read back, as the live session's cache does.
    static func materialized(_ image: CIImage, _ format: CIFormat = .RGBAh) -> CIImage {
        let extent = image.extent.integral
        let rendered = ReferenceTests.engine.withContext {
            $0.createCGImage(image, from: extent, format: format, colorSpace: RenderEngine.workingColorSpace)
        }!
        return CIImage(cgImage: rendered).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    static func describe(_ name: String, _ a: CIImage, _ b: CIImage) {
        let x = linear(a), y = linear(b)
        var worst: Float = 0, at = 0
        for i in x.pixels.indices where i % 4 != 3 {
            let d = abs(x.pixels[i] - y.pixels[i])
            if d > worst { (worst, at) = (d, i) }
        }
        let p = at / 4
        print("diagnostics \(name): max difference \(worst) at (\(p % x.width), \(p / x.width)) "
              + "\(x.pixels[at]) against \(y.pixels[at]); max values \(x.pixels.max() ?? 0) / \(y.pixels.max() ?? 0)")
    }

    /// Values at the border columns of the lower half, stage by stage.
    @Test("mask-combined-hazyLandscape at its border columns")
    func maskCombinedBorders() throws {
        let golden = try #require(GoldenTests.cases.first { $0.name == "mask-combined-hazyLandscape" })
        let input = golden.scene.image().ciImage
        let renderer = AdjustmentRenderer()
        let values = golden.adjustments.effective
        let crop = AdjustmentRenderer.crop(values, context: RenderContext())
        let selection = renderer.upstream(values, to: input, crop: crop, context: RenderContext())
        let masks = values.local.renderedMasks
        let estimates = renderer.localEstimates(masks, over: selection)
        var image = selection
        var stages: [(String, CIImage)] = [("selection", selection)]
        if let luminance = estimates.luminance { stages.append(("luminance estimate", luminance.cropped(to: selection.extent))) }
        var sharpening: [MaskSharpening] = []
        for (index, mask) in masks.enumerated() {
            let step = renderer.applyMask(mask, to: image, selection: selection, estimates: estimates,
                                          maskFrame: input.extent, crop: crop, context: RenderContext())
            stages.append(("alpha \(index)", step.alpha))
            stages.append(("after mask \(index)", step.image))
            image = step.image
            sharpening += step.sharpening
        }
        stages.append(("final", renderer.downstream(values, image, sharpening: sharpening, context: RenderContext())))
        for (name, stage) in stages {
            let pixels = Self.linear(stage.cropped(to: input.extent))
            let samples = [(0, 160), (1, 160), (254, 160), (255, 160), (0, 185), (255, 185), (128, 160)].map { x, y in
                let i = (y * pixels.width + x) * 4
                return "(\(x),\(y))=" + (0..<3).map { String(format: "%.5f", pixels.pixels[i + $0]) }.joined(separator: "/")
            }
            print("diagnostics mask-combined \(name): \(samples.joined(separator: " "))")
        }
    }

    /// The above-white stack without whole-frame estimates (the strict case of
    /// `LiveSessionTests.aboveWhite`): each cached stage against its lazy
    /// counterpart, for all masks and for each mask alone.
    @Test("Above-white content: cached stages against lazy ones")
    func aboveWhiteStages() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "bright.dng")
            try SyntheticDNG.write(to: url, options: .init(width: 640, height: 480, seed: 7))
            var strict = LiveSessionTests.masked()
            strict.exposure.ev = 1.5
            strict.tone.highlights = -20
            strict.local.masks[0].adjustments.dehaze = 0
            strict.local.masks[1].adjustments.shadows = 0
            let decoded = try PreviewGenerator.decode(url, longEdge: 640, draft: false, settings: strict.decodeSettings)
            let renderer = AdjustmentRenderer()
            func compare(_ label: String, _ adjustments: Adjustments) {
                let values = adjustments.effective
                let crop = AdjustmentRenderer.crop(values, context: decoded.context)
                let lazy = renderer.upstream(values, to: decoded.image, crop: crop, context: decoded.context)
                let cached = Self.materialized(lazy)
                let masks = values.local.renderedMasks
                let estimates = renderer.localEstimates(masks, over: lazy)
                var lazyImage = lazy, cachedImage = cached
                var lazySharpening: [MaskSharpening] = [], cachedSharpening: [MaskSharpening] = []
                for (index, mask) in masks.enumerated() {
                    let l = renderer.applyMask(mask, to: lazyImage, selection: lazy, estimates: estimates,
                                               maskFrame: decoded.image.extent, crop: crop, context: decoded.context)
                    let c = renderer.applyMask(mask, to: cachedImage, selection: cached, estimates: estimates,
                                               maskFrame: decoded.image.extent, crop: crop, context: decoded.context)
                    (lazyImage, cachedImage) = (l.image, c.image)
                    lazySharpening += l.sharpening
                    cachedSharpening += c.sharpening
                    Self.describe("\(label), after mask \(index)", cachedImage, lazyImage)
                }
                Self.describe("\(label), downstream",
                              renderer.downstream(values, cachedImage, sharpening: cachedSharpening, context: decoded.context),
                              renderer.downstream(values, lazyImage, sharpening: lazySharpening, context: decoded.context))
            }
            compare("strict, all masks", strict)
            for index in 0..<3 {
                var one = strict
                one.local.masks = [strict.local.masks[index]]
                compare("strict, mask \(index) alone", one)
            }
            var clarity = strict
            clarity.local.masks = [strict.local.masks[1]]
            clarity.sharpen = Sharpen()
            compare("mask 1 clarity, no global sharpening", clarity)
            var contrast = strict
            contrast.local.masks = [strict.local.masks[2]]
            contrast.local.masks[0].adjustments.sharpen = 0
            contrast.sharpen = Sharpen()
            compare("mask 2 contrast only", contrast)
        }
    }
}
