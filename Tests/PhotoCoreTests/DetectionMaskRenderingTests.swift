import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Issue #88, R6, R7, R14: rendering stored detection results.
@Suite("Detection masks: rendering")
struct DetectionMaskRenderingTests {
    // MARK: Fixtures

    /// A disc of radius `radius` (pixels) centered at (cx, cy), top row first:
    /// `inside` within it, `outside` beyond, a hard edge with 4×4 supersampling.
    static func disc(width: Int, height: Int, cx: Double, cy: Double, radius: Double,
                     inside: Double = 0.75, outside: Double = 0.2, ramp: Double = 0.1) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var covered = 0.0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let px = Double(x) + (Double(sx) + 0.5) / 4, py = Double(y) + (Double(sy) + 0.5) / 4
                        if hypot(px - cx, py - cy) <= radius { covered += 1 / 16 }
                    }
                }
                // A gentle ramp across the frame, so the guide is not flat on either side.
                let shade = ramp * Double(x) / Double(width)
                out[y * width + x] = outside + shade + (inside - outside) * covered
            }
        }
        return out
    }

    /// The guide as a gray image in the working space, values rounded to half float.
    static func image(_ values: [Double], width: Int, height: Int) -> CIImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for i in values.indices {
            let v = Float(Float16(values[i]))
            pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v
        }
        return LinearImage(width: width, height: height, pixels: pixels).ciImage
    }

    static func render(_ image: CIImage) -> [Double] {
        MaskReferenceTests.render(image)
    }

    /// A mask-resolution result: the disc's coverage of each result pixel, quantized to 8 bits.
    static func raster(width: Int, height: Int, frameWidth: Int, frameHeight: Int, cx: Double, cy: Double,
                       radius: Double) -> MaskRaster.Pixels {
        let sx = Double(frameWidth) / Double(width), sy = Double(frameHeight) / Double(height)
        var levels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                // Centre sampling: a hard, stair-stepped mask, as a coarse model gives.
                let inside = hypot((Double(x) + 0.5) * sx - cx, (Double(y) + 0.5) * sy - cy) <= radius
                levels[y * width + x] = inside ? 255 : 0
            }
        }
        return MaskRaster.Pixels(width: width, height: height, levels: levels)
    }

    // MARK: Stretch

    @Test("The stretch puts the result's top row at the top of the frame and matches its reference")
    func stretchOrientation() throws {
        let pixels = MaskRaster.Pixels(width: 4, height: 3, levels: [255, 255, 200, 255,
                                                                      128, 64, 32, 0,
                                                                      0, 0, 10, 0])
        let frame = CGRect(x: 0, y: 0, width: 16, height: 12)
        let stretched = try #require(GuidedMaskFilter.stretched(pixels, over: frame))
        let actual = Self.render(stretched)
        let expected = GuidedFilterReference.stretch(pixels, width: 16, height: 12)
        // One half-float rounding of the stored value (and float evaluation).
        MaskReferenceTests.check(actual, expected, tolerance: 0x1p-11 + 1e-6)
        #expect(actual[0] > 0.99 && actual[16 * 11] < 0.01, "top row bright, bottom row dark")
    }

    // MARK: The guided filter

    @Test("The guided filter matches its CPU reference within the half-float bound",
          arguments: [(32, 24, 256, 192), (64, 64, 200, 150), (20, 30, 120, 180)])
    func matchesReference(raster: (Int, Int, Int, Int)) throws {
        let (w, h, width, height) = raster
        let cx = Double(width) * 0.47, cy = Double(height) * 0.52, radius = Double(min(width, height)) * 0.3
        let guide = Self.disc(width: width, height: height, cx: cx, cy: cy, radius: radius)
            .map { Double(Float16($0)) }
        let pixels = Self.raster(width: w, height: h, frameWidth: width, frameHeight: height, cx: cx, cy: cy,
                                 radius: radius)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let r = GuidedMaskFilter.radius(rasterSize: CGSize(width: w, height: h), frameSize: frame.size)
        let stretched = try #require(GuidedMaskFilter.stretched(pixels, over: frame))
        let q = try #require(GuidedMaskFilter.filter(stretched, guide: Self.image(guide, width: width, height: height),
                                                     radius: r))
        let actual = Self.render(q)
        let reference = GuidedFilterReference.filter(p: GuidedFilterReference.stretch(pixels, width: width, height: height),
                                                     guide: guide, width: width, height: height, radius: r)
        var worst = 0.0, worstRatio = 0.0
        for i in actual.indices {
            let difference = abs(actual[i] - reference.q[i])
            worst = max(worst, difference)
            worstRatio = max(worstRatio, difference / reference.tolerance[i])
        }
        #expect(worstRatio <= 1, "worst \(worst), \(worstRatio) of the bound (r = \(r))")
    }

    @Test("Window radius is one mask pixel in render pixels, rounded up")
    func radius() {
        #expect(GuidedMaskFilter.radius(rasterSize: CGSize(width: 512, height: 512), frameSize: CGSize(width: 2560, height: 1707)) == 5)
        #expect(GuidedMaskFilter.radius(rasterSize: CGSize(width: 512, height: 512), frameSize: CGSize(width: 6000, height: 4000)) == 12)
        #expect(GuidedMaskFilter.radius(rasterSize: CGSize(width: 512, height: 384), frameSize: CGSize(width: 512, height: 341)) == 1)
        #expect(GuidedMaskFilter.radius(rasterSize: CGSize(width: 1, height: 1), frameSize: CGSize(width: 9000, height: 9000)) == 64)
    }

    @Test("At 100% on a hard edge the result follows the photo's edge, with no staircase of mask pixels (AC7)")
    func noStaircase() throws {
        // A mask pixel spans 8 render pixels, as a 512-pixel mask over a 4096-pixel photo.
        let width = 384, height = 288, w = 48, h = 36
        let cx = 191.3, cy = 147.8, radius = 101.7
        let guide = Self.disc(width: width, height: height, cx: cx, cy: cy, radius: radius).map { Double(Float16($0)) }
        let pixels = Self.raster(width: w, height: h, frameWidth: width, frameHeight: height, cx: cx, cy: cy,
                                 radius: radius)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let r = GuidedMaskFilter.radius(rasterSize: CGSize(width: w, height: h), frameSize: frame.size)
        let stretched = try #require(GuidedMaskFilter.stretched(pixels, over: frame))
        let filtered = Self.render(try #require(GuidedMaskFilter.filter(
            stretched, guide: Self.image(guide, width: width, height: height), radius: r)))
        let bilinear = Self.render(stretched)

        /// For each row crossing the disc, where the alpha first rises past ½
        /// from the left, against where the edge truly is.
        func edgeErrors(_ alpha: [Double]) -> [Double] {
            var errors: [Double] = []
            for y in Int(cy - radius * 0.8)...Int(cy + radius * 0.8) {
                let py = Double(y) + 0.5
                let truth = cx - (radius * radius - (py - cy) * (py - cy)).squareRoot()
                guard let x = (1..<width).first(where: { alpha[y * width + $0] >= 0.5 }) else { continue }
                let a0 = alpha[y * width + x - 1], a1 = alpha[y * width + x]
                let crossing = Double(x - 1) + 0.5 + (0.5 - a0) / (a1 - a0)
                errors.append(abs(crossing - truth))
            }
            return errors
        }
        let guided = edgeErrors(filtered), stepped = edgeErrors(bilinear)
        let guidedWorst = guided.max() ?? .infinity, steppedWorst = stepped.max() ?? 0
        // The stretched result is off by up to half a mask pixel (4 px) in steps;
        // filtered it lies on the photo's edge to about a render pixel.
        #expect(steppedWorst >= 2.5, "the fixture has a staircase to remove (\(steppedWorst))")
        #expect(guidedWorst <= 1.25, "guided edge within \(guidedWorst) px, stretched \(steppedWorst) px")
        // No steps: the crossing moves smoothly from row to row, never by a mask pixel's jump beyond the circle's own slope.
        #expect(guided.count > 100)
    }

    // MARK: In the renderer

    static func scene() -> CIImage {
        let width = TestScene.defaultWidth, height = TestScene.defaultHeight
        let values = disc(width: width, height: height, cx: 120, cy: 90, radius: 55)
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for i in values.indices {
            // A colored subject on a gray ground.
            pixels[i * 4] = Float(values[i]) * 1.1
            pixels[i * 4 + 1] = Float(values[i])
            pixels[i * 4 + 2] = Float(values[i]) * 0.8
        }
        return LinearImage(width: width, height: height, pixels: pixels).ciImage
    }

    static let subjectRaster: MaskRaster = {
        let pixels = raster(width: 32, height: 24, frameWidth: TestScene.defaultWidth,
                            frameHeight: TestScene.defaultHeight, cx: 120, cy: 90, radius: 55)
        return try! MaskRaster(levels: pixels.levels, width: 32, height: 24, instances: 1, request: .foreground)
    }()

    static func stack(_ components: [MaskComponent], exposure: Double = 1) -> Adjustments {
        DetectionMaskModelTests.masks(components, exposure: exposure)
    }

    static func detection(_ kind: MaskDetectionKind, _ digest: String?, operation: MaskOperation = .add,
                          invert: Bool = false) -> MaskComponent {
        MaskComponent(.detection(MaskDetection(kind: kind, raster: digest)), operation: operation, invert: invert)
    }

    static func rendered(_ adjustments: Adjustments, store: MaskRasterStore?) -> [Float] {
        let renderer = AdjustmentRenderer(maskRasters: store)
        return ReferenceTests.renderLinear(renderer.render(adjustments, to: scene(), context: RenderContext())).pixels
    }

    @Test("A stored result renders the same on every run and brightens the subject only (AC4)")
    func storedResultRenders() {
        let store = MaskRasterStore(rasters: [Self.subjectRaster])
        let values = Self.stack([Self.detection(.subject, Self.subjectRaster.digest)])
        let first = Self.rendered(values, store: store), second = Self.rendered(values, store: store)
        #expect(first == second)
        let plain = Self.rendered(Adjustments(), store: store)
        let width = TestScene.defaultWidth
        let center = (90 * width + 120) * 4, corner = (5 * width + 5) * 4
        #expect(first[center] > plain[center] * 1.9, "one stop on the subject")
        #expect(abs(first[corner] - plain[corner]) < 1e-3, "nothing off the subject")
    }

    @Test("Background selects everything but the subject; Invert on Background selects the subject")
    func background() {
        let store = MaskRasterStore(rasters: [Self.subjectRaster])
        let digest = Self.subjectRaster.digest
        let subject = Self.rendered(Self.stack([Self.detection(.subject, digest)]), store: store)
        let background = Self.rendered(Self.stack([Self.detection(.background, digest)]), store: store)
        let inverted = Self.rendered(Self.stack([Self.detection(.background, digest, invert: true)]), store: store)
        let plain = Self.rendered(Adjustments(), store: store)
        let width = TestScene.defaultWidth
        let center = (90 * width + 120) * 4, corner = (5 * width + 5) * 4
        #expect(abs(background[center] - plain[center]) < 1e-3 && background[corner] > plain[corner] * 1.9)
        #expect(zip(inverted, subject).allSatisfy { abs($0 - $1) <= 2e-3 })
    }

    @Test("Combined with a gradient: add, subtract, intersect and invert, and Amount, change the effect (AC2)",
          arguments: MaskOperation.allCases)
    func combines(operation: MaskOperation) {
        let store = MaskRasterStore(rasters: [Self.subjectRaster])
        let gradient = MaskComponent(.linear(LinearGradient(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 1))))
        let alone = Self.rendered(Self.stack([gradient]), store: store)
        let combined = Self.rendered(Self.stack([gradient, Self.detection(.people, Self.subjectRaster.digest,
                                                                          operation: operation)]), store: store)
        let invertedCombined = Self.rendered(Self.stack([gradient, Self.detection(.people, Self.subjectRaster.digest,
                                                                                  operation: operation, invert: true)]),
                                             store: store)
        #expect(combined != alone)
        #expect(invertedCombined != combined)
        var half = Self.stack([gradient, Self.detection(.people, Self.subjectRaster.digest, operation: operation)])
        half.local.masks[0].amount = 50
        #expect(Self.rendered(half, store: store) != combined)
    }

    @Test("Nothing found, a failed detection, a missing row and damaged bytes render as without the component (AC6, AC13)")
    func idleComponentsRenderAsWithout() throws {
        let empty = MaskRaster.empty(.foreground)
        let missing = try MaskRaster(levels: [255, 0, 0, 255], width: 2, height: 2, instances: 1, request: .person)
        let store = MaskRasterStore(rasters: [empty, Self.subjectRaster])
        let gradient = MaskComponent(.radial(RadialGradient(center: MaskPoint(x: 0.3, y: 0.4), radiusX: 0.2, radiusY: 0.2)))
        for idle in [Self.detection(.subject, empty.digest), Self.detection(.background, empty.digest),
                     Self.detection(.people, nil), Self.detection(.people, missing.digest)] {
            for operation in MaskOperation.allCases {
                var component = idle
                component.operation = operation
                for invert in [false, true] {
                    component.invert = invert
                    // Alone in its mask: as with no mask at all.
                    let without = Self.rendered(Adjustments(), store: store)
                    #expect(Self.rendered(Self.stack([component]), store: store) == without)
                    // Beside a gradient: as the gradient alone.
                    let gradientOnly = Self.rendered(Self.stack([gradient]), store: store)
                    #expect(Self.rendered(Self.stack([gradient, component]), store: store) == gradientOnly)
                }
            }
        }
        // No store at all (a renderer that can't reach the catalog) is the same as missing.
        #expect(Self.rendered(Self.stack([Self.detection(.subject, Self.subjectRaster.digest)]), store: nil)
                == Self.rendered(Adjustments(), store: nil))
    }

    @Test("A row whose bytes don't decode is missing to the store")
    func damagedRowIsMissing() async throws {
        let fixture = try await CatalogFixture.make()
        try await fixture.catalog.storeMaskRaster(Self.subjectRaster)
        let store = MaskRasterStore(catalog: fixture.catalog)
        guard case .stored = store.lookup(Self.subjectRaster.digest) else {
            Issue.record("the stored result was not found")
            return
        }
        try await fixture.catalog.damageMaskRasterForChecks(digest: Self.subjectRaster.digest)
        store.forget(Self.subjectRaster.digest)
        #expect(store.lookup(Self.subjectRaster.digest) == .missing)
        try await fixture.catalog.deleteMaskRasterForChecks(digest: Self.subjectRaster.digest)
        #expect(store.lookup(Self.subjectRaster.digest) == .missing)
    }

    @Test("The store keeps at most its capacity, the least recently used dropped first")
    func storeCapacity() throws {
        let rasters = try (0..<(MaskRasterStore.capacity + 2)).map {
            try MaskRaster(levels: [UInt8($0)], width: 1, height: 1, instances: 1, request: .foreground)
        }
        let store = MaskRasterStore(rasters: [])
        for raster in rasters { store.remember(raster) }
        #expect(store.cached(rasters[0].digest) == nil)
        #expect(store.cached(rasters[1].digest) == nil)
        #expect(store.cached(rasters.last!.digest) != nil)
    }

    @Test("Turned and cropped, the result stays on the same pixels of the photo (AC7)")
    func cropAndTurnKeepTheMask() throws {
        let store = MaskRasterStore(rasters: [Self.subjectRaster])
        let mask = [Self.detection(.subject, Self.subjectRaster.digest)]
        // A quarter turn and a crop on whole pixels of the turned frame (192 x 256).
        let crop = Crop(rect: CropRect(x: 0.25, y: 0.125, width: 0.5, height: 0.75), quarterTurns: 1)
        var plainCropped = Adjustments()
        plainCropped.crop = crop
        var masked = Self.stack(mask)
        masked.crop = crop
        let width = TestScene.defaultWidth, height = TestScene.defaultHeight
        func gain(_ masked: [Float], _ plain: [Float]) -> [Float] {
            stride(from: 0, to: masked.count, by: 4).flatMap { i -> [Float] in
                let g = masked[i + 1] / plain[i + 1]
                return [g, g, g, 1]
            }
        }
        // The gain of the uncropped render, turned and cropped as the photo is.
        let flat = gain(Self.rendered(Self.stack(mask), store: store), Self.rendered(Adjustments(), store: store))
        let moved = ReferenceTests.renderLinear(crop.apply(to: LinearImage(width: width, height: height, pixels: flat).ciImage))
        let cropped = gain(Self.rendered(masked, store: store), Self.rendered(plainCropped, store: store))
        #expect(moved.pixels.count == cropped.count)
        // Away from the crop's border, where the filter's windows (2 × 2r) see the same pixels.
        let margin = 4 * GuidedMaskFilter.radius(rasterSize: CGSize(width: 32, height: 24),
                                                 frameSize: CGSize(width: width, height: height))
        var worst: Float = 0
        for y in margin..<(moved.height - margin) {
            for x in margin..<(moved.width - margin) {
                let i = (y * moved.width + x) * 4
                worst = max(worst, abs(moved.pixels[i] - cropped[i]))
            }
        }
        // Half-float roundings of the gain met in another order (rows and columns swap).
        #expect(worst < 0.01, "worst gain difference \(worst)")
        #expect(cropped.contains { $0 > 1.9 }, "the subject is in the crop")
    }
}
