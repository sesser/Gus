import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Synchronization
import Testing
@testable import PhotoCore

/// The left and right edges of a rendered photo, where a RAW decode whose
/// lens correction was given too little of the image repeats its outermost
/// pixels outward: every row of a band is then one color
/// (docs/features/raw-edge-smear/status.md).
struct EdgeBands {
    /// Share of the width each band takes. The smear seen was 3.7% a side.
    static let share = 0.02

    let width: Int
    let height: Int
    /// 8-bit RGBA rows of the image.
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.displayP3),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    init?(jpeg data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image)
    }

    var band: Int { max(4, Int((Double(width) * Self.share).rounded())) }

    /// The columns of the left and the right band.
    private var columns: [Range<Int>] { [0..<band, (width - band)..<width] }

    /// The share of band rows (left and right counted apart) whose pixels all
    /// lie within `tolerance` levels of the row's outermost pixel. A photo has
    /// some (a clear sky); a smeared edge is nothing else.
    func constantRowShare(tolerance: Int = 2) -> Double {
        var constant = 0
        for columns in columns {
            let outermost = columns.lowerBound == 0 ? 0 : width - 1
            for y in 0..<height {
                let reference = (y * width + outermost) * 4
                let isConstant = columns.allSatisfy { x in
                    let pixel = (y * width + x) * 4
                    return (0..<3).allSatisfy { abs(Int(bytes[pixel + $0]) - Int(bytes[reference + $0])) <= tolerance }
                }
                if isConstant { constant += 1 }
            }
        }
        return Double(constant) / Double(height * 2)
    }

    /// Mean difference in levels between the bands of two renders of one photo.
    func meanDifference(from other: EdgeBands) -> Double {
        guard other.width == width, other.height == height else { return .infinity }
        var sum = 0
        var count = 0
        for columns in columns {
            for y in 0..<height {
                for x in columns {
                    let pixel = (y * width + x) * 4
                    for channel in 0..<3 {
                        sum += abs(Int(bytes[pixel + channel]) - Int(other.bytes[pixel + channel]))
                        count += 1
                    }
                }
            }
        }
        return Double(sum) / Double(count)
    }
}

@Suite("Edge bands")
struct EdgeBandTests {
    /// A 200 × 40 gradient that changes with x, and the same with its outer
    /// 5% a side replaced by the pixel next to them, as the smear does.
    static func image(smeared: Bool) -> CGImage {
        let width = 200, height = 40, margin = 10
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let source = smeared ? min(max(x, margin), width - 1 - margin) : x
                let value = UInt8((source * 7 + y * 3) % 256)
                bytes[(y * width + x) * 4] = value
                bytes[(y * width + x) * 4 + 1] = value
                bytes[(y * width + x) * 4 + 2] = value
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.displayP3)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    @Test("Repeated edge columns are found, and a photo's own edges are not")
    func findsRepeatedColumns() throws {
        let clean = try #require(EdgeBands(Self.image(smeared: false)))
        let smeared = try #require(EdgeBands(Self.image(smeared: true)))
        #expect(clean.band == 4)
        #expect(clean.constantRowShare() == 0)
        #expect(smeared.constantRowShare() == 1)
        #expect(clean.meanDifference(from: clean) == 0)
        #expect(smeared.meanDifference(from: clean) > 10)
    }
}

/// Every RAW decode has a render graph of its own (`RAWDecodeGraph` says why
/// and what that rests on). Whether that stops the fault only real camera
/// files can show (`RAWEdgeSmearTests`); these check the parts that need
/// none: the keys, that keying changes no pixel, and that no RAW filter is
/// made where its image could be rendered without a key.
@Suite("RAW decode graphs")
struct RAWDecodeGraphTests {
    typealias Key = RAWDecodeGraph.Key

