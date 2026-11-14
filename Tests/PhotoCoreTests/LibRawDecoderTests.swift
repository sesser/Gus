import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// The vendored LibRaw decoder and the fallback to it (issue #161), on
/// synthetic DNGs, so every line of it runs in a default `swift test` on
/// every macOS. The system's RAW decoder gives no image for the 256 x 192
/// one on macOS 27.2.1, which is the bug's condition; the tests that need
/// that say so, and the others call LibRaw directly.
@Suite("LibRaw decoder")
struct LibRawDecoderTests {
    static let width = 256, height = 192

    static func dng(in folder: URL, _ name: String, width: Int = width, height: Int = height, seed: UInt64 = 7,
                    orientation: Int = 1, scene: SyntheticDNG.Scene = .pattern, defaultCrop: CGRect? = nil) throws -> URL {
        let url = folder.appending(path: "\(name).dng")
        try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: seed, orientation: orientation,
                                                       scene: scene, defaultCrop: defaultCrop))
        return url
    }

    /// The decode's samples, four to a pixel, rows from the top.
    static func samples(_ output: LibRawDecoder.Output) -> [UInt16] {
        output.rgba16.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
    }

    /// One pixel's red, green and blue.
    static func pixel(_ samples: [UInt16], width: Int, x: Int, y: Int) -> [UInt16] {
        Array(samples[((y * width + x) * 4)..<((y * width + x) * 4 + 3)])
    }

    // MARK: The decode

    /// The mosaic holds linear values at 0.85 of the white level
    /// (`SyntheticDNG.mosaic`), the camera's primaries are sRGB's with a
    /// neutral as-shot white, and the decode is linear with no brightening:
    /// a grey stays grey and keeps its level. (The stripes' brightest value
    /// is under three quarters of the white level, so LibRaw's adjustment of
    /// the maximum leaves it alone.)
    @Test("A decode is linear, neutral and as bright as the file's values")
    func decodeIsLinearAndNeutral() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.dng(in: folder, "stripes", scene: .stripes(period: 64))
            let output = try LibRawDecoder.decode(url)
            #expect(output.size == CGSize(width: Self.width, height: Self.height))
            #expect(output.fullSize == output.size)
            #expect(output.image.extent == CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
            #expect(output.cameraMake == "Synthetic")
            let samples = Self.samples(output)
            #expect(samples.count == Self.width * Self.height * 4)
            func linear(_ srgb8: Double) -> Double {
                let v = srgb8 / 255
                return (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)) * 0.85 * 65535
            }
            // The middle of a dark stripe and of a bright one (sRGB 0.25 and 0.75 as 8 bits), away from the edges.
            for (x, expected) in [(32, linear(64)), (96, linear(191))] {
                let rgb = Self.pixel(samples, width: Self.width, x: x, y: Self.height / 2).map(Double.init)
                for value in rgb {
                    // 1%: the 8-bit table's rounding and LibRaw's 16-bit color matrix arithmetic.
                    #expect(abs(value - expected) <= expected * 0.01, "x \(x): \(rgb) against \(expected)")
                }
            }
            // Opaque.
            #expect(samples[3] == .max)
        }
    }

    /// LibRaw applies the file's orientation; each oriented pixel is the
    /// stored pixel the orientation's definition names. All seven that are
    /// not upright: the mirrored quarter turns (5 and 7) swap width and height
    /// as the plain ones (6 and 8) do (code review C13).
    @Test("A decode is oriented as the file says", arguments: [2, 3, 4, 5, 6, 7, 8])
    func decodeIsOriented(orientation: Int) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let upright = try LibRawDecoder.decode(try Self.dng(in: folder, "upright"))
            let turnedURL = try Self.dng(in: folder, "turned", orientation: orientation)
            let turned = try LibRawDecoder.decode(turnedURL)
            let w = Self.width, h = Self.height
            let swapsSides = orientation >= 5
            #expect(turned.size == (swapsSides ? CGSize(width: h, height: w) : CGSize(width: w, height: h)))
            // The header alone gives the size as it is shown.
            #expect(LibRawDecoder.frameSize(turnedURL) == turned.size)
            #expect(PreviewGenerator.nativeSize(turnedURL).map { max($0.width, $0.height) } == CGFloat(w))
            let stored = Self.samples(upright), shown = Self.samples(turned)
            let shownWidth = Int(turned.size.width), shownHeight = Int(turned.size.height)
            var differing = 0
            for y in 0..<shownHeight {
                for x in 0..<shownWidth {
                    // The stored pixel shown at (x, y), by the orientation tag's definition.
                    let (sx, sy) = switch orientation {
                    case 2: (w - 1 - x, y)          // mirrored left to right
                    case 3: (w - 1 - x, h - 1 - y)  // half a turn
                    case 4: (x, h - 1 - y)          // mirrored top to bottom
                    case 5: (y, x)                  // mirrored, then a quarter turn: rows become columns
                    case 6: (y, h - 1 - x)          // a quarter turn clockwise
                    case 7: (w - 1 - y, h - 1 - x)  // mirrored, then a quarter turn the other way
                    default: (w - 1 - y, x)         // 8: a quarter turn counterclockwise
                    }
                    if Self.pixel(shown, width: shownWidth, x: x, y: y) != Self.pixel(stored, width: w, x: sx, y: sy) {
                        differing += 1
                    }
                }
            }
            #expect(differing == 0)
        }
    }

    @Test("A target of at most half the frame decodes at half size, a larger one in full")
    func halfSizeRule() async throws {
        #expect(!LibRawDecoder.usesHalfSize(longEdge: nil, frameLongEdge: 256))
        #expect(LibRawDecoder.usesHalfSize(longEdge: 128, frameLongEdge: 256))
        #expect(!LibRawDecoder.usesHalfSize(longEdge: 129, frameLongEdge: 256))
        // A Fujifilm X-E3's frame: the preview tier is under half of it, a 3000 pixel export is not.
        #expect(LibRawDecoder.usesHalfSize(longEdge: 2560, frameLongEdge: 5998))
        #expect(!LibRawDecoder.usesHalfSize(longEdge: 3000, frameLongEdge: 5998))
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.dng(in: folder, "half")
            let half = try LibRawDecoder.decode(url, longEdge: 128)
            #expect(half.size == CGSize(width: 128, height: 96))
            #expect(half.fullSize == CGSize(width: 256, height: 192))
            #expect(half.rgba16.count == 128 * 96 * 8)
            let full = try LibRawDecoder.decode(url, longEdge: 129)
            #expect(full.size == CGSize(width: 256, height: 192))
            #expect(try LibRawDecoder.decode(url, halfSize: true).size == half.size)
        }
    }

    // MARK: The frame

    @Test("The frame is the file's inset crop inside LibRaw's visible area, or the visible area")
    func frameFromSizes() {
        // A Fujifilm X-E3 file, as LibRaw reads it: 6032 x 4028 visible, 6 rows down the
        // sensor, and the camera's frame of 5998 x 3997 at (18, 24) of the sensor.
        let fuji = LibRawDecoder.Frame(visibleWidth: 6032, visibleHeight: 4028, leftMargin: 0, topMargin: 6,
                                       insetLeft: 18, insetTop: 24, insetWidth: 5998, insetHeight: 3997, flip: 0)
        #expect(fuji.width == 5998 && fuji.height == 3997)
        #expect(fuji.cropBox.map { [$0.left, $0.top, $0.width, $0.height] } == [18, 18, 5998, 3997])
        #expect(fuji.orientedSize == CGSize(width: 5998, height: 3997))
        // The inset is in sensor coordinates; the crop box is in the visible area's.
        let margins = LibRawDecoder.Frame(visibleWidth: 5200, visibleHeight: 3900, leftMargin: 12, topMargin: 8,
                                          insetLeft: 20, insetTop: 8, insetWidth: 5184, insetHeight: 3888, flip: 6)
        #expect(margins.cropBox.map { [$0.left, $0.top, $0.width, $0.height] } == [8, 0, 5184, 3888])
        #expect(margins.orientedSize == CGSize(width: 3888, height: 5184))
        // No inset (LibRaw leaves its origin at 0xffff and its size at 0): the visible area.
        let none = LibRawDecoder.Frame(visibleWidth: 5472, visibleHeight: 3648, leftMargin: 0, topMargin: 0,
                                       insetLeft: 0xffff, insetTop: 0xffff, insetWidth: 0, insetHeight: 0, flip: 5)
        #expect(none.cropBox == nil)
        #expect(none.width == 5472 && none.height == 3648)
        #expect(none.orientedSize == CGSize(width: 3648, height: 5472))
        // Every flip with LibRaw's "swap the axes" bit turns the frame: 4 and 7 as 5 and 6.
        for flip in 0...7 {
            let frame = LibRawDecoder.Frame(visibleWidth: 300, visibleHeight: 200, leftMargin: 0, topMargin: 0,
                                            insetLeft: 0xffff, insetTop: 0xffff, insetWidth: 0, insetHeight: 0, flip: flip)
            #expect(frame.isTurned == [4, 5, 6, 7].contains(flip), "flip \(flip)")
            #expect(frame.orientedSize == (frame.isTurned ? CGSize(width: 200, height: 300) : CGSize(width: 300, height: 200)))
        }
        // An inset that starts before the visible area cannot be a crop of it: ignored.
        let before = LibRawDecoder.Frame(visibleWidth: 4000, visibleHeight: 3000, leftMargin: 16, topMargin: 16,
                                         insetLeft: 8, insetTop: 16, insetWidth: 3900, insetHeight: 2900, flip: 3)
        #expect(before.cropBox == nil)
        #expect(before.orientedSize == CGSize(width: 4000, height: 3000))
    }

    /// LibRaw reads a DNG's default crop as the file's inset crop: the decode
    /// is that part of the mosaic, pixel for pixel away from its borders
    /// (where demosaicing has other neighbors).
    ///
    /// LibRaw takes the brightest value in the frame as white when it is over
    /// three quarters of the white level, so the frame holds the picture's
    /// brightest values here (the seed's bar code, all white), as the whole
    /// mosaic does: both decodes have the same white.
    @Test("A file's inset crop is the frame of its decode")
    func insetCropIsDecoded() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let crop = CGRect(x: 16, y: 20, width: 224, height: 168)
            let whole = try LibRawDecoder.decode(try Self.dng(in: folder, "whole", seed: .max))
            let croppedURL = try Self.dng(in: folder, "cropped", seed: .max, defaultCrop: crop)
            let cropped = try LibRawDecoder.decode(croppedURL)
            #expect(cropped.size == crop.size)
            #expect(LibRawDecoder.frameSize(croppedURL) == crop.size)
            let all = Self.samples(whole), part = Self.samples(cropped)
            var differing = 0
            let border = 8
            for y in border..<(Int(crop.height) - border) {
                for x in border..<(Int(crop.width) - border)
                where Self.pixel(part, width: Int(crop.width), x: x, y: y)
                    != Self.pixel(all, width: Self.width, x: x + Int(crop.minX), y: y + Int(crop.minY)) {
                    differing += 1
                }
            }
            #expect(differing == 0)
            // The same comparison two pixels off (the same place in the color filter array) does not hold.
            var shifted = 0
            for y in border..<(Int(crop.height) - border) {
                for x in border..<(Int(crop.width) - border)
                where Self.pixel(part, width: Int(crop.width), x: x, y: y)
                    != Self.pixel(all, width: Self.width, x: x + Int(crop.minX) + 2, y: y + Int(crop.minY) + 2) {
                    shifted += 1
                }
            }
            #expect(shifted > 208 * 152 / 2)
            // Half size keeps the frame.
            let half = try LibRawDecoder.decode(croppedURL, halfSize: true)
            #expect(half.size == CGSize(width: crop.width / 2, height: crop.height / 2))
        }
    }

    // MARK: Failing files

    @Test("A file LibRaw cannot read fails with its reason, and is undecodable")
    func failingFiles() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            var random = SplitMix64(seed: 3)
            let noise = folder.appending(path: "noise.dng")
            try Data((0..<4096).map { _ in UInt8(truncatingIfNeeded: random.next()) }).write(to: noise)
            let empty = folder.appending(path: "empty.dng")
            try Data().write(to: empty)
            // A header that promises a mosaic the file does not hold.
            let truncated = folder.appending(path: "truncated.dng")
            try SyntheticDNG.data(options: .init(width: Self.width, height: Self.height, seed: 7)).prefix(2048)
                .write(to: truncated)
            let missing = folder.appending(path: "missing.dng")
            for url in [noise, empty, truncated, missing] {
                #expect(throws: LibRawDecoder.Failure.self, "\(url.lastPathComponent)") {
                    _ = try LibRawDecoder.decode(url)
                }
            }
            // Nothing in these for any decoder: the pipeline reports them undecodable.
            for url in [noise, empty, missing] {
                #expect(throws: PreviewGenerator.Failure.undecodable(url), "\(url.lastPathComponent)") {
                    _ = try PreviewGenerator.decode(url, longEdge: nil, draft: false)
                }
                #expect(LibRawDecoder.frameSize(url) == nil, "\(url.lastPathComponent)")
                #expect(PreviewGenerator.nativeSize(url) == nil, "\(url.lastPathComponent)")
            }
            guard case .libraw(let step, let code)? = Self.failure({ try LibRawDecoder.decode(noise) }) else {
                Issue.record("no LibRaw failure for random bytes")
                return
            }
            #expect(step == "open")
            #expect(code != 0)
            #expect(Self.failure { try LibRawDecoder.decode(noise) }?.description.hasPrefix("LibRaw open: ") == true)
        }
    }

    static func failure(_ body: () throws -> LibRawDecoder.Output) -> LibRawDecoder.Failure? {
        do {
            _ = try body()
            return nil
        } catch {
            return error as? LibRawDecoder.Failure
        }
    }

    // MARK: Decodes at the same time

    /// The app decodes on several threads (`PreviewService`'s lanes, the
    /// export group, the live sessions). Built with `LIBRAW_NOTHREADS`,
    /// LibRaw shares decoder state between instances and concurrent decodes
    /// returned wrong pixels with a success code (code review C1). With the
    /// define put back, this test fails here (8 of its 48 decodes differed),
    /// as do the orientation and inset crop tests running beside it.
    @Test("Decodes of several files at once give the pixels of each file decoded alone")
    func concurrentDecodesMatchSoloDecodes() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            // Different pictures, sizes, orientations and frames; full and half size.
            var jobs: [(url: URL, half: Bool)] = []
            for index in 0..<6 {
                let url = try Self.dng(in: folder, "file-\(index)", width: 256 + 32 * (index % 3), height: 192 + 16 * (index % 2),
                                       seed: UInt64(100 + index), orientation: [1, 6, 8, 3][index % 4],
                                       scene: index == 4 ? .stripes(period: 24) : .pattern,
                                       defaultCrop: index == 5 ? CGRect(x: 8, y: 8, width: 200, height: 160) : nil)
                jobs.append((url, false))
                jobs.append((url, true))
            }
            let alone = try jobs.map { try LibRawDecoder.decode($0.url, halfSize: $0.half).rgba16 }
            #expect(Set(alone).count == alone.count, "the files decode to different pictures")
            for round in 0..<4 {
                let together = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                    for (index, job) in jobs.enumerated() {
                        group.addTask { (index, try LibRawDecoder.decode(job.url, halfSize: job.half).rgba16) }
                    }
                    var results = [Data?](repeating: nil, count: jobs.count)
                    for try await (index, data) in group { results[index] = data }
                    return results
                }
                for (index, data) in together.enumerated() {
                    #expect(data == alone[index], "round \(round): \(jobs[index].url.lastPathComponent), half \(jobs[index].half)")
                }
            }
        }
    }

    /// `LIBRAW_NOTHREADS` makes LibRaw's decoder state process-wide. The
    /// test above shows what that does, but a race need not show on every
    /// run: this keeps the define out of the build whatever the timing.
    @Test("LibRaw is built thread-safe")
    func buildIsThreadSafe() throws {
        let manifest = try String(contentsOf: RepositoryFiles.url("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains("define(\"LIBRAW_NOTHREADS\""))
        #expect(!manifest.contains("-DLIBRAW_NOTHREADS"))
    }
}

