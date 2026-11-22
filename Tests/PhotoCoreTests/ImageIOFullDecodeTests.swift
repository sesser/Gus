import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// A full-size decode of a file ImageIO reads (JPEG, HEIC, PNG, TIFF) and the
/// renders made from it (bug #253, docs/features/core-image-split-render/status.md).
///
/// Over `CIImage(contentsOf:)`, a full render of a large photo with Shadows or
/// negative Highlights now and then came out with its left half showing the
/// right half's pixels: the loupe at 100% showed two halves that didn't line
/// up. Serialized: each render holds a 20 MP photo.
///
/// Each test's body runs `offCooperativePool`: its renders wait for the GPU and
/// its comparisons take seconds on CI's three cores, which, on the cooperative
/// pool, starved the tests running beside them (bug #253, status.md "CI").
///
/// The 20 MP soak (`largeRenderKeepsItsParts`) runs only with
/// `LARGE_RENDER_TESTS=1 swift test --filter ImageIOFullDecodeTests`: the CI
/// runners' paravirtual GPU fails renders that size, as `DeferredRenderTests`
/// records. The other tests run everywhere and fail without the fix too
/// (`fullDecodeIsResident`, `renderUnchanged`, and the JPEG case of
/// `LensAlignStaleAreaTests.tileSeesTheInputArea`).
@Suite("Full-size ImageIO decodes", .serialized)
struct ImageIOFullDecodeTests {
    /// The owner's file: 5472 × 3648, 20 MP (a Canon EOS 6D's frame size).
    static let width = 5472, height = 3648