    /// One of red, green, blue and alpha (0 … 3) of RGBA pixels.
    static func channel(_ index: Int, of pixels: [Float]) -> [Float] {
        stride(from: index, to: pixels.count, by: 4).map { pixels[$0] }
    }

    @Test("Every serial has bounds of its own, far beyond any pixel and finite")
    func keysDiffer() {
        // The first decodes, both sides of the first digit's carry, and large serials.
        let carry: UInt64 = 1 << 22
        let first: [UInt64] = (1...5000).map { UInt64($0) }
        let large: [UInt64] = [carry - 1, carry, carry + 1, 2 * carry, 5000 * carry + 17, (1 << 44) - 1]
        let serials = first + large
        let keys = serials.map { Key(serial: $0) }
        #expect(Set(keys).count == serials.count)
        for key in keys {
            #expect(key.low.isFinite && key.high.isFinite)
            #expect(key.low >= Key.base && key.high >= Key.base)
            #expect(key.low < 4e30 && key.high < 4e30)
        }
        // Neighbours differ in the argument itself, not past a Float's precision.
        #expect(Key(serial: 1).low != Key(serial: 2).low)
        #expect(Key(serial: carry).high != Key(serial: 2 * carry).high)
    }

    @Test("Decodes at the same time get different keys")
    func keysAreNotSharedAcrossThreads() {
        let keys = Mutex<[Key]>([])
        DispatchQueue.concurrentPerform(iterations: 2000) { _ in
            let key = RAWDecodeGraph.nextKey()
            keys.withLock { $0.append(key) }
        }
        #expect(Set(keys.withLock { $0 }).count == 2000)
    }

    /// The clamp passes values through. What comes before it may be compiled
    /// differently with it there, which moved values of real raws by one unit
    /// in the last place (status.md, "C1"): two are allowed, below and above
    /// white (the second input is four times the first).
    @Test("A keyed image has the pixels and the extent it had", arguments: [0.0, 2.0])
    func keyingChangesNoPixel(ev: Double) {
        // Bounds low enough to see are the ones applied: `low` to red and
        // blue, `high` to green and alpha. (The clamp works on values that are
        // not premultiplied, so a clamped alpha scales the rest: only alpha
        // is read for `high`.)
        let scene = TestScene.patchChart.image()
        let low = ReferenceTests.renderLinear(RAWDecodeGraph.keyed(scene.ciImage, with: Key(low: 0.25, high: 4))).pixels
        #expect((Self.channel(0, of: scene.pixels).max() ?? 0) > 0.5 && (Self.channel(2, of: scene.pixels).max() ?? 0) > 0.5)
        #expect(Self.channel(0, of: low).max() == 0.25 && Self.channel(2, of: low).max() == 0.25)
        #expect(Self.channel(1, of: low).max() == Self.channel(1, of: scene.pixels).max())
        let high = ReferenceTests.renderLinear(RAWDecodeGraph.keyed(scene.ciImage, with: Key(low: 4, high: 0.5))).pixels
        #expect(Self.channel(3, of: high).max() == 0.5)


        var input = TestScene.patchChart.image().ciImage
        if ev != 0 {
            input = input.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
        }
        let keyed = RAWDecodeGraph.keyed(input, with: Key(serial: 12_345_678))
        #expect(keyed.extent == input.extent)
        let plain = ReferenceTests.renderLinear(input).pixels
        let pixels = ReferenceTests.renderLinear(keyed).pixels
        #expect(pixels.count == plain.count && !plain.isEmpty)
        #expect((plain.max() ?? 0) > (ev == 0 ? 0.5 : 2), "the scene has nothing bright to clamp")
        let worst = zip(plain, pixels).map { abs($0 - $1) - 2 * max(abs($0), 0x1p-24).ulp }.max() ?? 0
        #expect(worst <= 0, "beyond two units in the last place by \(worst)")

        let empty = CIImage.empty()
        #expect(RAWDecodeGraph.keyed(empty, with: Key(serial: 1)).extent.isEmpty)
    }

