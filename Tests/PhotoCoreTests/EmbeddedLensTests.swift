import CoreGraphics
import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// A camera's own lens corrections on LibRaw's decode (issue #161): the
/// tables' functions, the lookup tables made from them, and the kernel
/// against its CPU reference. Synthetic throughout; the camera's file and its
/// embedded JPEG are checked in `LibRawFallbackTests`.
@Suite("Embedded lens corrections")
struct EmbeddedLensTests {
    typealias Correction = EmbeddedLensCorrection

    /// The Fujifilm XF 35mm f/2 at f/2 on an X-E3: barrel distortion to −7.6%
    /// at the corner, half the light there.
    static let lens35 = FujifilmRAF.LensTables(knots: SyntheticRAF.knots11, distortion: SyntheticRAF.distortion35,
                                               red: [0] + SyntheticRAF.red35, blue: [0] + SyntheticRAF.blue35,
                                               vignetting: SyntheticRAF.vignetting35)
    /// A pincushion lens with stronger color shifts, to exercise the other sign.
    static let pincushion = FujifilmRAF.LensTables(
        knots: [0, 0.25, 0.5, 0.75, 1], distortion: [0, 0.3, 1.2, 2.6, 4.5], red: [0, 0.0004, 0.0009, 0.0015, 0.002],
        blue: [0, -0.0003, -0.0008, -0.0012, -0.0018], vignetting: [100, 96, 88, 76, 60])
    static let flat = FujifilmRAF.LensTables(knots: [0, 0.5, 1], distortion: [0, 0, 0], red: [0, 0, 0], blue: [0, 0, 0],
                                             vignetting: [100, 100, 100])
    /// A 3:2 frame's short side over its diagonal.
    static let shortSide = 2 / hypot(3.0, 2.0)

    // MARK: The camera's functions

    @Test("A table is linear between its knots and constant beyond them")
    func tableValues() {
        let knots = [0.2, 0.5, 1.0], values = [1.0, 4.0, -1.0]
        #expect(Correction.value(values, knots: knots, at: 0) == 1)
        #expect(Correction.value(values, knots: knots, at: 0.2) == 1)
        #expect(abs(Correction.value(values, knots: knots, at: 0.35) - 2.5) < 1e-12)
        #expect(Correction.value(values, knots: knots, at: 0.5) == 4)
        #expect(abs(Correction.value(values, knots: knots, at: 0.75) - 1.5) < 1e-12)
        #expect(Correction.value(values, knots: knots, at: 1) == -1)
        #expect(Correction.value(values, knots: knots, at: 3) == -1)
    }

    /// A point recorded at r belongs at r / m(r): the radius found for a
    /// place in the corrected picture maps back onto it.
    @Test("The recorded radius found for a corrected radius maps back onto it", arguments: [lens35, pincushion, flat])
    func sourceRadiusInverts(tables: FujifilmRAF.LensTables) {
        for step in 0...400 {
            let destination = Double(step) / 400 * 1.2
            let source = Correction.sourceRadius(tables, destinationRadius: destination)
            let back = source / Correction.distortionFactor(tables, sourceRadius: source)
            #expect(abs(back - destination) <= 1e-13 * max(destination, 1), "\(destination): \(back)")
        }
        #expect(Correction.sourceRadius(tables, destinationRadius: 0) == 0)
    }

    @Test("Barrel distortion takes each place from nearer the center; red and blue from their own radii")
    func multipliers() {
        // At the recorded corner the table says −7.568%: what was recorded there belongs at 1 / 0.92432.
        let corner = 1 / (1 - 0.07568)
        let m = Correction.multipliers(Self.lens35, destinationRadius: corner)
        #expect(abs(m.y - (1 - 0.07568)) < 1e-12)
        #expect(abs(m.x - m.y * (1 + 0.000274)) < 1e-12)
        #expect(abs(m.z - m.y * (1 - 0.000335)) < 1e-12)
        // Nothing moves at the center, and less is taken from nearer in the closer to it.
        #expect(Correction.multipliers(Self.lens35, destinationRadius: 0) == SIMD3(1, 1, 1))
        var previous = 1.0
        for step in 1...100 {
            let green = Correction.multipliers(Self.lens35, destinationRadius: Double(step) / 100).y
            #expect(green <= previous && green > 0.9)
            previous = green
        }
        #expect(Correction.multipliers(Self.pincushion, destinationRadius: 0.8).y > 1)
        #expect(Correction.multipliers(Self.flat, destinationRadius: 0.7) == SIMD3(1, 1, 1))
        // Vignetting: half the light at the corner is twice the gain.
        #expect(abs(Correction.gain(Self.lens35, sourceRadius: 1) - 100 / 52.15) < 1e-12)
        #expect(Correction.gain(Self.lens35, sourceRadius: 0) == 1)
        #expect(Correction.gain(Self.flat, sourceRadius: 0.6) == 1)
    }