    /// A pattern whose left and right halves differ everywhere: red rises
    /// across the width, green up the height, and a 64-pixel checker in blue.
    static func pattern(width: Int, height: Int) -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let red = CIFilter.linearGradient()
        red.point0 = .zero
        red.point1 = CGPoint(x: width, y: 0)
        red.color0 = CIColor(red: 0, green: 0, blue: 0)
        red.color1 = CIColor(red: 1, green: 0, blue: 0)
        let green = CIFilter.linearGradient()
        green.point0 = .zero
        green.point1 = CGPoint(x: 0, y: height)
        green.color0 = CIColor(red: 0, green: 0, blue: 0)
        green.color1 = CIColor(red: 0, green: 1, blue: 0)
        let checker = CIFilter.checkerboardGenerator()
        checker.color0 = CIColor(red: 0, green: 0, blue: 0.75)
        checker.color1 = CIColor(red: 0, green: 0, blue: 0.15)
        checker.width = 64
        let first = CIFilter.additionCompositing()
        first.inputImage = red.outputImage
        first.backgroundImage = green.outputImage
        let second = CIFilter.additionCompositing()
        second.inputImage = first.outputImage
        second.backgroundImage = checker.outputImage
        return second.outputImage!.cropped(to: rect)
    }

    /// The pattern as a TIFF laid out as the owner's file: uncompressed,
    /// chunky 16-bit RGB with no alpha, Display P3, written by ImageIO.
    static func writeLargeTIFF(to url: URL) throws {
        let rgba = pattern(width: width, height: height).cgImageForTest()
        let byteOrder = rgba.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        guard let provider = rgba.dataProvider,
              let rgb = CGImage(width: rgba.width, height: rgba.height, bitsPerComponent: 16, bitsPerPixel: 64,
                                bytesPerRow: rgba.bytesPerRow, space: RenderEngine.outputColorSpace,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | byteOrder),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw CocoaError(.fileWriteUnknown) }
        try SyntheticImages.write(rgb, to: url, type: .tiff)
    }

    /// The red channel of every 13th row of a BGRA8 render, top to bottom.
    static func sampledRed(_ image: CGImage) -> [[UInt8]] {
        let bytes = LiveRegionRendererTests.bytes(image)
        let width = image.width
        return bytes.withUnsafeBufferPointer { buffer in
            stride(from: 0, to: image.height, by: 13).map { y in
                (0..<width).map { buffer[(y * width + $0) * 4 + 2] }
            }
        }
    }

    /// How many values of `a` and `b` differ (`!=`, as Float compares), the
    /// arrays being the same length. A loop over raw pointers: in a debug
    /// build `zip(a, b).filter { $0 != $1 }.count` runs unspecialized generic
    /// code per value, about 4 s for the 24 million values of a 3000 × 2000
    /// float render (bug #253, status.md "CI").
    static func differingCount(_ a: [Float], _ b: [Float]) -> Int {
        precondition(a.count == b.count)
        return a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                guard let left = a.baseAddress, let right = b.baseAddress else { return 0 }
                var count = 0, index = 0
                while index < a.count {
                    if left[index] != right[index] { count += 1 }
                    index += 1
                }
                return count
            }
        }
    }

    /// The fault's signature: the left half repeats the right half. On the
    /// pattern the halves differ by about half of red's range everywhere.
    static func leftHalfRepeatsRight(_ rows: [[UInt8]]) -> Bool {
        var total = 0, count = 0
        for row in rows {
            let half = row.count / 2
            for x in stride(from: 0, to: half, by: 61) {
                total += abs(Int(row[x]) - Int(row[x + half]))
                count += 1
            }
        }
        return Double(total) / Double(count) < 8
    }

    @Test("A full-size decode of an ImageIO file is read from the GPU, not from the file")
    func fullDecodeIsResident() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { folder in
                let tiff = folder.appending(path: "large.tif")
                try SyntheticImages.write(Self.pattern(width: 640, height: 480).cgImageForTest(), to: tiff, type: .tiff)
                let jpeg = folder.appending(path: "photo.jpg")
                try SyntheticImages.writeJPEG(to: jpeg, width: 640, height: 480, seed: 3)
                for url in [tiff, jpeg] {
                    // Core Image's own reader keeps the file's URL on the image it reads.
                    #expect(CIImage(contentsOf: url, options: [.applyOrientationProperty: true])?.url == url)
                    let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
                    #expect(decoded.image.url == nil, "\(url.lastPathComponent)")
                    #expect(decoded.image.extent == CGRect(x: 0, y: 0, width: 640, height: 480))
                    // Measuring the graph only (the loupe's early size) still reads just the header.
                    let measured = try PreviewGenerator.decode(url, longEdge: nil, draft: false, forSizeOnly: true)
                    #expect(measured.image.url == url)
                }
            }
        }
    }

    @Test("The GPU copy renders the file's pixels, in bands that cover the photo once")
    func residentCopyIsTheFile() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { folder in
                let url = folder.appending(path: "large.tif")
                // Wider than a band is tall at this width: several bands.
                try SyntheticImages.write(Self.pattern(width: 3000, height: 2000).cgImageForTest(), to: url, type: .tiff)
                let lazy = try #require(CIImage(contentsOf: url))
                #expect(ResidentDecode.bands(of: lazy.extent).count > 1)
                let resident = try #require(ResidentDecode.resident(lazy))
                #expect(resident.extent == lazy.extent)
                let engine = RenderEngine(contextCount: 1, name: "full-decode-test")
                func values(_ image: CIImage) -> [Float] {
                    var out = [Float](repeating: 0, count: 3000 * 2000 * 4)
                    engine.withContext {
                        $0.render(image, toBitmap: &out, rowBytes: 3000 * 16, bounds: image.extent, format: .RGBAf,
                                  colorSpace: RenderEngine.workingColorSpace)
                    }
                    return out
                }
                let differing = Self.differingCount(values(resident), values(lazy))
                #expect(differing == 0, "\(differing) values differ")
            }
        }
    }

    /// The owner's stack's gain on a difference before it, as
    /// `LiveRegionRendererTests.typicalGain` derives it: Exposure (2^ev),
    /// local tone's largest gain and the tone table's largest relative slope.
    static let ownerGain: Double = {
        let values = ownerValues
        let tone = values.tone
        let local = LocalToneCurve(shadows: tone.shadows / 100, recovery: max(-tone.highlights, 0) / 100)
        let localTone = Double(local.gainTable().max() ?? 1)
        let table = ToneTable(contrast: tone.contrast / 100, highlights: max(tone.highlights, 0) / 100,
                              whites: tone.whites / 100, blacks: tone.blacks / 100, curve: values.toneCurve).rgbTable()
        let step = ToneTable.domainMaximum / Double(table.count / 3 - 1)
        var slope = 1.0
        for i in 1..<(table.count / 3 - 1) {
            let x = Double(i) * step, y = Double(table[i * 3])
            let rise = Double(table[(i + 1) * 3] - table[(i - 1) * 3]) / (2 * step)
            if y > 0.01 { slope = max(slope, x * rise / y) }
        }
        return pow(2, values.exposure.ev) * localTone * slope
    }()

    /// No rendering changed, resampling aside. Unedited, the GPU copy
    /// renders exactly what the file's image renders. Straightening and
    /// rotation now interpolate linear light, as raws and the 100% live
    /// frames do (`ResidentDecode`; status.md measures it on real photos),
    /// so no geometry is checked here. With edits Core Image may place its
    /// half-float intermediates differently over the two (over the copy it
    /// fused a heal into one float program where the file's image got an
    /// intermediate), so they may differ by one half-float rounding, times
    /// what the stack does to a difference, seen through the display curve:
    /// the tolerance of the 100% renderer (`LiveRegionRendererTests.allowedSteps`).
    /// Measured: at most 0.001 (heal) and 0.003 (the owner's stack) in
    /// linear values. Small enough not to be split, so the file's renders
    /// are the same every time.
    @Test("A render of the GPU copy is the render of the file's image", arguments: ["photo.jpg", "pattern.tif"])
    func renderUnchanged(name: String) async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { folder in
                let url = folder.appending(path: name)
                if name.hasSuffix(".jpg") {
                    try SyntheticImages.writeJPEG(to: url, width: 1200, height: 800, seed: 4)
                } else {
                    try SyntheticImages.write(Self.pattern(width: 1500, height: 1000).cgImageForTest(), to: url, type: .tiff)
                }
                let engine = RenderEngine(contextCount: 1, name: "full-decode-test")
                let renderer = AdjustmentRenderer()
                let context = RenderContext(scale: 1, isRaw: false, lens: .notRaw)
                let file = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
                let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false).image
                #expect(decoded.url == nil)
                func values(_ image: CIImage) -> [Float] {
                    let width = Int(image.extent.width), height = Int(image.extent.height)
                    var out = [Float](repeating: 0, count: width * height * 4)
                    engine.withContext {
                        $0.render(image, toBitmap: &out, rowBytes: width * 16, bounds: image.extent, format: .RGBAf,
                                  colorSpace: RenderEngine.workingColorSpace)
                    }
                    return out
                }
                let unedited = Self.differingCount(values(file), values(decoded))
                #expect(unedited == 0, "\(name), unedited: \(unedited) values differ")

                var healed = Adjustments()
                healed.spots.spots = [Spot(center: MaskPoint(x: 0.4, y: 0.6), size: 0.05, source: MaskPoint(x: 0.4, y: 0.75))]
                for (label, stack, gain) in [("owner", Self.ownerValues, Self.ownerGain), ("heal", healed, 1.0)] {
                    let expected = try #require(engine.makeCGImage(renderer.render(stack, to: file, context: context)))
                    let actual = try #require(engine.makeCGImage(renderer.render(stack, to: decoded, context: context)))
                    // The tolerance depends on the encoded value only: worked out once per
                    // value, not once per channel (a `pow` each, millions of them).
                    let allowed = (0...255).map { LiveRegionRendererTests.allowedSteps(gain: gain, encoded: UInt8($0)) }
                    let result = LiveRegionRendererTests.compare(
                        frame: actual, whole: LiveRegionRendererTests.bytes(expected), wholeWidth: expected.width,
                        region: CGRect(x: 0, y: 0, width: actual.width, height: actual.height)
                    ) { allowed[Int($0)] }
                    LiveRegionRendererTests.report("\(name), \(label)", result, pixels: actual.width * actual.height)
                    #expect(result.over == 0, "\(name), \(label): \(result.overValues)")
                }
            }
        }
    }

    /// The owner's limit (2026-11-21): copies up to 100 megapixels, and never
    /// a side over one texture's; above either the decode stays lazy.
    @Test("A decode is copied up to 100 megapixels and 16384 pixels a side")
    func residencyLimit() {
        #expect(ResidentDecode.maximumPixels == 100_000_000)
        #expect(ResidentDecode.maximumDimension == 16384)
        #expect(ResidentDecode.lazyReason(width: 5472, height: 3648) == nil)
        #expect(ResidentDecode.lazyReason(width: 10000, height: 10000) == nil)
        #expect(ResidentDecode.lazyReason(width: 16384, height: 6103) == nil)
        #expect(ResidentDecode.lazyReason(width: 10000, height: 10001) == .overPixelLimit)
        #expect(ResidentDecode.lazyReason(width: 12000, height: 9000) == .overPixelLimit)
        #expect(ResidentDecode.lazyReason(width: 16385, height: 100) == .sideOverTextureLimit)
        #expect(ResidentDecode.lazyReason(width: 100, height: 16385) == .sideOverTextureLimit)
        // Both over: the side is the reason, no texture could hold it.
        #expect(ResidentDecode.lazyReason(width: 20000, height: 6000) == .sideOverTextureLimit)
        // And `resident` keeps such an image lazy before it makes any texture.
        let over = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 10000, height: 10001))
        #expect(ResidentDecode.resident(over) == nil)
    }

    @Test("The value comparison counts every differing value, as Float compares them")
    func differingCountCountsEveryDifference() {
        #expect(Self.differingCount([], []) == 0)
        #expect(Self.differingCount([1, 2, 3, 4], [1, 2, 3, 4]) == 0)
        #expect(Self.differingCount([1, 2, 3, 4], [0, 2, 3, 5]) == 2)
        #expect(Self.differingCount([0, .nan], [-0, .nan]) == 1)
    }

    @Test("Bands cover the extent top first, without gaps or overlaps")
    func bandsCoverTheExtent() {
        let extent = CGRect(x: 0, y: 0, width: 5472, height: 3648)
        let bands = ResidentDecode.bands(of: extent)
        let rows = ResidentDecode.bandPixels / 5472
        #expect(bands.count == (3648 + rows - 1) / rows)
        #expect(bands.allSatisfy { $0.rect.width * $0.rect.height <= CGFloat(ResidentDecode.bandPixels) })
        // Top first: the first band ends at the top edge, the last starts at the bottom.
        #expect(bands.first?.rect.maxY == 3648 && bands.last?.rect.minY == 0)
        for (upper, lower) in zip(bands, bands.dropFirst()) { #expect(lower.rect.maxY == upper.rect.minY) }
        #expect(bands.allSatisfy { $0.origin == CGPoint(x: 0, y: $0.rect.minY) })
        #expect(bands.reduce(0) { $0 + $1.rect.height } == 3648)
        let offset = ResidentDecode.bands(of: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(offset.count == 1 && offset[0].rect == CGRect(x: 10, y: 20, width: 100, height: 50)
            && offset[0].origin == .zero)
        #expect(ResidentDecode.bands(of: .zero).isEmpty)
    }

    /// Compared in the working space, in float, as `residentCopyIsTheFile`:
    /// the copy holds exactly the values Core Image computes from the file.
    /// Not in 8-bit Display P3: over the file Core Image builds a different
    /// program for the conversion to the output (it starts from the file's
    /// encoding, not from linear floats), which now and then rounds one value
    /// one level the other way. Which files do it varies between processes:
    /// of eight synthetic JPEGs, five or all eight differed in one byte by one
    /// level, while their float values were equal every time (bug #253, code
    /// review second pass).
    @Test("An EXIF orientation is still applied to the full-size decode")
    func fullDecodeIsOriented() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { folder in
                let url = folder.appending(path: "turned.jpg")
                try SyntheticImages.writeJPEG(to: url, width: 640, height: 480, seed: 4,
                                              exif: SyntheticImages.Exif(orientation: 6))
                let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
                let reference = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
                #expect(decoded.image.extent == reference.extent)
                #expect(decoded.image.extent.size == CGSize(width: 480, height: 640))
                let engine = RenderEngine(contextCount: 1, name: "full-decode-test")
                func values(_ image: CIImage) -> [Float] {
                    var out = [Float](repeating: 0, count: 480 * 640 * 4)
                    engine.withContext {
                        $0.render(image, toBitmap: &out, rowBytes: 480 * 16, bounds: image.extent, format: .RGBAf,
                                  colorSpace: RenderEngine.workingColorSpace)
                    }
                    return out
                }
                let differing = Self.differingCount(values(decoded.image), values(reference))
                #expect(differing == 0, "\(differing) values differ")
            }
        }
    }

    /// The owner's values: Highlights below 0 is what reads the photo from
    /// several programs of one render.
    static var ownerValues: Adjustments {
        var values = Adjustments()
        values.exposure.ev = 1.05
        values.tone = Tone(contrast: 66, highlights: -45, shadows: 0, whites: 0, blacks: -100)
        return values
    }

    /// The renders the loupe shows at 100% at rest (`cgImage`, the full
    /// rendition) of a 16-bit TIFF of the owner's size, each on a fresh
    /// engine after another stack's render, as the bug's reproduction did:
    /// every one keeps its halves in place and they are all the same.
    /// Without the fix, about one render in three showed the left half
    /// repeating the right (status.md: 7 of 24, 12 of 36).
    @Test("A full render of a 20 MP TIFF with Highlights keeps its parts in place",
          .enabled(if: ProcessInfo.processInfo.environment["LARGE_RENDER_TESTS"] == "1",
                   "Set LARGE_RENDER_TESTS=1 to run: 20 MP renders the CI runners' GPU can't do"))
    func largeRenderKeepsItsParts() async throws {
        try await offCooperativePool {
            try await RepositoryFiles.withTemporaryDirectory { folder in
                let url = folder.appending(path: "IMG_1.tif")
                try Self.writeLargeTIFF(to: url)
                var exposureOnly = Adjustments()
                exposureOnly.exposure.ev = 1.05
                var first: [[UInt8]]?
                var swapped = 0, unlike = 0
                for _ in 0..<4 {
                    let generator = PreviewGenerator(engine: RenderEngine(contextCount: 1, name: "full-decode-test"))
                    _ = try generator.cgImage(source: url, stack: exposureOnly.editStack)
                    for _ in 0..<4 {
                        let image = try generator.cgImage(source: url, stack: Self.ownerValues.editStack)
                        #expect(image.width == Self.width && image.height == Self.height)
                        let red = Self.sampledRed(image)
                        if Self.leftHalfRepeatsRight(red) { swapped += 1 }
                        if let first {
                            let differs = zip(red, first).contains { row, firstRow in
                                zip(row, firstRow).contains { abs(Int($0) - Int($1)) > 2 }
                            }
                            if differs { unlike += 1 }
                        } else {
                            first = red
                        }
                    }
                }
                #expect(swapped == 0, "\(swapped) of 16 renders showed the right half on the left")
                #expect(unlike == 0, "\(unlike) of 15 renders differed from the first")
            }
        }
    }
}

private extension CIImage {
    /// A 16-bit Display P3 copy, for writing as a file.
    func cgImageForTest() -> CGImage {
        RenderEngine(contextCount: 1, name: "full-decode-test")
            .makeCGImage(self, colorSpace: RenderEngine.outputColorSpace, bitsPerComponent: 16)!
    }
}