    /// With a real key the clamp cannot be seen in the pixels, so the last
    /// part passes bounds low enough to see: the decoder's image is clamped
    /// to the key it is given.
    @Test("The RAW decoder's image comes keyed and is still the photo")
    func decoderOutputIsKeyed() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let dng = folder.appending(path: "photo.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 1200, height: 800, seed: 5))
            let raw = try #require(CIRAWFilter(imageURL: dng))
            let plain = try #require(raw.outputImage)
            let keyed = try #require(RAWDecodeGraph.output(of: raw))
            #expect(keyed.extent == plain.extent)
            let a = ReferenceTests.renderLinear(plain).pixels, b = ReferenceTests.renderLinear(keyed).pixels
            let worst = zip(a, b).map { abs($0 - $1) - 2 * max(abs($0), 0x1p-24).ulp }.max() ?? 0
            #expect(worst <= 0, "beyond two units in the last place by \(worst)")

            let reds = Self.channel(0, of: a)
            #expect((reds.max() ?? 0) > 0.5, "the scene has nothing bright to clamp")
            let visible = try #require(RAWDecodeGraph.output(of: raw, key: Key(low: 0.25, high: 4)))
            let clamped = ReferenceTests.renderLinear(visible).pixels
            #expect(Self.channel(0, of: clamped).max() == 0.25, "the image was not clamped to its key")
            #expect(Self.channel(1, of: clamped).max() == Self.channel(1, of: a).max())

            let decoded = try PreviewGenerator.decode(dng, longEdge: nil, draft: false)
            #expect(decoded.context.isRaw, "the RAW decoder no longer decodes the synthetic DNG")
            #expect(decoded.image.extent == plain.extent)
        }
    }

    /// A tripwire, not a proof: a RAW filter made in a new place is most
    /// likely rendered there too, and its image must come from
    /// `RAWDecodeGraph.output(of:)` or the smear is back for that path. When
    /// this fails, check the new place, then add its file here.
    @Test("RAW filters are made only where their image is keyed or never rendered")
    func rawFiltersAreMadeInKnownPlaces() throws {
        /// File → whether it renders the filter's image.
        let known = [
            "Sources/PhotoCore/Preview/PreviewGenerator.swift": true,   // decodeRAW; nativeSize reads a size
            "Sources/PhotoCore/Preview/CameraFrame.swift": false,       // hands its filter to decodeRAW
            "Sources/PhotoCore/Edits/AutoAdjust.swift": true,           // Auto White Balance; RawDefaults reads values
            "Sources/PhotoCore/Edits/MachineLearningNoiseReduction.swift": false, // reads decoder versions
        ]
        var found: Set<String> = []
        for path in RepositoryFiles.files(under: "Sources") where path.hasSuffix(".swift") {
            let text = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            guard text.contains("CIRAWFilter(") else { continue }
            found.insert(path)
            // The decoder's image is taken in one place only.
            if path != "Sources/PhotoCore/Preview/RAWDecodeGraph.swift" {
                #expect(!text.contains("raw.outputImage"), "\(path) takes a RAW filter's image without a key")
            }
            if known[path] == true {
                #expect(text.contains("RAWDecodeGraph.output(of:"), "\(path) no longer keys the image it renders")
            }
        }
        #expect(found == Set(known.keys), "RAW filters are made in other files than before: \(found.symmetricDifference(known.keys).sorted())")
    }
}