/// The fallback to LibRaw and what follows from it: such a raw is a rendered
/// image everywhere, by one test (`SystemRAWDecoder`).
@Suite("LibRaw fallback")
struct LibRawFallbackPipelineTests {
    static func smallDNG(in folder: URL, _ name: String = "small") throws -> URL {
        try LibRawDecoderTests.dng(in: folder, name)
    }

    /// Statistics of a render in the working space.
    static func means(_ image: CIImage) -> SIMD3<Double> {
        let linear = ReferenceTests.renderLinear(image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,
                                                                                         y: -image.extent.minY)))
        var sum = SIMD3<Double>(0, 0, 0)
        for index in stride(from: 0, to: linear.pixels.count, by: 4) {
            sum += SIMD3(Double(linear.pixels[index]), Double(linear.pixels[index + 1]), Double(linear.pixels[index + 2]))
        }
        return sum / Double(linear.width * linear.height)
    }

    /// The bug (issue #161): on macOS 27.2.1 the system's RAW decoder gives
    /// no image for this file, and before the fallback nothing else read it,
    /// so it was `undecodable`: a black loupe and grey tiles. Fails without
    /// the fallback wherever the system decoder does not read the file; where
    /// it does (the premise is printed), the decode is the system's.
    @Test("A raw the system decoder gives no image for is decoded by LibRaw and renders")
    func rawWithoutSystemImageRenders() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.smallDNG(in: folder)
            let systemReads = SystemRAWDecoder.reads(url)
            for longEdge in [nil, 128, 512] as [Int?] {
                let decoded = try PreviewGenerator.decode(url, longEdge: longEdge, draft: false)
                #expect(!decoded.image.extent.isEmpty)
                #expect(decoded.context.isRaw == systemReads)
                guard !systemReads else { continue }
                let libraw = try LibRawDecoder.decode(url, longEdge: longEdge)
                #expect(decoded.image.extent.size == libraw.size)
                #expect(decoded.context.scale == (longEdge == 128 ? 0.5 : 1))
                #expect(decoded.machineLearning == .notRequested)
            }
            let rendered = try PreviewGenerator(engine: ReferenceTests.engine).cgImage(source: url, stack: .identity, longEdge: 200)
            #expect(max(rendered.width, rendered.height) == 200)
            let tiers = try PreviewGenerator(engine: ReferenceTests.engine)
                .jpegData(source: url, stack: .identity, tiers: [.thumbnail, .preview])
            #expect(tiers.count == 2)
            if systemReads { print("LibRawFallbackPipelineTests: the system RAW decoder reads the 256 x 192 DNG here") }
        }
    }

    @Test("One test says which files the system RAW decoder reads, and the raw defaults follow it")
    func oneTestOfWhatIsDecodedAsRaw() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let small = try Self.smallDNG(in: folder)
            let large = try LibRawDecoderTests.dng(in: folder, "large", width: 1536, height: 1152)
            let jpeg = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: jpeg, width: 320, height: 240, seed: 5)
            #expect(SystemRAWDecoder.reads(large), "the system RAW decoder no longer reads the 1536 x 1152 DNG")
            #expect(!SystemRAWDecoder.reads(jpeg))
            #expect(!SystemRAWDecoder.reads(folder.appending(path: "missing.dng")))
            for url in [small, large, jpeg] {
                let reads = SystemRAWDecoder.reads(url)
                #expect((RawDefaults(source: url) != nil) == reads, "\(url.lastPathComponent)")
                #expect(try PreviewGenerator.decode(url, longEdge: nil, draft: false).context.isRaw == reads,
                        "\(url.lastPathComponent)")
                // The stack's own choices never move a file to the other decoder (code review Q6).
                let chosen = RAWDecodeSettings(temperature: 4200, decoderVersion: "no such version", fullFrame: true)
                let decoded = try PreviewGenerator.decode(url, longEdge: 200, draft: false, settings: chosen)
                #expect(decoded.context.isRaw == reads, "\(url.lastPathComponent)")
                #expect((decoded.decoder == .systemRAW) == reads, "\(url.lastPathComponent)")
                #expect(decoded.decoder == (reads ? .systemRAW : url == jpeg ? .imageIO : .libRaw), "\(url.lastPathComponent)")
                var memo = SystemRAWDecoder.Memo(url)
                let remembered = memo.reads()
                #expect(remembered == reads)
                #expect(chosen.choosesTheDecode && !chosen.withoutDecodeChoices.choosesTheDecode)
                #expect(chosen.withoutDecodeChoices.temperature == 4200)
                let asked = RAWDecodeSettings(temperature: 4000, fullFrame: true)
                let reaching = memo.decodeSettings(asked)
                #expect(reaching == (reads ? asked : .none))
            }
            // A caller that knows the answer is not contradicted by the file.
            var known = SystemRAWDecoder.Memo(large, known: false)
            let told = known.reads()
            #expect(!told)
        }
    }

    /// Code review C4: without a size the decode was chosen for the uncropped
    /// target, and a cropped preview had half the resolution the file holds.
    @Test("A raw LibRaw decodes has a size, so a crop decodes large enough")
    func cropDecodesLargeEnough() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.smallDNG(in: folder)
            let size = CGSize(width: LibRawDecoderTests.width, height: LibRawDecoderTests.height)
            #expect(LibRawDecoder.frameSize(url) == size)
            #expect(PreviewGenerator.nativeSize(url) == size)
            // The middle half of the frame, for a target of 96 pixels: twice the decode.
            var cropped = Adjustments()
            cropped.crop = Crop(rect: CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            #expect(generator.decodeLongEdge(url, stack: cropped.editStack, longEdge: 96) == 192)
            #expect(generator.decodeLongEdge(url, stack: .identity, longEdge: 96) == 96)
            // 192 is over half the frame: a full decode, where 96 alone would bin.
            #expect(try LibRawDecoder.decode(url, longEdge: 192).size == size)
            #expect(try LibRawDecoder.decode(url, longEdge: 96).size == CGSize(width: 128, height: 96))
            guard !SystemRAWDecoder.reads(url) else { return }
            // Through the pipeline: the kept half is 128 pixels of the file, enough for 96.
            let image = try generator.image(source: url, stack: cropped.editStack, longEdge: 96)
            #expect(max(image.extent.width, image.extent.height) == 96)
        }
    }

    /// The owner's ruling on what the Adjust tab offers (code review C2, Q3):
    /// a photo LibRaw decoded is adjusted like any rendered image. None of
    /// this depends on the system decoder: LibRaw's image goes to the
    /// renderer as `PreviewGenerator.decode` hands it over (`isRaw` false).
    @Test("The renderer applies white balance, light, noise reduction and sharpening to LibRaw's image")
    func rendererAdjustsTheLibRawImage() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let output = try LibRawDecoder.decode(try Self.smallDNG(in: folder))
            let context = RenderContext(scale: 1, isRaw: false)
            let renderer = AdjustmentRenderer()
            func means(_ edit: (inout Adjustments) -> Void) -> SIMD3<Double> {
                var values = Adjustments()
                edit(&values)
                return Self.means(renderer.render(values, to: output.image, context: context))
            }
            let base = means { _ in }
            #expect(base.x > 0.01 && base.y > 0.01 && base.z > 0.01)
            // Warmer: more red against blue. More magenta: less green.
            let warm = means { $0.whiteBalance = WhiteBalance(preset: .custom, relativeTemperature: 60) }
            #expect(warm.x / warm.z > base.x / base.z * 1.1)
            let magenta = means { $0.whiteBalance = WhiteBalance(preset: .custom, relativeTint: 60) }
            #expect(magenta.y / (magenta.x + magenta.z) < base.y / (base.x + base.z) * 0.97)
            // One stop is a factor of two in linear light.
            let brighter = means { $0.exposure.ev = 1 }
            #expect(abs(brighter.y / base.y - 2) < 0.02)
            let recovered = means { $0.tone.highlights = -80 }
            #expect(recovered.y < base.y)
            let lifted = means { $0.tone.shadows = 60 }
            #expect(lifted.y > base.y)
            // Noise reduction and sharpening change pixels, not the mean: compare the renders.
            func render(_ edit: (inout Adjustments) -> Void) -> [Float] {
                var values = Adjustments()
                edit(&values)
                return ReferenceTests.renderLinear(renderer.render(values, to: output.image, context: context)).pixels
            }
            let plain = render { _ in }
            #expect(render { $0.noiseReduction.luminance = 80 } != plain)
            #expect(render { $0.sharpen.amount = 100 } != plain)
            // As for a JPEG, the decoder's own settings have nothing to act on.
            #expect(render { $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 2500, tint: 60) } == plain)
            #expect(render { $0.decode.look = .flat } == plain)
            #expect(render { $0.noiseReduction.color = 90 } == plain)
        }
    }

    @Test("Auto White Balance gives a raw LibRaw decodes relative values, and one the system reads a Kelvin")
    func autoWhiteBalanceFollowsTheDecoder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let adjuster = AutoAdjuster(generator: PreviewGenerator(engine: ReferenceTests.engine))
            for url in [try Self.smallDNG(in: folder), try LibRawDecoderTests.dng(in: folder, "large", width: 1536, height: 1152)] {
                let balance = try adjuster.whiteBalance(source: url, adjustments: .none)
                #expect(balance.preset == .auto)
                if SystemRAWDecoder.reads(url) {
                    #expect(balance.temperature != nil && balance.tint != nil, "\(url.lastPathComponent)")
                    #expect(balance.relativeTemperature == 0 && balance.relativeTint == 0)
                } else {
                    #expect(balance.temperature == nil && balance.tint == nil, "\(url.lastPathComponent)")
                    #expect((-100...100).contains(balance.relativeTemperature))
                }
                // Exposure measures the rendered image, whichever decoder made it.
                #expect((-4...4).contains(try adjuster.exposure(source: url, adjustments: .none)))
            }
        }
    }

    /// The image `Auto White Balance` searches on is reduced once when the
    /// decode is far larger than what is measured.
    @Test("A large decode is reduced once before it is measured")
    func measuresOnAReducedCopy() {
        let large = CIImage(color: CIColor(red: 0.4, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let reduced = AutoAdjuster.reducedOnce(large, engine: ReferenceTests.engine)
        #expect(max(reduced.extent.width, reduced.extent.height) == CGFloat(AutoAdjuster.measureSize))
        let small = large.cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(AutoAdjuster.reducedOnce(small, engine: ReferenceTests.engine).extent == small.extent)
    }

    /// Code review C3: the stack's decode settings keyed the decode, so every
    /// change of one decoded the file again with LibRaw for the same image.
    @Test("Changing a decode setting does not decode a LibRaw photo again")
    func decodeSettingsDoNotDecodeAgain() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.smallDNG(in: folder)
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            // The keying, whatever this macOS reads: told that the system does not decode the file.
            for known in [false, nil] as [Bool?] {
                if known == nil, SystemRAWDecoder.reads(url) { continue }
                let session = LiveRenderSession(source: url, generator: generator, longEdge: 200, colorSpace: nil,
                                                systemDecodesRaw: known)
                var values = Adjustments()
                _ = try await session.render(values)
                #expect(await session.decodeCount == 1)
                values.whiteBalance = WhiteBalance(preset: .custom, temperature: 3000, tint: 20)
                _ = try await session.render(values)
                values.decode.look = .flat
                values.noiseReduction = NoiseReduction(luminance: 60, color: 40)
                _ = try await session.render(values)
                // Exposure below 0 asks a raw for extended range, a mask or crop for the whole sensor.
                values.exposure.ev = -1
                values.tone.highlights = -50
                values.crop = Crop(rect: CropRect(x: 0, y: 0, width: 0.9, height: 0.9))
                _ = try await session.render(values)
                #expect(await session.decodeCount == 1, "known \(String(describing: known))")
            }
            // LibRaw decodes at two sizes and has no draft mode: a draft and a full request it
            // answers with the same half-size decode share one, and a crop that needs more than
            // half the frame decodes once more, in full.
            if !SystemRAWDecoder.reads(url) {
                let session = LiveRenderSession(source: url, generator: generator, longEdge: 100, colorSpace: nil)
                var edited = Adjustments()
                edited.exposure.ev = 0.5
                _ = try await session.render(edited, interactive: true)
                let whole = try await session.render(edited)
                #expect(whole.maskFrameSize == CGSize(width: 128, height: 96))
                edited.crop = Crop(rect: CropRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
                _ = try await session.render(edited)
                #expect(await session.decodeCount == 1)
                edited.crop = Crop(rect: CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
                let cropped = try await session.render(edited)
                #expect(await session.decodeCount == 2)
                #expect(cropped.maskFrameSize == CGSize(width: 256, height: 192))
            }
            // Only an image LibRaw made is kept that way (code review Q6): a session that
            // expects LibRaw of a file another decoder then answers for keeps one decode
            // per request, so a small draft never stands in for the frame after it.
            let large = try LibRawDecoderTests.dng(in: folder, "large", width: 1024, height: 768)
            if SystemRAWDecoder.reads(large) {
                let session = LiveRenderSession(source: large, generator: generator, longEdge: 400, colorSpace: nil,
                                                systemDecodesRaw: false)
                var edited = Adjustments()
                edited.exposure.ev = 0.5
                let draft = try await session.render(edited, interactive: true)
                #expect(max(draft.maskFrameSize.width, draft.maskFrameSize.height) < 400)
                let final = try await session.render(edited)
                #expect(await session.decodeCount == 2)
                #expect(max(final.maskFrameSize.width, final.maskFrameSize.height) >= 400)
                #expect(max(final.image.cgImage.width, final.image.cgImage.height) == 400)
            }
            // The 100% renderer holds one decode for every such change.
            let region = LiveRegionRenderer(source: url, generator: generator, colorSpace: nil, systemDecodesRaw: false)
            var values = Adjustments()
            try await region.prepare(values)
            #expect(await region.isReady(for: values))
            values.whiteBalance = WhiteBalance(preset: .custom, temperature: 3000, tint: 20)
            values.exposure.ev = -1
            values.noiseReduction = NoiseReduction(luminance: 60, color: 40)
            #expect(await region.isReady(for: values))
            #expect(await !region.shouldDecode(whileMoving: values))
        }
    }

    /// Code review Q6 and C16: which decoder a raw gets is one test, so a raw
    /// the system decoder reads as an untouched photo is never handed to
    /// LibRaw because one of the stack's own decoder choices left the system
    /// decoder without an image. No file here takes that path; the order is
    /// tested on its own.
    @Test("A raw goes to LibRaw only when the system decoder has no image without the stack's decoder choices either")
    func decoderOrder() {
        var asked: [RAWDecodeSettings] = []
        var librawAsked = 0, dropped = 0
        func run(_ settings: RAWDecodeSettings, system: @escaping (RAWDecodeSettings) -> String?) -> String? {
            asked = []
            librawAsked = 0
            dropped = 0
            return PreviewGenerator.rawImage(settings: settings, system: { asked.append($0); return system($0) },
                                             libRaw: { librawAsked += 1; return "libraw" }, droppedChoices: { dropped += 1 })
        }
        let plain = RAWDecodeSettings(temperature: 4000)
        let chosen = RAWDecodeSettings(temperature: 4000, decoderVersion: "7", fullFrame: true)
        // The system decoder has an image: nothing else is asked.
        #expect(run(chosen) { _ in "system" } == "system")
        #expect(asked == [chosen] && librawAsked == 0 && dropped == 0)
        // No image with the stack's choices, one without them: the system's, with the stack's values kept.
        #expect(run(chosen) { $0.choosesTheDecode ? nil : "system" } == "system")
        #expect(asked == [chosen, chosen.withoutDecodeChoices] && librawAsked == 0 && dropped == 1)
        #expect(chosen.withoutDecodeChoices == plain)
        // No image either way: LibRaw.
        #expect(run(chosen) { _ in nil } == "libraw")
        #expect(asked.count == 2 && librawAsked == 1 && dropped == 0)
        // Without choices there is nothing to drop: the system decoder is asked once.
        #expect(run(plain) { _ in nil } == "libraw")
        #expect(asked == [plain] && librawAsked == 1)
        // Neither decoder has an image.
        #expect(PreviewGenerator.rawImage(settings: plain, system: { _ in String?.none }, libRaw: { nil }) == nil)
    }

    /// Code review C7: the reason was overwritten with "failed", for a file
    /// the system decoder does not read at all. Design review F3: the reason
    /// is the camera on every macOS, never "this Mac needs macOS 27": machine
    /// learning is the system decoder's, and it does not read this file.
    @Test("Machine learning asked of a raw LibRaw decodes is not applied because of the camera")
    func machineLearningReasonIsTheCamera() async throws {
        #expect(MachineLearningNoiseReduction.reasonWithoutSystemDecoder == .cameraNotSupported)
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.smallDNG(in: folder)
            guard !SystemRAWDecoder.reads(url) else { return }
            let decoded = try PreviewGenerator.decode(url, longEdge: nil, draft: false,
                                                      settings: RAWDecodeSettings(machineLearning: true))
            #expect(decoded.machineLearning == .notApplied(.cameraNotSupported))
            // The inspector's state for it, asked for or not (ml-denoise S6 and S4).
            let asked = MachineLearningNoiseReduction.Status(asks: true, groupIsOn: true, availability: .cameraNotSupported)
            #expect(asked.state == .notApplied(.cameraNotSupported))
            #expect(asked.checkBoxIsEnabled)
            let notAsked = MachineLearningNoiseReduction.Status(asks: false, groupIsOn: true, availability: .cameraNotSupported)
            #expect(notAsked.state == .unavailable(.cameraNotSupported))
            #expect(!notAsked.checkBoxIsEnabled)
        }
    }

    /// Design review F2 and D5 (code review C14): the Mode pop-up of a file
    /// that is not decoded as a raw offers As Shot, Auto and Custom. A stored
    /// mode that is one of them, with no Kelvin values, is shown as it is, so
    /// a mode picked from the pop-up sticks. Any other (a paste or preset from
    /// a raw the system decodes) left a stale item; it shows what renders.
    /// The stored values are not rewritten.
    @Test("The white balance mode shown for a rendered image is the stored one, or for a pasted raw mode the one that renders")
    func relativeModeShown() {
        // D5's four cases.
        // 1. Custom chosen with both sliders at 0 stays Custom.
        #expect(WhiteBalance(preset: .custom).relativeDisplayPreset == .custom)
        // 2. A pasted Daylight at 0/0 renders as shot.
        #expect(WhiteBalance.raw(.daylight).relativeDisplayPreset == .asShot)
        // 3. A pasted Custom with Kelvin values and a relative value renders that value.
        #expect(WhiteBalance(preset: .custom, temperature: 2500, tint: 60, relativeTemperature: 30).relativeDisplayPreset == .custom)
        // 4. The relative Auto (no Kelvin values) is Auto, whatever it measured.
        #expect(WhiteBalance(preset: .auto, relativeTemperature: 16, relativeTint: -22).relativeDisplayPreset == .auto)
        #expect(WhiteBalance(preset: .auto).relativeDisplayPreset == .auto)

        // Rule 1: the three offered modes without Kelvin values, whatever the relative values.
        #expect(WhiteBalance().relativeDisplayPreset == .asShot)
        #expect(WhiteBalance(preset: .custom, relativeTemperature: 30).relativeDisplayPreset == .custom)
        #expect(WhiteBalance(preset: .custom, relativeTint: -5).relativeDisplayPreset == .custom)
        // Rule 2: Kelvin values (either one) or a mode that is not offered.
        #expect(WhiteBalance(preset: .custom, temperature: 2500, tint: 60).relativeDisplayPreset == .asShot)
        #expect(WhiteBalance(preset: .custom, tint: 10).relativeDisplayPreset == .asShot)
        // A raw's Auto pasted here carries a Kelvin and renders as shot.
        #expect(WhiteBalance(preset: .auto, temperature: 5886, tint: 7).relativeDisplayPreset == .asShot)
        #expect(WhiteBalance(preset: .auto, temperature: 5886, tint: 7, relativeTint: 4).relativeDisplayPreset == .custom)
        #expect(WhiteBalance(preset: .tungsten, temperature: 2850, tint: 0, relativeTemperature: 10).relativeDisplayPreset == .custom)
        #expect(WhiteBalance(preset: .shade).relativeDisplayPreset == .asShot)
        // Always one of the three offered.
        let offered = WhiteBalance.Preset.relativePresets
        for preset in WhiteBalance.Preset.allCases {
            #expect(offered.contains(WhiteBalance.raw(preset).relativeDisplayPreset), "\(preset)")
            #expect(offered.contains(WhiteBalance(preset: preset, relativeTint: 3).relativeDisplayPreset), "\(preset)")
        }
        // Display only: the stack keeps what was pasted.
        let pasted = WhiteBalance.raw(.daylight)
        _ = pasted.relativeDisplayPreset
        #expect(pasted.preset == .daylight && pasted.temperature == 5500)
    }
}