    /// darktable's rule, which the camera's own JPEG agrees with
    /// (`LibRawFallbackTests`): the picture is scaled by the largest
    /// multiplier between the frame's short side and its corner, so that no
    /// place is taken from outside the recorded frame.
    @Test("The corrected picture is scaled so that it fills the frame from within the recorded one")
    func outputScale() {
        let barrel = Correction(Self.lens35, shortSideRadius: Self.shortSide)
        // Barrel: the multiplier falls with the radius, so it is the short side's (red's, which reaches furthest).
        #expect(abs(barrel.scale - Correction.multipliers(Self.lens35, destinationRadius: Self.shortSide).max()) < 1e-12)
        #expect(barrel.scale == Correction.outputScale(Self.lens35, shortSideRadius: Self.shortSide))
        #expect(barrel.scale < 1 && barrel.scale > 0.98)
        let pin = Correction(Self.pincushion, shortSideRadius: Self.shortSide)
        // Pincushion: the corner's, with the color that reaches furthest.
        #expect(abs(pin.scale - Correction.multipliers(Self.pincushion, destinationRadius: 1).max()) < 1e-4)
        #expect(pin.scale > 1)
        #expect(Correction(Self.flat, shortSideRadius: Self.shortSide).scale == 1)
        for correction in [barrel, pin] {
            // No place of the frame is taken from beyond the recorded frame's corner,
            // and along the frame's edges none from beyond the recorded edges.
            for step in 0...200 {
                let angle = Double(step) / 200 * Double.pi / 2
                // A point on the frame's border (half-diagonal 1; 3:2), by its direction.
                let halfWidth = 3 / hypot(3.0, 2.0), halfHeight = 2 / hypot(3.0, 2.0)
                let reach = min(halfWidth / max(cos(angle), 1e-12), halfHeight / max(sin(angle), 1e-12))
                let m = correction.multipliers(atOutputRadius: reach).max()
                #expect(m <= 1 + 1e-9, "direction \(angle): \(m)")
            }
            #expect(correction.sourceReach >= 1)
        }
    }

    /// The largest jump of a function's slope at the places `at`, measured just to each side of them.
    static func slopeJump(_ function: (Double) -> Double, at places: [Double]) -> Double {
        let step = 1e-7
        return places.map { place in
            let before = (function(place - step) - function(place - 2 * step)) / step
            let after = (function(place + 2 * step) - function(place + step)) / step
            return abs(after - before)
        }.max() ?? 0
    }

    /// Between the camera's knots the functions are smooth and reading
    /// between two entries is exact to 10⁻⁶. At a knot their slope jumps, and
    /// the entry pair around it is off by at most a quarter of the jump
    /// times the entries' spacing.
    @Test("The lookup tables hold the functions; reading between entries is off only by the knots' slope jumps")
    func lookupTables() {
        for tables in [Self.lens35, Self.pincushion] {
            let correction = Correction(tables, shortSideRadius: Self.shortSide)
            let last = Double(Correction.tableCount - 1)
            #expect(correction.multiplierOffsets.count == Correction.tableCount && correction.gainOffsets.count == Correction.tableCount)
            // Where the knots fall in each table: as radii of the output, and of the source.
            let outputKnots = tables.knots.map { $0 / Correction.distortionFactor(tables, sourceRadius: $0) * correction.scale }
            let multiplierJump = (0..<3).map { channel in
                Self.slopeJump({ correction.multipliers(atOutputRadius: $0)[channel] }, at: outputKnots.filter { $0 > 0 && $0 < 1 })
            }.max() ?? 0
            let gainJump = Self.slopeJump({ Correction.gain(tables, sourceRadius: $0) },
                                          at: tables.knots.filter { $0 > 0 && $0 < correction.sourceReach })
            let multiplierBound = multiplierJump / last / 4 + 1e-6
            let gainBound = gainJump * correction.sourceReach / last / 4 + 1e-6
            var worst = 0.0, worstGain = 0.0
            for step in 0..<(Correction.tableCount * 4 - 4) {
                let position = Double(step) / 4
                let index = Int(position), t = position - Double(index)
                let next = min(index + 1, Correction.tableCount - 1)
                let read = correction.multiplierOffsets[index] + (correction.multiplierOffsets[next] - correction.multiplierOffsets[index]) * t
                let difference = read - (correction.multipliers(atOutputRadius: position / last) - 1)
                worst = max(worst, abs(difference.x), abs(difference.y), abs(difference.z))
                let gainRead = correction.gainOffsets[index] + (correction.gainOffsets[next] - correction.gainOffsets[index]) * t
                worstGain = max(worstGain, abs(gainRead - (Correction.gain(tables, sourceRadius: position / last * correction.sourceReach) - 1)))
            }
            #expect(worst <= multiplierBound, "multipliers \(worst), bound \(multiplierBound)")
            #expect(worstGain <= gainBound, "gain \(worstGain), bound \(gainBound)")
            // For these lenses: under a tenth of a pixel at a 24-megapixel frame's corner, and a thousandth of the light.
            #expect(multiplierBound < 2.5e-5 && gainBound < 1e-3)
        }
        // The image the kernel reads: two rows of 32-bit floats, not color managed.
        let image = Correction(Self.lens35, shortSideRadius: Self.shortSide).lookupImage
        #expect(image.extent == CGRect(x: 0, y: 0, width: Correction.tableCount, height: 2))
        #expect(image.colorSpace == nil)
    }