/// Two camera raws of one camera whose lens correction differs, rendered one
/// after the other in one process (issue #55): the second must come out as it
/// does alone. The synthetic DNGs have no lens correction, so this needs real
/// files; they are only read.
///
/// This suite is the guard for what `RAWDecodeGraph` assumes about Core
/// Image: run it on every new macOS. Without the key (`decodeRAW` taking
/// `raw.outputImage` as it is) 5 of its 7 cases fail on macOS 27.2.
///
/// `RAW_EDGE_SAMPLES` names them, separated by a colon: first a wide shot,
/// then a longer one that the decoder still corrects (a Panasonic ZS100 at
/// 9.1 mm, then at 12.7 mm). A pair that doesn't trigger the fault passes and
/// shows nothing.
/// `RAW_EDGE_SAMPLES=wide.RW2:longer.RW2 swift test --filter RAWEdgeSmearTests`
@Suite("Camera RAW files rendered one after another",
       .enabled(if: ProcessInfo.processInfo.environment["RAW_EDGE_SAMPLES"] != nil,
                "Set RAW_EDGE_SAMPLES to two raws of one camera, wide:longer"))
struct RAWEdgeSmearTests {
    static var samples: (first: URL, second: URL) {
        let paths = (ProcessInfo.processInfo.environment["RAW_EDGE_SAMPLES"] ?? "").split(separator: ":").map(String.init)
        return (URL(fileURLWithPath: paths.first ?? ""), URL(fileURLWithPath: paths.last ?? ""))
    }

    /// A generator whose engine has one context, so everything it renders
    /// would share that context's state.
    static func generator(_ name: String) -> PreviewGenerator {
        PreviewGenerator(engine: RenderEngine(contextCount: 1, name: name))
    }

