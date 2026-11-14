import CoreImage
import Foundation
import ImageIO
import Testing
@testable import PhotoCore

/// The fallback on a real file: a raw the system's RAW decoder gives no image
/// for is decoded by LibRaw (issue #161).
/// `RAF_SAMPLE=path/to/DSCF5123.RAF swift test --filter LibRawFallbackTests`
/// with a Fujifilm X-E3 file on macOS 27.2.1. `LibRawDecoderTests` and
/// `LibRawFallbackPipelineTests` cover the same code on synthetic files in
/// every run; this suite checks a camera's own file (its compressed loader,
/// its inset crop, its size and speed).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RAF_SAMPLE"] != nil,
                "Set RAF_SAMPLE to a raw the system decoder cannot read and run this suite alone"))
struct LibRawFallbackTests {
    private var url: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAF_SAMPLE"] ?? "") }

    @Test func theSystemDecoderGivesNoImage() {
        // The premise: with an image from the system decoder, nothing below goes through LibRaw.
        #expect(!SystemRAWDecoder.reads(url), "the system RAW decoder reads this file: pick another sample")
        #expect(RawDefaults(source: url) == nil)
    }

    @Test func decodesAtFullAndSmallSizes() throws {
        let full = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
        let fullEdge = max(full.image.extent.width, full.image.extent.height)
        // Whichever way the camera was held.
        #expect(fullEdge > 4000)
        #expect(!full.context.isRaw)
        #expect(full.context.scale == 1)
        let size = try #require(PreviewGenerator.nativeSize(url))
        #expect(size == full.image.extent.size)
        let small = try PreviewGenerator.decode(url, longEdge: 800, draft: false)
        #expect(max(small.image.extent.width, small.image.extent.height) < fullEdge)
        #expect(small.context.scale <= 0.5)
    }

    @Test func rendersThroughThePipeline() throws {
        let image = try PreviewGenerator().cgImage(source: url, stack: .identity, longEdge: 1000)
        #expect(max(image.width, image.height) == 1000)
    }