    // MARK: The kernel

    /// A smooth picture, so that reading it between pixels is exact to a
    /// bound: 0.5 + 0.2 (sin(x / 9) + cos(y / 7)), tinted by channel.
    static func smooth(_ x: Double, _ y: Double) -> SIMD3<Double> {
        let base = 0.5 + 0.2 * (sin(x / 9) + cos(y / 7))
        return SIMD3(base, base * 0.8 + 0.05, 0.9 - base * 0.6)
    }

    static func image(width: Int, height: Int, _ value: (Double, Double) -> SIMD3<Double>) -> LinearImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                // Pixel centers in Core Image's coordinates (from the bottom left).
                let v = value(Double(column) + 0.5, Double(height - 1 - row) + 0.5)
                pixels[(row * width + column) * 4] = Float(v.x)
                pixels[(row * width + column) * 4 + 1] = Float(v.y)
                pixels[(row * width + column) * 4 + 2] = Float(v.z)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// The frame of a 336 x 232 source as a half-size decode has it: it starts between pixels.
    static let frame = CGRect(x: 12, y: 7.5, width: 312, height: 208)

    static func correction(_ tables: FujifilmRAF.LensTables) -> Correction {
        Correction(tables, shortSideRadius: Double(min(frame.width, frame.height) / hypot(frame.width, frame.height)))
    }

    /// Coordinates up to 336 pixels carry single precision's 2⁻²⁴ relative
    /// error through about four operations (2⁻²² × 336 ≈ 8 × 10⁻⁵ of a
    /// pixel). A sample read between pixels moves by at most the largest step
    /// between neighbors times that; the gain (at most 2.6 here) multiplies
    /// it, and a few more roundings of a value below 2.6 add 10⁻⁶.
    static func floatBound(largestStep: Float, gain: Float) -> Float {
        0x1p-22 * 336 * largestStep * gain + 1e-6
    }

    @Test("The kernel matches its CPU reference", arguments: [lens35, pincushion])
    func kernelMatchesReference(tables: FujifilmRAF.LensTables) throws {
        let correction = Self.correction(tables)
        for source in [TestScene.edgeTarget.image(width: 336, height: 232), Self.image(width: 336, height: 232, Self.smooth)] {
            let applied = try #require(correction.apply(to: source.ciImage, frame: Self.frame))
            #expect(applied.extent == CGRect(x: 0, y: 0, width: 312, height: 208))
            let rendered = LensRenderingTests.renderFloat(applied)
            let expected = EmbeddedLensReference.apply(correction, to: source, frame: Self.frame)
            #expect(rendered.width == expected.width && rendered.height == expected.height)
            // Neighboring pixels differ by at most the picture's whole range.
            let bound = Self.floatBound(largestStep: 1, gain: Float(1 + (correction.gainOffsets.max() ?? 0)))
            var worst: Float = 0
            for index in rendered.pixels.indices { worst = max(worst, abs(rendered.pixels[index] - expected.pixels[index])) }
            #expect(worst <= bound, "worst \(worst), bound \(bound)")
        }
    }

    /// The app's context keeps intermediates, and may keep the lookup table,
    /// as half floats. A multiplier's offset (at most 0.08 in size here) is
    /// then off by 2⁻¹¹ of itself, 4 × 10⁻⁵, which moves a sample 190 pixels
    /// from the center by 0.008 of a pixel; the gain's offset (at most 1.6)
    /// by 2⁻¹¹ of itself, 8 × 10⁻⁴ of the value. The source and the result
    /// are each rounded once more (2⁻¹¹ of a value up to 2.6).
    @Test("In the app's half-float context the corrections stay within their derived bound")
    func halfFloatContext() throws {
        let correction = Self.correction(Self.lens35)
        let source = Self.image(width: 336, height: 232, Self.smooth)
        let applied = try #require(correction.apply(to: source.ciImage, frame: Self.frame))
        let rendered = ReferenceTests.renderLinear(applied)
        let expected = EmbeddedLensReference.apply(correction, to: source, frame: Self.frame)
        // The smooth picture's largest step between neighbors: 0.2 × (1/9 + 1/7) a pixel.
        let step: Float = 0.2 * (1 / 9 + 1 / 7)
        let bound = (0x1p-11 * 0.08 * 190 + 0x1p-22 * 336) * step * 2.6 + 0x1p-11 * 1.6 * 1.0 + 2 * 0x1p-11 * 2.6 + 1e-6
        var worst: Float = 0
        for index in rendered.pixels.indices where index % 4 != 3 {
            worst = max(worst, abs(rendered.pixels[index] - expected.pixels[index]))
        }
        #expect(worst <= bound, "worst \(worst), bound \(bound)")
    }