    /// `after` (rendered after another raw) against `alone` (rendered by an
    /// engine that rendered nothing else).
    static func expectSame(_ after: EdgeBands?, _ alone: EdgeBands?, _ what: Comment) throws {
        let after = try #require(after), alone = try #require(alone)
        #expect(after.constantRowShare() <= alone.constantRowShare() + 0.05,
                "\(what): the edge columns repeat (\(after.constantRowShare()) of the rows, \(alone.constantRowShare()) alone)")
        #expect(after.meanDifference(from: alone) < 0.5,
                "\(what): the edges differ from the render alone by \(after.meanDifference(from: alone)) levels")
    }

    @Test("A cached preview does not depend on the raw decoded before it")
    func previews() throws {
        let (first, second) = Self.samples
        let alone = try Self.generator("alone").jpegData(source: second, stack: .identity, tiers: [.preview, .thumbnail])
        let generator = Self.generator("shared")
        _ = try generator.jpegData(source: first, stack: .identity, tiers: [.preview, .thumbnail])
        let after = try generator.jpegData(source: second, stack: .identity, tiers: [.preview, .thumbnail])
        for tier in [PreviewTier.preview, .thumbnail] {
            try Self.expectSame(after[tier].flatMap(EdgeBands.init(jpeg:)), alone[tier].flatMap(EdgeBands.init(jpeg:)),
                                "\(tier)")
        }
    }

    /// Full size, and resized to a 2048 px long edge (another render graph).
    @Test("An exported file does not depend on the raw exported before it", arguments: [false, true])
    func exports(resized: Bool) async throws {
        let (first, second) = Self.samples
        var settings = ExportSettings()
        if resized {
            settings.sizing = .longEdge
        }
        try await RepositoryFiles.withTemporaryDirectory { folder in
            func export(_ source: URL, _ generator: PreviewGenerator, as name: String) throws -> EdgeBands? {
                let url = folder.appending(path: name)
                try ExportRenderer(generator: generator).export(source: source, stack: .identity, values: SidecarValues(),
                                                                settings: settings, to: url, replacing: true)
                return EdgeBands(jpeg: try Data(contentsOf: url))
            }
            let alone = try export(second, Self.generator("alone"), as: "alone.jpg")
            let generator = Self.generator("shared")
            _ = try export(first, generator, as: "first.jpg")
            let after = try export(second, generator, as: "after.jpg")
            try Self.expectSame(after, alone, resized ? "export, 2048 px" : "export, full size")
        }
    }

    /// Align automatically stores what it measures, so a smeared decode would
    /// leave wrong values in the edit stack. Three measurements at 2048 px:
    /// over a minute in a debug build.
    @Test("Color Alignment's measurement does not depend on the raw measured before")
    func colorAlignment() throws {
        let (first, second) = Self.samples
        func measured(_ source: URL, _ generator: PreviewGenerator) throws -> ColorAlignment {
            try ColorAlignmentMeasurement.measure(source: source, adjustments: Adjustments(), generator: generator)
        }
        let alone = try measured(second, Self.generator("alone"))
        let generator = Self.generator("shared")
        _ = try measured(first, generator)
        let after = try measured(second, generator)
        #expect(after == alone)
    }

    /// Auto Exposure and Auto White Balance measure a small draft decode.
    @Test("Auto Exposure and Auto White Balance do not depend on the raw measured before")
    func measurements() throws {
        let (first, second) = Self.samples
        func measured(_ source: URL, _ generator: PreviewGenerator) throws -> [Double] {
            let auto = AutoAdjuster(generator: generator)
            let balance = try auto.whiteBalance(source: source, adjustments: Adjustments())
            return [try auto.exposure(source: source, adjustments: Adjustments()), balance.temperature ?? 0,
                    balance.tint ?? 0]
        }
        let alone = try measured(second, Self.generator("alone"))
        let generator = Self.generator("shared")
        _ = try measured(first, generator)
        let after = try measured(second, generator)
        #expect(after == alone)
    }

    @Test("The loupe's live frames do not depend on the raw opened before")
    func liveFrames() async throws {
        let (first, second) = Self.samples
        func frame(_ source: URL, _ generator: PreviewGenerator) async throws -> CGImage {
            let session = LiveRenderSession(source: source, generator: generator, colorSpace: nil)
            return try await session.render(Adjustments()).image.cgImage
        }
        let alone = try await frame(second, Self.generator("alone"))
        let generator = Self.generator("shared")
        _ = try await frame(first, generator)
        let after = try await frame(second, generator)
        try Self.expectSame(EdgeBands(after), EdgeBands(alone), "live frame")
    }

    @Test("The full-resolution live region does not depend on the raw opened before")
    func liveRegion() async throws {
        let (first, second) = Self.samples
        func frame(_ source: URL, _ generator: PreviewGenerator) async throws -> CGImage {
            let renderer = LiveRegionRenderer(source: source, generator: generator, colorSpace: nil)
            try await renderer.prepare(Adjustments())
            return try await renderer.render(Adjustments(), unit: CGRect(x: 0, y: 0, width: 1, height: 1)).image.cgImage
        }
        let alone = try await frame(second, Self.generator("alone"))
        let generator = Self.generator("shared")
        _ = try await frame(first, generator)
        let after = try await frame(second, generator)
        try Self.expectSame(EdgeBands(after), EdgeBands(alone), "live region")
    }
}

/// What a soak's footprints say about memory left behind per preview. The
/// limits scale with the number of previews, so a short soak is as much of
/// a guard as a long one: 50 KB a preview is what a context of its own per
/// decode left (status.md, "C1"), and a level run moves by 20 MB or so
/// between samples whatever its length.
struct SoakGrowth {
    /// MB a level run may differ by between two samples.
    static let headroom = 24.0
    /// KB a preview allowed on top of that, a tenth of the leak.
    static let allowedPerPreview = 5.0
    /// KB a preview the fitted growth may reach, a fifth of the leak.
    static let fittedLimit = 10.0
    /// The fewest previews at which the leak is well clear of both limits
    /// (110 MB of growth against 35 MB allowed).
    static let fewestPreviews = 3000

    /// The footprint in MB after each twelfth of the run.
    let footprints: [Double]
    let total: Int

    /// The samples from the first quarter on: what came before is warming up.
    var settled: [Double] { Array(footprints.dropFirst(2)) }
    var previewsPerSample: Double { Double(total) / 12 }
    var previewsSettled: Double { previewsPerSample * Double(max(settled.count - 1, 0)) }