    /// Code review C4: 900 x 600 before, from a half-size decode chosen for the uncropped target.
    @Test func aCropDecodesLargeEnough() throws {
        var cropped = Adjustments()
        cropped.crop = Crop(rect: CropRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3))
        let size = try #require(PreviewGenerator.nativeSize(url))
        let image = try PreviewGenerator().image(source: url, stack: cropped.editStack, longEdge: 2560)
        // Three tenths of the frame, which is under the 2560 asked for: every pixel the file holds there.
        let expected = (max(size.width, size.height) * 0.3).rounded()
        #expect(abs(max(image.extent.width, image.extent.height) - expected) <= 1)
    }

    /// The owner's ruling (code review Q3): the photo can be adjusted after decoding.
    @Test func adjustmentsChangeTheRender() throws {
        let generator = PreviewGenerator()
        func render(_ edit: (inout Adjustments) -> Void) throws -> Data {
            var values = Adjustments()
            edit(&values)
            let image = try generator.cgImage(source: url, stack: values.editStack, longEdge: 400)
            return try #require(image.dataProvider?.data as Data?)
        }
        let plain = try render { _ in }
        #expect(try render { $0.whiteBalance = WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30) } != plain)
        #expect(try render { $0.exposure.ev = 1 } != plain)
        #expect(try render { $0.tone.highlights = -80 } != plain)
        #expect(try render { $0.noiseReduction.luminance = 80 } != plain)
        let balance = try AutoAdjuster(generator: generator).whiteBalance(source: url, adjustments: .none)
        #expect(balance.preset == .auto)
        #expect(balance.temperature == nil)
    }

    // MARK: The camera's frame and lens corrections (Fujifilm RAF)

    /// The JPEG the camera embedded in the file, which has the camera's own
    /// lens corrections, turned as the camera was held.
    private func embeddedJPEG(_ file: FujifilmRAF) throws -> CGImage {
        let range = try #require(file.embeddedJPEG)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: range.lowerBound)
        let data = try #require(try handle.read(upToCount: Int(range.count)))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let stored = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(stored.width, stored.height),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
    }

    /// LibRaw's half-size decode as gray at the JPEG's size, two stops brighter
    /// (the JPEG has the camera's tone curve; the decode is linear).
    private func gray(lensCorrections: Bool, width: Int, height: Int) throws -> [Float] {
        let output = try LibRawDecoder.decode(url, halfSize: true, lensCorrections: lensCorrections)
        // Tables that correct nothing (a lens without contacts) are not counted as corrections.
        let corrects = FujifilmRAF(contentsOf: url)?.lens.map { !$0.isIdentity } ?? false
        #expect(output.hasLensCorrections == (lensCorrections && corrects))
        let brighter = output.image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 2.0])
        let image = try #require(RenderEngine(contextCount: 1, name: "raf-check")
            .makeCGImage(brighter.scaledToFit(longEdge: max(width, height)), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        return BlockMatching.gray(image, width: width, height: height)
    }

    @Test func theFrameIsTheCameras() throws {
        let file = try #require(FujifilmRAF(contentsOf: url), "not a Fujifilm RAF")
        let frame = try #require(file.cameraFrame)
        // The file's tables, if it has any, are for this frame, and it is in no 1.25x crop mode.
        #expect(file.lensTables(for: frame).refusal == nil, "crop mode \(String(describing: file.cropMode))")
        let size = try #require(LibRawDecoder.frameSize(url))
        // 6000 x 4000 for an X-E3, as its JPEG and as the system decoder gives where it reads these files.
        #expect([size.width, size.height].sorted() == [CGFloat(frame.height), CGFloat(frame.width)].sorted())
        #expect(PreviewGenerator.nativeSize(url) == size)
        let half = try LibRawDecoder.decode(url, halfSize: true)
        #expect(half.fullSize == size)
        #expect(half.size == CGSize(width: size.width / 2, height: size.height / 2))
        #expect(half.image.extent == CGRect(origin: .zero, size: half.size))
        // With or without the corrections, the same frame.
        #expect(try LibRawDecoder.decode(url, halfSize: true, lensCorrections: false).size == half.size)
    }

    /// The camera's JPEG is the camera's own rendering of the frame, lens
    /// corrections applied. Details of it are looked up in the render, block
    /// by block (48 pixels square, on the JPEG's 1920 x 1280 grid): corrected,
    /// they are where the JPEG has them; uncorrected, they are not.
    @Test func theCorrectedRenderLinesUpWithTheCamerasJPEG() throws {
        let file = try #require(FujifilmRAF(contentsOf: url), "not a Fujifilm RAF")
        let lens = try #require(file.lens, "the file has no lens tables (a manual lens?)")
        let jpeg = try embeddedJPEG(file)
        let width = jpeg.width, height = jpeg.height
        let camera = BlockMatching.gray(jpeg, width: width, height: height)
        let corrected = try gray(lensCorrections: true, width: width, height: height)
        let matches = BlockMatching.matches(camera, corrected, width: width, height: height, block: 48, step: 48, search: 6)
        #expect(matches.count > 100, "too little detail in this picture to compare: \(matches.count) blocks")
        let decodeIsWide = try #require(LibRawDecoder.frameSize(url)).width > CGFloat(try #require(LibRawDecoder.frameSize(url)).height)
        #expect((width > height) == decodeIsWide, "the JPEG and the decode are turned differently")
        let shifts = matches.map { hypot($0.dx, $0.dy) }.sorted()
        let median = BlockMatching.median(shifts), ninth = shifts[shifts.count * 9 / 10]
        let cx = Double(width) / 2, cy = Double(height) / 2, radius = hypot(cx, cy)
        let outer = matches.filter { hypot(Double($0.x) - cx, Double($0.y) - cy) / radius >= 0.75 }
        print("LibRawFallbackTests: \(matches.count) blocks; corrected render against the camera's JPEG, in JPEG pixels:",
              "median shift \(median), 90th percentile \(ninth), largest \(shifts.last ?? 0);",
              "beyond 0.75 of the radius (\(outer.count) blocks) median \(BlockMatching.median(outer.map { hypot($0.dx, $0.dy) }))")
        // Half a JPEG pixel is a pixel and a half of the 24-megapixel frame. (Without anything
        // to correct the numbers say how well this picture can be matched at all.)
        if !lens.isIdentity {
            #expect(median <= 0.5)
            #expect(ninth <= 1.5)
        }

        // Uncorrected, an eighth of the size (shifts of tens of pixels): the same details sit elsewhere.
        let small = (width: width / 8, height: height / 8)
        let uncorrected = BlockMatching.matches(BlockMatching.gray(jpeg, width: small.width, height: small.height),
                                                try gray(lensCorrections: false, width: small.width, height: small.height),
                                                width: small.width, height: small.height, block: 16, step: 8, search: 12)
        let uncorrectedShifts = uncorrected.map { hypot($0.dx, $0.dy) * 8 }.sorted()
        let expected = abs(EmbeddedLensCorrection(lens, shortSideRadius: Double(min(width, height)) / hypot(Double(width), Double(height)))
            .multipliers(atOutputRadius: 1).y - 1) * radius
        print("LibRawFallbackTests: uncorrected, median shift \(BlockMatching.median(uncorrectedShifts)),",
              "largest \(uncorrectedShifts.last ?? 0) JPEG pixels (the tables move the corner by \(expected))")
        if expected > 8 {
            #expect(BlockMatching.median(uncorrectedShifts) > 4 * median)
        }

        // Light: how bright the render is beside the JPEG, far from the center against near it.
        // Near the center (within 0.4 of the radius) the render's gray is mapped from the JPEG's
        // (the two have different tone curves) by the medians of twelve brightness classes; far
        // out (beyond 0.75) the render's blocks are compared with what that map gives.
        func farOverNear(_ render: [Float]) -> Double {
            let a = BlockMatching.means(camera, width: width, height: height, block: 64)
            let b = BlockMatching.means(render, width: width, height: height, block: 64)
            var pairs: [(rho: Double, camera: Double, render: Double)] = []
            for (inCamera, inRender) in zip(a, b) {
                // Neither nearly black nor clipped, in either picture.
                guard inCamera.mean > 16, inCamera.mean < 236, inRender.mean > 8, inRender.mean < 246 else { continue }
                let rho = hypot(Double(inCamera.x) - cx, Double(inCamera.y) - cy) / radius
                pairs.append((rho, inCamera.mean, inRender.mean))
            }
            let near = pairs.filter { $0.rho < 0.4 }.sorted { $0.camera < $1.camera }
            print("LibRawFallbackTests: light: \(pairs.count) usable blocks, \(near.count) near, \(pairs.filter { $0.rho > 0.75 }.count) far")
            guard near.count >= 24 else { return .nan }
            let classes = (0..<12).map { index -> (camera: Double, render: Double) in
                let part = near[(index * near.count / 12)..<((index + 1) * near.count / 12)]
                return (BlockMatching.median(part.map(\.camera)), BlockMatching.median(part.map(\.render)))
            }
            func mapped(_ value: Double) -> Double? {
                guard let first = classes.first, let last = classes.last, value >= first.camera, value <= last.camera else { return nil }
                for (low, high) in zip(classes, classes.dropFirst()) where value <= high.camera {
                    let t = high.camera > low.camera ? (value - low.camera) / (high.camera - low.camera) : 0
                    return low.render + (high.render - low.render) * t
                }
                return last.render
            }
            let ratios = pairs.filter { $0.rho > 0.75 }.compactMap { pair in mapped(pair.camera).map { pair.render / $0 } }
            return ratios.count >= 6 ? BlockMatching.median(ratios) : .nan
        }
        let light = farOverNear(corrected)
        let falloff = EmbeddedLensCorrection.value(lens.vignetting, knots: lens.knots, at: 0.85) / 100
        print("LibRawFallbackTests: far from the center the corrected render is \(light) as bright beside the JPEG as near it",
              "(the lens passes \(falloff) of the light at 0.85 of the radius)")
        if !light.isNaN, falloff < 0.8 {
            // In gamma-encoded gray, a share f of the light is about f to the power 1 / 2.2.
            #expect(abs(light - 1) < (1 - pow(falloff, 1 / 2.2)) / 2)
        }
    }
}