    /// The whole of it: a picture recorded through the lens (every recorded
    /// place shows what belongs at r / m(r), scaled, with red and blue
    /// displaced and the light falling off) comes back as the picture. This
    /// is what makes straight lines straight again; without the correction
    /// the same comparison is off by the picture's whole range.
    @Test("A picture recorded through the lens is restored", arguments: [lens35, pincushion])
    func restoresAPictureRecordedThroughTheLens(tables: FujifilmRAF.LensTables) throws {
        let correction = Self.correction(tables)
        let frame = Self.frame
        let radius = Double(hypot(frame.width, frame.height)) / 2
        // The recorded image: what each color records at a place is the picture
        // at the place that color's sample there is used for, dimmed.
        func recorded(_ x: Double, _ y: Double) -> SIMD3<Double> {
            let dx = x - Double(frame.midX), dy = y - Double(frame.midY)
            let r = hypot(dx, dy) / radius
            var out = SIMD3<Double>(0, 0, 0)
            for channel in 0..<3 {
                // This color at recorded radius r is green's light from r / (1 + shift).
                let shift = channel == 0 ? Correction.value(tables.red, knots: tables.knots, at: r)
                    : channel == 2 ? Correction.value(tables.blue, knots: tables.knots, at: r) : 0
                let green = r / (1 + shift)
                let destination = green / Correction.distortionFactor(tables, sourceRadius: green) * correction.scale
                let factor = r > 0 ? destination / r : correction.scale
                let picture = Self.smooth(Double(frame.width) / 2 + dx * factor, Double(frame.height) / 2 + dy * factor)
                out[channel] = picture[channel] * Correction.value(tables.vignetting, knots: tables.knots, at: r) / 100
            }
            return out
        }
        let source = Self.image(width: 336, height: 232, recorded)
        let applied = try #require(correction.apply(to: source.ciImage, frame: frame))
        let rendered = LensRenderingTests.renderFloat(applied)
        let uncorrected = LensRenderingTests.renderFloat(source.ciImage.cropped(to: CGRect(x: 12, y: 7, width: 312, height: 208))
            .transformed(by: CGAffineTransform(translationX: -12, y: -7)))
        // Reading the smooth picture between pixels is off by at most an eighth of
        // its curvature, 0.2 × (1/81 + 1/49) / 8 ≈ 8 × 10⁻⁴, times the gain; the shift
        // tables are evaluated at slightly different radii on the way in and out
        // (their slope, at most 0.01 per unit, times the shift, 0.002: nothing). Twice that.
        let bound = 2 * 0.2 * (1.0 / 81 + 1.0 / 49) / 8 * (1 + (correction.gainOffsets.max() ?? 0)) + 1e-4
        var worst = 0.0, worstUncorrected = 0.0
        for row in 0..<rendered.height {
            for column in 0..<rendered.width {
                let picture = Self.smooth(Double(column) + 0.5, Double(rendered.height - 1 - row) + 0.5)
                for channel in 0..<3 {
                    let index = (row * rendered.width + column) * 4 + channel
                    worst = max(worst, abs(Double(rendered.pixels[index]) - picture[channel]))
                    worstUncorrected = max(worstUncorrected, abs(Double(uncorrected.pixels[index]) - picture[channel]))
                }
            }
        }
        #expect(worst <= bound, "worst \(worst), bound \(bound)")
        #expect(worstUncorrected > 0.1, "the recorded picture is the picture already: \(worstUncorrected)")
    }

    @Test("Tables that correct nothing leave the frame's pixels as they are")
    func identityTables() throws {
        let source = TestScene.patchChart.image(width: 336, height: 232)
        let whole = CGRect(x: 12, y: 8, width: 312, height: 208)
        let correction = Correction(Self.flat, shortSideRadius: Double(whole.height / hypot(whole.width, whole.height)))
        let applied = try #require(correction.apply(to: source.ciImage, frame: whole))
        let rendered = LensRenderingTests.renderFloat(applied)
        var worst: Float = 0
        for row in 0..<208 {
            for column in 0..<312 {
                // Core Image's y 8 … 216 is rows 16 … 224 from the top of 232.
                let from = ((row + 232 - 216) * 336 + column + 12) * 4
                for channel in 0..<3 {
                    worst = max(worst, abs(rendered.pixels[(row * 312 + column) * 4 + channel] - source.pixels[from + channel]))
                }
            }
        }
        #expect(worst <= 1e-6, "\(worst)")
    }