    /// MB from the first quarter to the end.
    var growth: Double { (settled.last ?? 0) - (settled.first ?? 0) }
    var allowedGrowth: Double { Self.headroom + Self.allowedPerPreview * previewsSettled / 1024 }

    /// KB a preview: the slope of a line fitted to the settled samples, which
    /// one odd sample moves less than it moves `growth`.
    var fittedPerPreview: Double {
        let count = Double(settled.count)
        guard settled.count > 1 else { return 0 }
        let meanX = (count - 1) / 2, meanY = settled.reduce(0, +) / count
        var covariance = 0.0, variance = 0.0
        for (index, value) in settled.enumerated() {
            covariance += (Double(index) - meanX) * (value - meanY)
            variance += (Double(index) - meanX) * (Double(index) - meanX)
        }
        return covariance / variance / previewsPerSample * 1024
    }

    var isLevel: Bool { growth < allowedGrowth && fittedPerPreview < Self.fittedLimit }
}

/// The soak's verdict on footprints recorded from real runs (status.md and
/// code-review.md), so the limits are known to tell the two apart without
/// running a soak.
@Suite("Soak growth")
struct SoakGrowthTests {
    @Test("A level run passes and the recorded leak fails, at every length the soak allows")
    func tellsALeakFromALevelRun() {
        // A key per decode, 24,000 and 12,000 previews.
        let level = [[432.0, 432, 439, 443, 444, 439, 440, 440, 441, 441, 444, 436],
                     [428.0, 432, 430, 434, 427, 432, 433, 434, 432, 435, 431, 428],
                     [427.0, 428, 447, 444, 444, 447, 439, 443, 444, 441, 445, 448]]
        for (footprints, total) in zip(level, [24000, 12000, 12000]) {
            let growth = SoakGrowth(footprints: footprints, total: total)
            #expect(growth.isLevel, "\(growth.growth) MB, \(growth.fittedPerPreview) KB a preview")
            // The same samples from a run a quarter as long are still level.
            #expect(SoakGrowth(footprints: footprints, total: SoakGrowth.fewestPreviews).isLevel)
        }

        // A context per decode, kept and emptied (12,000) and made new (12,000, noisier).
        let leaking = [[512.0, 573, 621, 673, 729, 772, 826, 884, 934, 990, 1041, 1094],
                       [388.0, 402, 540, 647, 571, 646, 684, 721, 846, 972, 1037, 912]]
        for footprints in leaking {
            let growth = SoakGrowth(footprints: footprints, total: 12000)
            #expect(!growth.isLevel)
            #expect(growth.growth > growth.allowedGrowth && growth.fittedPerPreview > SoakGrowth.fittedLimit)
        }
        #expect(abs(SoakGrowth(footprints: leaking[0], total: 12000).fittedPerPreview - 53) < 3)

        // 50 KB a preview at the shortest soak, with a level run's ups and downs on top.
        let short = level[0].enumerated().map { index, value in
            value + 50.0 * Double(index + 1) * Double(SoakGrowth.fewestPreviews) / 12 / 1024
        }
        let growth = SoakGrowth(footprints: short, total: SoakGrowth.fewestPreviews)
        #expect(!growth.isLevel)
        #expect(growth.growth > growth.allowedGrowth && growth.fittedPerPreview > SoakGrowth.fittedLimit)
    }
}

/// Thousands of RAW previews in one process. A context of its own for every
/// decode stopped the smear too, but left about 50 KB behind per decode for
/// good (docs/features/raw-edge-smear/status.md, "C1"); with a key per decode
/// on the shared contexts the footprint stays level. Too long for every run:
/// `RAW_CONTEXT_SOAK=24000 swift test --filter RAWContextSoakTests`
/// With `RAW_EDGE_SAMPLES` set as well (`RAWEdgeSmearTests`), the two raws
/// are also rendered in turn, a tenth as often, each checked against its
/// render made alone.
@Suite("RAW context soak", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["RAW_CONTEXT_SOAK"] != nil,
                "Set RAW_CONTEXT_SOAK to a number of previews, 3000 or more, such as 12000"))
