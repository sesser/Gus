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
                    orientation: Int = 1, scene: SyntheticDNG.Scene = .pattern, defaultCrop: CGRect? = nil,
                    mosaic: Data? = nil) throws -> URL {
        let url = folder.appending(path: "\(name).dng")
        try SyntheticDNG.write(to: url, options: .init(width: width, height: height, seed: seed, orientation: orientation,
                                                       scene: scene, defaultCrop: defaultCrop), mosaic: mosaic)
        return url
    }

    /// One picture's mosaic, drawn once. Tests that compare the decodes of
    /// two files holding the same picture (another orientation, another
    /// crop) write both from it: the scene's drawing is Core Graphics', and
    /// two drawings of one scene are not always the same bytes when other
    /// drawings run at the same time (`SyntheticDNG.mosaic(options:)`; code
    /// review C2: such tests failed 7 times in 80 runs under load, each
    /// reading as a decoder race that was not one).
    static func mosaic(width: Int = width, height: Int = height, seed: UInt64 = 7,
                       scene: SyntheticDNG.Scene = .pattern) throws -> Data {
        try SyntheticDNG.mosaic(options: .init(width: width, height: height, seed: seed, scene: scene))
    }

    /// The decode's samples, four to a pixel, rows from the top.
    /// The decode as it is shown (cropped, oriented, framed), four values to
    /// a pixel on LibRaw's 16-bit scale (1 is 65535), whichever demosaic made
    /// it. Rendered in the app's half-float working format: exact for our
    /// demosaic's half floats; LibRaw's 16-bit values are rounded to half
    /// float, the same way every time.
    static func samples(_ output: LibRawDecoder.Output) -> [Float] {
        ReferenceTests.renderLinear(output.linear).pixels.map { (value: Float) -> Float in value * 65535 }
    }

    /// One pixel's red, green and blue.
    static func pixel(_ samples: [Float], width: Int, x: Int, y: Int) -> [Float] {
        Array(samples[((y * width + x) * 4)..<((y * width + x) * 4 + 3)])
    }

    // MARK: The decode

    /// The mosaic holds linear values at 0.85 of the white level
    /// (`SyntheticDNG.mosaic`) and the camera's as-shot neutral is 1, 1, 1,
    /// so LibRaw's multipliers are all 1: the decode, camera RGB before the
    /// color step, keeps a grey grey and at the file's level, linear, with no
    /// brightening. The white level is the file's whatever the picture holds
    /// (`whiteLevelIsTheFiles`).
    @Test("A decode is linear camera RGB, balanced for the camera's white, at the file's level")
    func decodeIsLinearAndNeutral() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.dng(in: folder, "stripes", scene: .stripes(period: 64))
            let output = try LibRawDecoder.decode(url)
            #expect(output.size == CGSize(width: Self.width, height: Self.height))
            #expect(output.fullSize == output.size)
            #expect(output.linear.extent == CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
            #expect(output.cameraMake == "Synthetic")
            // The file's color data is usable: the decode is in camera RGB, and the color step
            // counts a channel as saturated at `whiteMargin` of the white level.
            #expect(output.step.color != nil)
            #expect(output.step.channelScale == SIMD3(repeating: LibRawDecoder.whiteMargin))
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
                    // 1%: the 8-bit table's rounding and LibRaw's 16-bit arithmetic.
                    #expect(abs(value - expected) <= expected * 0.01, "x \(x): \(rgb) against \(expected)")
                }
            }
            // Opaque.
            #expect(samples[3] == 65535)
            // Through the color step without a look the camera (sRGB's primaries, under D65) is
            // converted to the working space: a grey stays grey, 1 / 0.99 as bright (the margin).
            var transform = output.step.transform(temperature: nil, tint: nil)
            transform.exposure = 1
            transform.toneCurve = nil
            let rendered = ReferenceTests.renderLinear(transform.apply(to: output.linear))
            for (x, expected) in [(32, linear(64)), (96, linear(191))] {
                let pixel = rendered[x, Self.height / 2]
                for value in [pixel.x, pixel.y, pixel.z] {
                    #expect(abs(Double(value) - expected / 65535 / LibRawDecoder.whiteMargin) <= expected / 65535 * 0.012,
                            "x \(x): \(pixel)")
                }
            }
        }
    }

    /// Issue #170, R7 and AC7 (#161's requirements issue R2). LibRaw's
    /// default takes the brightest value in the frame as white when it is
    /// over three quarters of the file's white level, so two frames of one
    /// scene, or a crop of a frame, decoded up to 0.4 EV apart. Here one
    /// mosaic is decoded whole (its bar code is white: 0.85 of the white
    /// level, the brightest value it holds) and through a default crop that
    /// leaves the brightest parts out. With LibRaw's default on, the crop's
    /// white is its own brightest value and its pixels come out brighter.
    @Test("A decode's level is the file's white level, whatever the frame holds")
    func whiteLevelIsTheFiles() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let mosaic = try Self.mosaic(seed: .max)
            let whole = try LibRawDecoder.decode(try Self.dng(in: folder, "whole", seed: .max, mosaic: mosaic))
            let all = Self.samples(whole)
            var brightest: Float = 0
            for i in stride(from: 0, to: all.count, by: 4) { brightest = max(brightest, all[i], all[i + 1], all[i + 2]) }
            // A window of the mosaic whose brightest value is well under the whole picture's.
            let size = 64
            var crop: CGRect?, cropBrightest: Float = 0
            search: for top in stride(from: 8, through: Self.height - size - 8, by: 8) {
                for left in stride(from: 8, through: Self.width - size - 8, by: 8) {
                    var highest: Float = 0
                    for y in top..<(top + size) {
                        for x in left..<(left + size) {
                            highest = max(highest, Self.pixel(all, width: Self.width, x: x, y: y).max() ?? 0)
                        }
                    }
                    if Double(highest) < 0.9 * Double(brightest) {
                        (crop, cropBrightest) = (CGRect(x: left, y: top, width: size, height: size), highest)
                        break search
                    }
                }
            }
            let window = try #require(crop, "no part of the picture is without its brightest values")
            // The whole picture's brightest value is over three quarters of the white level: LibRaw's default acts on it.
            #expect(Double(brightest) > 0.75 * 65535 && cropBrightest < brightest)
            let cropped = try LibRawDecoder.decode(try Self.dng(in: folder, "cropped", seed: .max, defaultCrop: window,
                                                                mosaic: mosaic))
            #expect(cropped.size == window.size)
            let part = Self.samples(cropped)
            var differing = 0
            let border = 8
            for y in border..<(size - border) {
                for x in border..<(size - border)
                where Self.pixel(part, width: size, x: x, y: y)
                    != Self.pixel(all, width: Self.width, x: x + Int(window.minX), y: y + Int(window.minY)) {
                    differing += 1
                }
            }
            // The same pixels at the same level: with LibRaw's default, every one of them is brighter in the crop.
            #expect(differing == 0)
        }
    }

    /// LibRaw applies the file's orientation; each oriented pixel is the
    /// stored pixel the orientation's definition names. All seven that are
    /// not upright: the mirrored quarter turns (5 and 7) swap width and height
    /// as the plain ones (6 and 8) do (code review C13).
    @Test("A decode is oriented as the file says", arguments: [2, 3, 4, 5, 6, 7, 8])
    func decodeIsOriented(orientation: Int) async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let mosaic = try Self.mosaic()
            let upright = try LibRawDecoder.decode(try Self.dng(in: folder, "upright", mosaic: mosaic))
            let turnedURL = try Self.dng(in: folder, "turned", orientation: orientation, mosaic: mosaic)
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
            #expect(half.pixels.width == 128 && half.pixels.height == 96)
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
    @Test("A file's inset crop is the frame of its decode")
    func insetCropIsDecoded() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let crop = CGRect(x: 16, y: 20, width: 224, height: 168)
            let mosaic = try Self.mosaic(seed: .max)
            let whole = try LibRawDecoder.decode(try Self.dng(in: folder, "whole", seed: .max, mosaic: mosaic))
            let croppedURL = try Self.dng(in: folder, "cropped", seed: .max, defaultCrop: crop, mosaic: mosaic)
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
            let alone = try jobs.map { try LibRawDecoder.decode($0.url, halfSize: $0.half).pixels.data }
            #expect(Set(alone).count == alone.count, "the files decode to different pictures")
            for round in 0..<4 {
                let together = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                    for (index, job) in jobs.enumerated() {
                        group.addTask { (index, try LibRawDecoder.decode(job.url, halfSize: job.half).pixels.data) }
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
                // What reaches the decode: everything for the system decoder, the white balance
                // for LibRaw's color step, nothing for a file that is not a raw. What a new
                // decode is needed for: the system decoder's settings only.
                let asked = RAWDecodeSettings(temperature: 4000, tint: 12, boostAmount: 0.5, fullFrame: true)
                let reaching = memo.decodeSettings(asked)
                #expect(reaching == (reads ? asked : url == jpeg ? .none : RAWDecodeSettings(temperature: 4000, tint: 12)))
                let keyed = memo.decodeKey(asked)
                #expect(keyed == (reads ? asked : .none))
                #expect(SystemRAWDecoder.settings(asked, reaching: url, systemReads: reads) == reaching)
                // The renderer is told the decode applied the white balance for a raw by either decoder.
                #expect(decoded.context.balancedByDecoder == (url != jpeg), "\(url.lastPathComponent)")
                #expect((decoded.camera != nil) == (decoded.decoder == .libRaw), "\(url.lastPathComponent)")
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

    /// What reaches a photo LibRaw decoded (issue #161's code review C2 and
    /// Q3, then issue #170): the stack's Kelvin and tint, in the color step
    /// of its decode; the renderer's light, noise reduction and sharpening.
    /// Not the relative Temperature and Tint, which are for files that are
    /// not raw, nor the system decoder's profile and color noise reduction.
    /// None of this depends on the system decoder: the image goes to the
    /// renderer as `PreviewGenerator.decode` hands it over.
    @Test("A LibRaw photo takes the stack's Kelvin white balance, and the renderer's light, noise reduction and sharpening")
    func rendererAdjustsTheLibRawImage() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try Self.smallDNG(in: folder)
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            let systemReads = SystemRAWDecoder.reads(url)
            /// The render as the pipeline makes it, forced through LibRaw where the system decoder reads the file.
            func rendering(_ values: Adjustments) throws -> CIImage {
                if !systemReads { return try generator.image(source: url, stack: values.editStack, longEdge: nil) }
                let output = try LibRawDecoder.decode(url)
                let image = output.step.apply(to: output.linear, settings: values.decodeSettings)
                return AdjustmentRenderer().render(values, to: image, context: RenderContext(isRaw: false, balancedByDecoder: true))
            }
            func means(_ edit: (inout Adjustments) -> Void) throws -> SIMD3<Double> {
                var values = Adjustments()
                edit(&values)
                return Self.means(try rendering(values))
            }
            let base = try means { _ in }
            #expect(base.x > 0.01 && base.y > 0.01 && base.z > 0.01)
            // A lower Kelvin says the light was warmer, so the picture is rendered cooler: less red against blue.
            let tungsten = try means { $0.whiteBalance = .raw(.tungsten) }
            #expect(tungsten.x / tungsten.z < base.x / base.z * 0.8)
            let shade = try means { $0.whiteBalance = .raw(.shade) }
            #expect(shade.x / shade.z > base.x / base.z * 1.02)
            // A higher tint says the light was greener, so the picture is rendered more magenta: less green.
            let magenta = try means { $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 6500, tint: 80) }
            let neutral = try means { $0.whiteBalance = WhiteBalance(preset: .custom, temperature: 6500, tint: 0) }
            #expect(magenta.y / (magenta.x + magenta.z) < neutral.y / (neutral.x + neutral.z) * 0.97)
            // One stop is a factor of two in linear light.
            let brighter = try means { $0.exposure.ev = 1 }
            #expect(abs(brighter.y / base.y - 2) < 0.02)
            let recovered = try means { $0.tone.highlights = -80 }
            #expect(recovered.y < base.y)
            let lifted = try means { $0.tone.shadows = 60 }
            #expect(lifted.y > base.y)
            // Noise reduction and sharpening change pixels, not the mean: compare the renders.
            func render(_ edit: (inout Adjustments) -> Void) throws -> [Float] {
                var values = Adjustments()
                edit(&values)
                let image = try rendering(values)
                return ReferenceTests.renderLinear(image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,
                                                                                           y: -image.extent.minY))).pixels
            }
            let plain = try render { _ in }
            #expect(try render { $0.noiseReduction.luminance = 80 } != plain)
            #expect(try render { $0.sharpen.amount = 100 } != plain)
            // The relative values never render on a raw (R10): they stay in the stack and it renders as shot.
            #expect(try render { $0.whiteBalance = WhiteBalance(preset: .custom, relativeTemperature: 60, relativeTint: 30) } == plain)
            // The system decoder's own settings have nothing to act on.
            #expect(try render { $0.decode.storedLook = "flat" } == plain)
            #expect(try render { $0.noiseReduction.color = 90 } == plain)
            // A white balance that is turned off is not applied.
            #expect(try render {
                $0.whiteBalance = .raw(.tungsten)
                $0.setEnabled(.whiteBalance, false)
            } == plain)
        }
    }

    /// Issue #170, AC3: Auto stores a Kelvin and tint for a raw whichever
    /// decoder reads it, never the relative values.
    @Test("Auto White Balance gives a raw a Kelvin and tint by either decoder")
    func autoWhiteBalanceFollowsTheDecoder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let adjuster = AutoAdjuster(generator: PreviewGenerator(engine: ReferenceTests.engine))
            for url in [try Self.smallDNG(in: folder), try LibRawDecoderTests.dng(in: folder, "large", width: 1536, height: 1152)] {
                let balance = try adjuster.whiteBalance(source: url, adjustments: .none)
                #expect(balance.preset == .auto)
                let kelvin = try #require(balance.temperature, "\(url.lastPathComponent)")
                let tint = try #require(balance.tint, "\(url.lastPathComponent)")
                #expect(WhiteBalance.temperatureRange.contains(kelvin) && WhiteBalance.tintRange.contains(tint))
                #expect(kelvin == kelvin.rounded() && tint == tint.rounded())
                #expect(balance.relativeTemperature == 0 && balance.relativeTint == 0)
                #expect(balance.kelvinDisplayPreset == .auto)
                // Exposure measures the rendered image, whichever decoder made it.
                #expect((-4...4).contains(try adjuster.exposure(source: url, adjustments: .none)))
            }
            // A grey picture (stripes of two greys) from a camera with sRGB's primaries whose
            // as-shot neutral is off: every photosite holds the same value in the three colors, so
            // the light that makes the picture neutral is the one whose camera neutral is 1, 1, 1,
            // which for this camera is D65 (6504 K; its tint is +10, the D series lying that far
            // from the black body's colors). Forced through LibRaw's color step whatever this macOS reads.
            let cast = folder.appending(path: "cast.dng")
            try SyntheticDNG.write(to: cast, options: .init(width: LibRawDecoderTests.width, height: LibRawDecoderTests.height, seed: 21,
                                                            scene: .stripes(period: 16),
                                                            color: .init(matrix1: SyntheticDNG.Color.sRGBMatrix,
                                                                         asShotNeutral: [0.9, 1, 0.8])))
            let output = try LibRawDecoder.decode(cast, halfSize: true)
            func imbalance(_ balance: ColorTemperature?) throws -> Double {
                let sample = try #require(PixelSample(output.image(whiteBalance: balance), engine: ReferenceTests.engine)?.neutralAverage())
                return abs(log(sample.z / sample.x)) + abs(log(sample.y / (sample.x * sample.z).squareRoot()))
            }
            // As shot the greys have a cast (0.14 here, after the look's tone curve); at D65 they have none.
            #expect(try imbalance(nil) > 0.1)
            #expect(try imbalance(ColorTemperature(kelvin: 6504, tint: 10)) < 0.01)
            if !SystemRAWDecoder.reads(cast) {
                let measured = try adjuster.whiteBalance(source: cast, adjustments: .none)
                let kelvin = try #require(measured.temperature), tint = try #require(measured.tint)
                // The search stops within half a percent of neutral in each direction: about 1% in Kelvin, 2 of tint.
                #expect(abs(kelvin / 6504 - 1) < 0.02, "\(kelvin) K")
                #expect(abs(tint - 10) < 3, "tint \(tint)")
                #expect(try imbalance(ColorTemperature(kelvin: kelvin, tint: tint)) < 0.02)
            }
            // A file that is not a raw still gets relative values.
            let jpeg = folder.appending(path: "photo.jpg")
            try SyntheticImages.writeJPEG(to: jpeg, width: 320, height: 240, seed: 5)
            let relative = try adjuster.whiteBalance(source: jpeg, adjustments: .none)
            #expect(relative.preset == .auto && relative.temperature == nil && relative.tint == nil)
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
                let asShot = try await session.linearFrame(values)
                values.whiteBalance = WhiteBalance(preset: .custom, temperature: 3000, tint: 20)
                _ = try await session.render(values)
                // The white balance is applied after the kept decode: the frame changes, the count does not.
                let balanced = try await session.linearFrame(values)
                #expect(balanced.dataProvider?.data as Data? != asShot.dataProvider?.data as Data?, "known \(String(describing: known))")
                values.decode.storedLook = "flat"
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
            // And its frames follow the white balance (design §4, live feedback at 100%).
            if !SystemRAWDecoder.reads(url) {
                let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
                let cool = try await region.render(values, unit: whole)
                values.whiteBalance = WhiteBalance(preset: .custom, temperature: 9000, tint: 20)
                #expect(await region.isReady(for: values))
                let warm = try await region.render(values, unit: whole)
                #expect(cool.image.cgImage.dataProvider?.data as Data? != warm.image.cgImage.dataProvider?.data as Data?)
            }
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
    /// that is not a raw offers As Shot, Auto and Custom. (A raw LibRaw
    /// decodes has had the raws' own rule since issue #170: `kelvinModeShown`.) A stored
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