    /// Code review C19. LibRaw's image ends at white (1). The gain used to
    /// multiply clipped values too: a blown sky was white at the center and
    /// up to 100 / vignetting times brighter toward the corners (1.73 with
    /// this lens), a ring that shows once Exposure or Highlights is pulled
    /// down. The result ends at white, as the camera's own picture does.
    @Test("A clipped area stays white wherever it lies; values under white are lifted up to it")
    func gainEndsAtWhite() throws {
        let correction = Self.correction(Self.lens35)
        let white = Self.image(width: 336, height: 232) { _, _ in SIMD3(1, 1, 1) }
        let whole = LensRenderingTests.renderFloat(try #require(correction.apply(to: white.ciImage, frame: Self.frame)))
        #expect(whole.pixels.max() == 1 && whole.pixels.min() == 1)
        #expect(EmbeddedLensReference.apply(correction, to: white, frame: Self.frame).pixels.allSatisfy { $0 == 1 })
        // A flat 0.7: lifted by the gain where that stays under white, white beyond.
        let gray = Self.image(width: 336, height: 232) { _, _ in SIMD3(0.7, 0.7, 0.7) }
        let lifted = LensRenderingTests.renderFloat(try #require(correction.apply(to: gray.ciImage, frame: Self.frame)))
        let center = lifted[156, 104], corner = lifted[1, 1], edge = lifted[156, 1]
        #expect(abs(center.x - 0.7) < 1e-3)
        // Near the middle of the top edge: that pixel's center is (0.5, 102.5) from the frame's
        // center, of a half diagonal of 187.5; green there is taken from that radius times its multiplier.
        let output = hypot(0.5, 102.5) / 187.5
        let recorded = output * correction.multipliers(atOutputRadius: output).y
        let expected = Float(min(0.7 * Correction.gain(Self.lens35, sourceRadius: recorded), 1))
        #expect(expected < 1 && expected > 0.8)
        #expect(abs(edge.y - expected) < 1e-3, "\(edge.y) against \(expected)")
        #expect(corner.x == 1 && corner.y == 1 && corner.z == 1)
        #expect(lifted.pixels.max() == 1)
        // The reference clips the same way, in a picture with clipped and unclipped parts.
        let mixed = Self.image(width: 336, height: 232) { x, y in
            let v = min(1, 0.55 + 0.5 * (sin(x / 23) * cos(y / 17) + 0.5))
            return SIMD3(v, min(1, v * 1.1), v * 0.9)
        }
        let rendered = LensRenderingTests.renderFloat(try #require(correction.apply(to: mixed.ciImage, frame: Self.frame)))
        let reference = EmbeddedLensReference.apply(correction, to: mixed, frame: Self.frame)
        let bound = Self.floatBound(largestStep: 0.5 * (1.0 / 23 + 1.0 / 17) * 1.1, gain: Float(1 + (correction.gainOffsets.max() ?? 0)))
        var worst: Float = 0
        for index in rendered.pixels.indices { worst = max(worst, abs(rendered.pixels[index] - reference.pixels[index])) }
        #expect(worst <= bound, "worst \(worst), bound \(bound)")
        #expect(rendered.pixels.max() == 1)
    }

    // MARK: What a decode does with LibRaw's image (code review C21)

    /// An X-E3's frame in LibRaw's image, a twentieth of the size: 300 x 200 at (4, 3) of 310 x 208.
    static func decodeFrame(flip: Int = 0) -> LibRawDecoder.Frame {
        LibRawDecoder.Frame(visibleWidth: 310, visibleHeight: 208, leftMargin: 0, topMargin: 6,
                            insetLeft: 0xffff, insetTop: 0xffff, insetWidth: 0, insetHeight: 0, flip: flip,
                            cameraFrame: FujifilmRAF.PixelRect(left: 4, top: 9, width: 300, height: 200))
    }

    @Test("A decode cuts the camera's frame from LibRaw's image and applies the tables it is given")
    func decodeFramesAndCorrects() throws {
        let frame = Self.decodeFrame()
        let source = Self.image(width: 310, height: 208, Self.smooth)
        let size = CGSize(width: 310, height: 208)
        // The frame in the image, from the bottom left: rows 3 … 203 from the top are y 5 … 205.
        let window = try #require(frame.windowRect(inImageOf: size))
        #expect(window == CGRect(x: 4, y: 5, width: 300, height: 200))

        // With tables: corrected, the frame's size, as the reference computes it.
        let corrected = LibRawDecoder.framed(source.ciImage, size: size, frame: frame, tables: Self.lens35)
        #expect(corrected.corrected)
        #expect(corrected.size == CGSize(width: 300, height: 200) && corrected.fullSize == CGSize(width: 300, height: 200))
        #expect(corrected.image.extent == CGRect(x: 0, y: 0, width: 300, height: 200))
        let correction = Correction(Self.lens35, shortSideRadius: 200 / hypot(300.0, 200.0))
        let reference = EmbeddedLensReference.apply(correction, to: source, frame: window)
        let rendered = LensRenderingTests.renderFloat(corrected.image)
        let bound = Self.floatBound(largestStep: 0.2 * (1.0 / 9 + 1.0 / 7), gain: Float(1 + (correction.gainOffsets.max() ?? 0)))
        var worst: Float = 0
        for index in rendered.pixels.indices { worst = max(worst, abs(rendered.pixels[index] - reference.pixels[index])) }
        #expect(worst <= bound, "worst \(worst), bound \(bound)")

        // Without tables, or with tables that correct nothing: the frame's own pixels, not counted as corrected.
        for tables in [nil, Self.flat] as [FujifilmRAF.LensTables?] {
            let cut = LibRawDecoder.framed(source.ciImage, size: size, frame: frame, tables: tables)
            #expect(!cut.corrected && cut.size == CGSize(width: 300, height: 200) && cut.fullSize == CGSize(width: 300, height: 200))
            let pixels = LensRenderingTests.renderFloat(cut.image)
            var different = 0
            for row in 0..<200 {
                for column in 0..<300 where pixels[column, row] != source[column + 4, row + 3] { different += 1 }
            }
            #expect(different == 0)
        }

        // A half-size image (155 x 104): the frame starts between two rows (y 2.5) and is
        // read between them, with or without tables, so every size shows the same frame.
        let halfSource = Self.image(width: 155, height: 104, Self.smooth)
        let halfSize = CGSize(width: 155, height: 104)
        let halfWindow = try #require(frame.windowRect(inImageOf: halfSize))
        #expect(halfWindow == CGRect(x: 2, y: 2.5, width: 150, height: 100))
        let half = LibRawDecoder.framed(halfSource.ciImage, size: halfSize, frame: frame, tables: nil)
        #expect(!half.corrected && half.size == CGSize(width: 150, height: 100) && half.fullSize == CGSize(width: 300, height: 200))
        let halfReference = EmbeddedLensReference.apply(Correction(.none, shortSideRadius: 0.55), to: halfSource, frame: halfWindow)
        let halfRendered = LensRenderingTests.renderFloat(half.image)
        worst = 0
        for index in halfRendered.pixels.indices { worst = max(worst, abs(halfRendered.pixels[index] - halfReference.pixels[index])) }
        #expect(worst <= 1e-5, "\(worst)")
        // Each row is the mean of the two it lies between.
        let mean = (halfSource[10, 11].x + halfSource[10, 12].x) / 2
        #expect(abs(halfRendered[8, 10].x - mean) <= 1e-5)
        let halfCorrected = LibRawDecoder.framed(halfSource.ciImage, size: halfSize, frame: frame, tables: Self.lens35)
        #expect(halfCorrected.corrected && halfCorrected.size == half.size)

        // A frame LibRaw cropped itself: the image as it is.
        let inset = LibRawDecoder.Frame(visibleWidth: 310, visibleHeight: 208, leftMargin: 0, topMargin: 0,
                                        insetLeft: 4, insetTop: 4, insetWidth: 300, insetHeight: 200, flip: 0)
        let untouched = LibRawDecoder.framed(source.ciImage, size: size, frame: inset, tables: Self.lens35)
        #expect(!untouched.corrected && untouched.fullSize == nil && untouched.size == size)
        #expect(untouched.image.extent == source.ciImage.extent)
    }

    @Test("A decode uses a file's tables only for the camera's own frame, in no crop mode, and made for that frame")
    func whichTablesADecodeUses() throws {
        let frame = LibRawDecoder.Frame(visibleWidth: 6032, visibleHeight: 4028, leftMargin: 0, topMargin: 6,
                                        insetLeft: 18, insetTop: 24, insetWidth: 5998, insetHeight: 3997, flip: 0,
                                        cameraFrame: FujifilmRAF.PixelRect(left: 16, top: 21, width: 6000, height: 4000))
        let file = try #require(FujifilmRAF(data: SyntheticRAF.xe3()))
        #expect(LibRawDecoder.lensTables(file, frame: frame, file: "a.RAF") == file.lens)
        #expect(LibRawDecoder.lensTables(nil, frame: frame, file: "a.RAF") == nil)
        // The 1.25x crop mode; tables for another frame; tables that correct nothing.
        #expect(LibRawDecoder.lensTables(FujifilmRAF(data: SyntheticRAF.xe3(cropMode: 2)), frame: frame, file: "a.RAF") == nil)
        var tags = SyntheticRAF.elevenKnotTags()
        tags[0].values[0] = SyntheticRAF.Rational(numerator: 2884, denominator: 11)
        #expect(LibRawDecoder.lensTables(FujifilmRAF(data: SyntheticRAF.xe3(tags: tags)), frame: frame, file: "a.RAF") == nil)
        let nothing = SyntheticRAF.elevenKnotTags(distortion: [Double](repeating: 0, count: 11), red: [Double](repeating: 0, count: 10),
                                                  blue: [Double](repeating: 0, count: 10), vignetting: [Double](repeating: 100, count: 11))
        #expect(LibRawDecoder.lensTables(FujifilmRAF(data: SyntheticRAF.xe3(tags: nothing)), frame: frame, file: "a.RAF") == nil)
        // A frame that is not the camera's (LibRaw's inset crop): the tables are centered elsewhere.
        let inset = LibRawDecoder.Frame(visibleWidth: 6032, visibleHeight: 4028, leftMargin: 0, topMargin: 6,
                                        insetLeft: 18, insetTop: 24, insetWidth: 5998, insetHeight: 3997, flip: 0)
        #expect(LibRawDecoder.lensTables(file, frame: inset, file: "a.RAF") == nil)
    }

    /// Code review C18. A Super CCD's file is read turned 45 degrees: its
    /// records are no rectangle of LibRaw's image, and as a crop box they
    /// gave a strip of the picture beside a magenta copy (FinePix F700).
    @Test("A camera frame is used only when the file's records describe the sensor LibRaw reads; a Super CCD is never cropped")
    func cameraFrameAndSensorLayout() throws {
        let file = try #require(FujifilmRAF(data: SyntheticRAF.xe3()))
        let frame = FujifilmRAF.PixelRect(left: 16, top: 21, width: 6000, height: 4000)
        #expect(LibRawDecoder.cameraFrame(file, rawWidth: 6048, rawHeight: 4038, isDiagonal: false) == frame)
        // LibRaw reads another sensor size than the records give, or the sensor is a Super CCD.
        #expect(LibRawDecoder.cameraFrame(file, rawWidth: 6160, rawHeight: 4032, isDiagonal: false) == nil)
        #expect(LibRawDecoder.cameraFrame(file, rawWidth: 4038, rawHeight: 6048, isDiagonal: false) == nil)
        #expect(LibRawDecoder.cameraFrame(file, rawWidth: 6048, rawHeight: 4038, isDiagonal: true) == nil)
        #expect(LibRawDecoder.cameraFrame(nil, rawWidth: 6048, rawHeight: 4038, isDiagonal: false) == nil)
        // A FinePix F700 as LibRaw opens it: 2832 x 1064 visible with an inset crop, a 2035 x 1533 picture.
        for flip in [0, 5, 6] {
            let turned = flip & 4 != 0
            let shown = turned ? CGSize(width: 1533, height: 2035) : CGSize(width: 2035, height: 1533)
            let diagonal = LibRawDecoder.Frame(visibleWidth: 2832, visibleHeight: 1064, leftMargin: 0, topMargin: 0,
                                               insetLeft: 100, insetTop: 50, insetWidth: 2600, insetHeight: 900, flip: flip,
                                               cameraFrame: FujifilmRAF.PixelRect(left: 0, top: 0, width: 2000, height: 1000),
                                               diagonalOutput: shown)
            #expect(diagonal.cropBox == nil && diagonal.window == nil)
            #expect(diagonal.orientedSize == shown)
            #expect(diagonal.longEdge == 2035)
            #expect(diagonal.windowRect(inImageOf: shown) == nil)
        }
    }

    /// Code review C17 (security note S1): the bridge decoded whatever size a
    /// file held, 10 GB for 192 megapixels, without the user asking.
    @Test("A sensor over 150 megapixels is refused")
    func sensorSizeLimit() {
        #expect(LibRawDecoder.maximumSensorPixels == 150_000_000)
        #expect(!LibRawDecoder.isTooLarge(rawWidth: 6048, rawHeight: 4038))
        // The largest cameras: 11656 x 8742 (102 megapixels), 14204 x 10652 (151: refused; 150 megapixel backs are 14204 x 10652 only with their margins).
        #expect(!LibRawDecoder.isTooLarge(rawWidth: 11656, rawHeight: 8742))
        #expect(!LibRawDecoder.isTooLarge(rawWidth: 15000, rawHeight: 10000))
        #expect(LibRawDecoder.isTooLarge(rawWidth: 15001, rawHeight: 10000))
        #expect(LibRawDecoder.isTooLarge(rawWidth: 16000, rawHeight: 12000))
        #expect(LibRawDecoder.isTooLarge(rawWidth: 65535, rawHeight: 65535))
        #expect(LibRawDecoder.Failure.tooLarge(megapixels: 192).description.contains("192"))
    }

    // MARK: The frame in LibRaw's image

    /// Where LibRaw puts a sensor pixel in its oriented image: for the pixel
    /// at (row, column) of its output it reads the sensor at the place
    /// `LibRaw::flip_index` gives (swap, then mirror rows, then mirror columns).
    static func sensorPlace(row: Int, column: Int, flip: Int, width: Int, height: Int) -> (row: Int, column: Int) {
        var r = row, c = column
        if flip & 4 != 0 { swap(&r, &c) }
        if flip & 2 != 0 { r = height - 1 - r }
        if flip & 1 != 0 { c = width - 1 - c }
        return (r, c)
    }

    @Test("The camera's frame is found in LibRaw's image whichever way the file is oriented", arguments: 0...7)
    func windowInOrientedImage(flip: Int) throws {
        let visible = (width: 40, height: 28)
        let camera = FujifilmRAF.PixelRect(left: 6, top: 9, width: 30, height: 16)
        // Margins of 2 and 4: the frame starts at (4, 5) of the visible area.
        let frame = LibRawDecoder.Frame(visibleWidth: visible.width, visibleHeight: visible.height, leftMargin: 2, topMargin: 4,
                                        insetLeft: 0xffff, insetTop: 0xffff, insetWidth: 0, insetHeight: 0, flip: flip,
                                        cameraFrame: camera)
        #expect(frame.window?.left == 4 && frame.window?.top == 5)
        #expect(frame.cropBox == nil)
        #expect(frame.width == 30 && frame.height == 16)
        let turned = flip & 4 != 0
        let size = turned ? CGSize(width: visible.height, height: visible.width) : CGSize(width: visible.width, height: visible.height)
        let rect = try #require(frame.windowRect(inImageOf: size))
        // Every pixel of the oriented image is in the rectangle exactly when it shows a sensor pixel of the frame.
        var mismatches = 0
        for row in 0..<Int(size.height) {
            for column in 0..<Int(size.width) {
                let place = Self.sensorPlace(row: row, column: column, flip: flip, width: visible.width, height: visible.height)
                let inFrame = (5..<21).contains(place.row) && (4..<34).contains(place.column)
                // The pixel's center in Core Image's coordinates.
                let center = CGPoint(x: CGFloat(column) + 0.5, y: size.height - CGFloat(row) - 0.5)
                if rect.contains(center) != inFrame { mismatches += 1 }
            }
        }
        #expect(mismatches == 0)
        #expect(frame.orientedSize == rect.size)
        // A half-size image: the same rectangle, halved (it may start between pixels).
        let half = try #require(frame.windowRect(inImageOf: CGSize(width: size.width / 2, height: size.height / 2)))
        #expect(half == CGRect(x: rect.minX / 2, y: rect.minY / 2, width: rect.width / 2, height: rect.height / 2))
    }

    @Test("A camera frame that is not inside LibRaw's visible area is not used")
    func cameraFrameOutsideTheVisibleArea() {
        func frame(_ camera: FujifilmRAF.PixelRect?) -> LibRawDecoder.Frame {
            LibRawDecoder.Frame(visibleWidth: 6032, visibleHeight: 4028, leftMargin: 0, topMargin: 6,
                                insetLeft: 18, insetTop: 24, insetWidth: 5998, insetHeight: 3997, flip: 0, cameraFrame: camera)
        }
        // An X-E3's file: the camera's 6000 x 4000 at (16, 21) of the sensor, (16, 15) of the visible area.
        let xe3 = frame(FujifilmRAF.PixelRect(left: 16, top: 21, width: 6000, height: 4000))
        #expect(xe3.width == 6000 && xe3.height == 4000 && xe3.cropBox == nil)
        #expect(xe3.window?.left == 16 && xe3.window?.top == 15)
        #expect(xe3.windowRect(inImageOf: CGSize(width: 6032, height: 4028)) == CGRect(x: 16, y: 13, width: 6000, height: 4000))
        #expect(xe3.windowRect(inImageOf: CGSize(width: 3016, height: 2014)) == CGRect(x: 8, y: 6.5, width: 3000, height: 2000))
        // Without one, or with one that reaches outside, LibRaw's inset crop as before.
        for camera in [nil, FujifilmRAF.PixelRect(left: 16, top: 2, width: 6000, height: 4000),
                       FujifilmRAF.PixelRect(left: 40, top: 21, width: 6000, height: 4000),
                       FujifilmRAF.PixelRect(left: 16, top: 21, width: 0, height: 4000)] {
            let other = frame(camera)
            #expect(other.window == nil && other.width == 5998 && other.height == 3997)
            #expect(other.cropBox.map { [$0.left, $0.top] } == [18, 18])
            #expect(other.windowRect(inImageOf: CGSize(width: 5998, height: 3997)) == nil)
        }
    }
}