struct RAWContextSoakTests {
    static let atOnce = 7
    /// 12,000 unless `RAW_CONTEXT_SOAK` gives a number; never fewer than the limits can judge.
    static var total: Int {
        max(SoakGrowth.fewestPreviews, Int(ProcessInfo.processInfo.environment["RAW_CONTEXT_SOAK"] ?? "") ?? 12000)
    }

    /// The process's memory footprint in MB, as Activity Monitor shows it.
    static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Runs `render(index)` `total` times, `atOnce` at a time, and returns
    /// the footprint after each twelfth.
    static func soak(_ total: Int, _ render: @escaping @Sendable (Int) throws -> Void) async throws -> [Double] {
        var footprints: [Double] = []
        try await withThrowingTaskGroup(of: Void.self) { group in
            var started = 0, finished = 0
            func add() {
                let index = started
                started += 1
                group.addTask { try autoreleasepool { try render(index) } }
            }
            for _ in 0..<min(atOnce, total) { add() }
            while try await group.next() != nil {
                finished += 1
                if finished % (total / 12) == 0 { footprints.append(footprint()) }
                if started < total { add() }
            }
        }
        return footprints
    }

    /// The limits are `SoakGrowth`'s, which scale with the number of previews.
    @Test("Memory stays level over thousands of RAW previews")
    func previews() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let dng = folder.appending(path: "photo.dng")
            try SyntheticDNG.write(to: dng, options: .init(width: 1200, height: 800, seed: 5))
            let generator = PreviewGenerator(engine: RenderEngine(contextCount: Self.atOnce, name: "soak"))
            let footprints = try await Self.soak(Self.total) { _ in
                _ = try generator.jpegData(source: dng, stack: .identity, tiers: [.preview, .thumbnail])
            }
            let growth = SoakGrowth(footprints: footprints, total: Self.total)
            let fitted = (growth.fittedPerPreview * 10).rounded() / 10
            print("RAW context soak: \(Self.total) previews, footprint in MB after each twelfth:",
                  footprints.map { Int($0) }, "\(fitted) KB a preview after the first quarter")
            #expect(footprints.count == 12)
            #expect(growth.growth < growth.allowedGrowth,
                    "the footprint grew by \(Int(growth.growth)) MB after the first quarter; \(Int(growth.allowedGrowth)) MB allowed")
            #expect(growth.fittedPerPreview < SoakGrowth.fittedLimit,
                    "\(fitted) KB left behind a preview; under \(SoakGrowth.fittedLimit) KB allowed")
        }
    }

    @Test("Two camera raws rendered in turn keep coming out as they do alone",
          .enabled(if: ProcessInfo.processInfo.environment["RAW_EDGE_SAMPLES"] != nil))
    func realFilesInTurn() async throws {
        let (first, second) = RAWEdgeSmearTests.samples
        let files = [first, second]
        let alone = try files.map {
            try RAWEdgeSmearTests.generator("alone").jpegData(source: $0, stack: .identity, tier: .preview)
        }
        let generator = PreviewGenerator(engine: RenderEngine(contextCount: Self.atOnce, name: "soak"))
        let wrong = Mutex(0)
        let footprints = try await Self.soak(Self.total / 10) { index in
            let data = try generator.jpegData(source: files[index % 2], stack: .identity, tier: .preview)
            if data != alone[index % 2] { wrong.withLock { $0 += 1 } }
        }
        print("RAW context soak: \(Self.total / 10) camera raw previews, footprint in MB after each twelfth:",
              footprints.map { Int($0) })
        #expect(wrong.withLock { $0 } == 0, "renders that differ from the render made alone")
    }
}
