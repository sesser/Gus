import CoreGraphics
import Foundation
import PhotoFixtures
import Testing
import UniformTypeIdentifiers
@testable import PhotoCore

/// A `LinearImage` as a magnifier image, for tests: every pixel is shown.
struct LinearMagnifierImage: PixelMagnifierImage {
    let image: LinearImage

    var width: Int { image.width }
    var height: Int { image.height }

    func color(x: Int, y: Int) -> SIMD3<Double>? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let pixel = image[x, y]
        return SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
    }
}

/// The pixel magnifier (docs/features/chromatic-aberration/prd.md R19–R36,
/// AC16–AC31): its values against a CPU reference, its picture, its rule's
/// agreement with the click, and its reuse by a tool of a test's own.
@Suite("Pixel magnifier")
struct PixelMagnifierTests {
    typealias Values = PixelMagnifierValues

    /// Scene (d) as held pixels (half float, what a pick reads), exact to half float's rounding.
    static func heldPixels(_ image: LinearImage) -> FringeSamplePixels {
        var halves = [UInt16](repeating: 0, count: image.width * image.height * 4)
        for i in image.pixels.indices {
            halves[i] = halfBits(image.pixels[i])
        }
        return FringeSamplePixels(width: image.width, height: image.height, halves: halves)
    }

    /// The bits of the half float nearest `value` (finite, |value| < 65504).
    static func halfBits(_ value: Float) -> UInt16 {
        if value == 0 { return value.sign == .minus ? 0x8000 : 0 }
        let sign: UInt16 = value < 0 ? 0x8000 : 0
        let magnitude = abs(value)
        let exponent = Int(floor(log2(magnitude)))
        if exponent < -14 {
            let fraction = (magnitude * 0x1p24).rounded()
            return sign | UInt16(fraction)
        }
        let scaled: Float = (magnitude / pow(2, Float(exponent)) - 1) * 1024
        var fraction = Int(scaled.rounded())
        var biased = exponent + 15
        if fraction == 1024 {
            fraction = 0
            biased += 1
        }
        return sign | UInt16(biased << 10) | UInt16(fraction)
    }

    static func tool(_ image: LinearImage, crop: Crop = Crop()) -> FringeMagnifierTool {
        FringeMagnifierTool(pixels: heldPixels(image), crop: crop, note: "Before edits", refusal: "Almost no color")
    }

    /// A CPU reference for the conversion: CoreGraphics takes linear Rec. 2020 to
    /// Display P3 (its own tone curve) directly.
    static func reference(_ color: SIMD3<Double>) -> (r: Int, g: Int, b: Int) {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
        let source = CGColor(colorSpace: space, components: [color.x, color.y, color.z, 1])!
        let p3 = source.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .relativeColorimetric, options: nil)!
        let c = p3.components!
        func value(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return (value(c[0]), value(c[1]), value(c[2]))
    }

    @Test("Half floats are read from their bits")
    func halfBitsDecode() {
        #expect(FringeSamplePixels.double(0x3C00) == 1)
        #expect(FringeSamplePixels.double(0xC000) == -2)
        #expect(FringeSamplePixels.double(0x3555) == 0.333_251_953_125)
        #expect(FringeSamplePixels.double(0x0001) == 0x1p-24)
        #expect(FringeSamplePixels.double(0x0400) == 0x1p-14)
        #expect(FringeSamplePixels.double(0x7C00) == .infinity)
    }

    // MARK: Values (AC19, AC20, R23, R24)

    @Test("AC19: the values match a CPU reference's conversion, within 1, on scenes (d) and (a)",
          arguments: [TestScene.pixelGrid, .fringes])
    func valuesMatchReference(scene: TestScene) {
        let image = scene.image()
        var worst = 0
        for y in stride(from: 0, to: image.height, by: 3) {
            for x in stride(from: 0, to: image.width, by: 3) {
                let pixel = image[x, y]
                let color = SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
                let values = Values(linearRec2020: color)
                let expected = Self.reference(color)
                worst = max(worst, abs(values.r - expected.r), abs(values.g - expected.g), abs(values.b - expected.b))
            }
        }
        #expect(worst <= 1, "worst \(worst)")
    }

    @Test("AC20, R23: a neutral reads R = G = B = L; beyond the range reads 0 or 255")
    func neutralsAndRange() {
        for v in stride(from: 0.0, through: 1.0, by: 1.0 / 97) {
            let values = Values(linearRec2020: SIMD3(repeating: v))
            #expect(values.r == values.g && values.g == values.b && values.b == values.l, "\(v)")
        }
        #expect(Values(linearRec2020: SIMD3(2, 2, 2)) == Values(r: 255, g: 255, b: 255, l: 255))
        #expect(Values(linearRec2020: SIMD3(-1, -1, -1)) == Values(r: 0, g: 0, b: 0, l: 0))
    }

    @Test("AC20: L is the Rec. 2020 luminance on the same curve")
    func luminanceMatchesReference() {
        let image = TestScene.pixelGrid.image()
        for (x, y) in [(10, 20), (100, 50), (200, 150)] {
            let pixel = image[x, y]
            let color = SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
            let luminance = 0.2627 * color.x + 0.678 * color.y + 0.0593 * color.z
            let expected = Int((Self.encode(luminance) * 255).rounded())
            #expect(abs(Values(linearRec2020: color).l - expected) <= 1)
        }
    }

    static func encode(_ v: Double) -> Double {
        v <= 0.003_130_8 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    // MARK: The picture (AC17, AC22, AC24)

    @Test("AC17, AC22: hard squares of level ÷ 100 device pixels, each exactly its photo pixel, at backing 1 and 2",
          arguments: PixelMagnifierLevel.allCases)
    func pictureIsHardSquares(level: PixelMagnifierLevel) {
        let image = TestScene.pixelGrid.image()
        let tool = Self.tool(image)
        let center = PixelPosition(x: 120, y: 90)
        for backing in [1, 2] {
            let deviceSize = 128 * backing
            let picture = PixelMagnifier.picture(image: tool.image, center: center, level: level, deviceSize: deviceSize)
            #expect(picture.cellSize == level.rawValue / 100)
            let bitmap = picture.bitmap(surround: (10, 20, 30))
            let middle = picture.cellsAcross / 2
            // Every cell fully on screen is one flat color: its photo pixel's.
            for row in 0..<picture.cellsAcross {
                for column in 0..<picture.cellsAcross {
                    let x0 = picture.deviceOrigin(ofCell: column), y0 = picture.deviceOrigin(ofCell: row)
                    guard x0 >= 0, y0 >= 0, x0 + picture.cellSize <= deviceSize, y0 + picture.cellSize <= deviceSize else { continue }
                    let source = tool.image.color(x: center.x + column - middle, y: center.y + row - middle)
                    let expected = source.map { Values(linearRec2020: $0) }
                    #expect(picture.cells[row * picture.cellsAcross + column] == expected)
                    guard let expected else { continue }
                    for y in y0..<(y0 + picture.cellSize) {
                        for x in x0..<(x0 + picture.cellSize) {
                            let i = (y * deviceSize + x) * 4
                            #expect(Int(bitmap[i]) == expected.r && Int(bitmap[i + 1]) == expected.g && Int(bitmap[i + 2]) == expected.b)
                        }
                    }
                }
            }
        }
    }

    @Test("AC22, DR17: the outlined pixel is the picture's middle cell at every level")
    func outlinedPixelIsTheMiddle() {
        let tool = Self.tool(TestScene.pixelGrid.image())
        for level in PixelMagnifierLevel.allCases {
            let picture = PixelMagnifier.picture(image: tool.image, center: PixelPosition(x: 50, y: 60), level: level, deviceSize: 256)
            let middle = picture.cellsAcross / 2
            let origin = picture.deviceOrigin(ofCell: middle)
            #expect(picture.cellsAcross % 2 == 1)
            #expect(origin == (256 - picture.cellSize) / 2)
        }
    }

    @Test("AC24: at the corner pixels the outlined pixel stays in the image and no pixel beyond it is drawn")
    func cornersAndBeyond() {
        let image = TestScene.pixelGrid.image()
        let tool = Self.tool(image)
        let corners: [(Int, Int)] = [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)]
        for (x, y) in corners {
            let position = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
            let reading = PixelMagnifier.reading(tool: tool, at: position, photoPixelsPerDevicePixel: 1)
            #expect(reading?.pixel == PixelPosition(x: x, y: y))
            let picture = PixelMagnifier.picture(image: tool.image, center: PixelPosition(x: x, y: y), level: .percent800, deviceSize: 256)
            let middle = picture.cellsAcross / 2
            for row in 0..<picture.cellsAcross {
                for column in 0..<picture.cellsAcross {
                    let px = x + column - middle, py = y + row - middle
                    let isInside = px >= 0 && py >= 0 && px < image.width && py < image.height
                    #expect((picture.cells[row * picture.cellsAcross + column] != nil) == isInside)
                }
            }
        }
    }

    @Test("AC24: a crop draws nothing beyond it, and the outlined pixel stays inside")
    func cropEdge() throws {
        let image = TestScene.pixelGrid.image()
        let crop = Crop(rect: CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let tool = Self.tool(image, crop: crop)
        #expect(tool.image.color(x: 63, y: 100) == nil)
        #expect(tool.image.color(x: 64, y: 100) != nil)
        // The output's top left corner is that pixel.
        let reading = try #require(PixelMagnifier.reading(tool: tool, at: tool.position(forOutput: CGPoint(x: 0, y: 0)),
                                                          photoPixelsPerDevicePixel: 1))
        #expect(reading.pixel == PixelPosition(x: 64, y: 48))
    }

    @Test("AC24: a quarter turn shows the picture the same way up as the view")
    func quarterTurn() throws {
        let image = TestScene.pixelGrid.image()
        let turned = Crop(quarterTurns: 1)
        let tool = Self.tool(image, crop: turned)
        #expect(tool.image.width == image.height && tool.image.height == image.width)
        // Output top left is the source's bottom left, a clockwise turn.
        let reading = try #require(PixelMagnifier.reading(tool: tool, at: tool.position(forOutput: CGPoint(x: 0.0001, y: 0.0001)),
                                                          photoPixelsPerDevicePixel: 1))
        #expect(tool.image.color(x: reading.pixel.x, y: reading.pixel.y) == tool.pixels.color(x: 0, y: image.height - 1))
        // One pixel to the view's right is one pixel up in the source.
        let right = tool.image.color(x: reading.pixel.x + 1, y: reading.pixel.y)
        #expect(right == tool.pixels.color(x: 0, y: image.height - 2))
    }

    // MARK: The rule and the click (AC18, AC21)

    @Test("AC18: at 100% and 800% the outline is the pixel under the pointer, and the click takes it")
    func outlineIsThePickZoomedIn() throws {
        let tool = Self.tool(TestScene.fringes.image())
        for scale in [1.0, 0.125] {
            for x in 26...33 {
                let unit = CGPoint(x: (Double(x) + 0.5) / 256, y: 60.5 / 192)
                let across = 256 / scale
                let reading = try #require(PixelMagnifier.reading(tool: tool, at: tool.position(forOutput: unit),
                                                                  photoPixelsPerDevicePixel: scale))
                #expect(reading.pixel == PixelPosition(x: x, y: 60))
                let picked = try #require(FringePicker.pick(tool: tool, atOutput: unit, devicePixelsAcross: across))
                let point: CGPoint
                switch picked {
                case .color(_, let at), .almostNoColor(let at): point = at
                }
                #expect(point == tool.maskPoint(of: reading.pixel))
            }
        }
    }

    @Test("AC18: at fit the outline is the most colorful pixel under the pointer's device pixel, and the click takes it")
    func outlineIsThePickAtFit() throws {
        let tool = Self.tool(TestScene.fringes.image())
        let across = 256.0 / 4
        // A device pixel covering columns 28 … 31: its most colorful is 31.
        let unit = CGPoint(x: 30.0 / 256, y: 60.5 / 192)
        let reading = try #require(PixelMagnifier.reading(tool: tool, at: tool.position(forOutput: unit), photoPixelsPerDevicePixel: 4))
        #expect(reading.pixel == PixelPosition(x: 31, y: 60))
        if case .color(_, let at)? = FringePicker.pick(tool: tool, atOutput: unit, devicePixelsAcross: across) {
            #expect(at == tool.maskPoint(of: reading.pixel))
        } else {
            Issue.record("the click was refused")
        }
    }

    @Test("AC21: the magnifier says a click would be refused on the light ground, and not on a fringe")
    func refusalIsKnownFirst() throws {
        let tool = Self.tool(TestScene.fringes.image())
        let ground = try #require(PixelMagnifier.reading(tool: tool, at: SIMD2(10.5, 60.5), photoPixelsPerDevicePixel: 1))
        #expect(ground.verdict == .refused("Almost no color"))
        #expect(FringePicker.pick(tool: tool, atOutput: CGPoint(x: 10.5 / 256, y: 60.5 / 192), devicePixelsAcross: 256)
            == .almostNoColor(at: tool.maskPoint(of: PixelPosition(x: 10, y: 60))))
        let fringe = try #require(PixelMagnifier.reading(tool: tool, at: SIMD2(30.5, 60.5), photoPixelsPerDevicePixel: 1))
        #expect(fringe.verdict == .fine)
        #expect(fringe.note == "Before edits")
    }

    // MARK: Level and placement (AC22, AC23, DR16)

    @Test("Levels: the list, doublings, no wrap, unknown stored values read as 800%")
    func levels() {
        #expect(PixelMagnifierLevel.allCases.map(\.rawValue) == [100, 200, 400, 800, 1600])
        #expect(PixelMagnifierLevel(stored: 0) == .percent800)
        #expect(PixelMagnifierLevel(stored: 333) == .percent800)
        #expect(PixelMagnifierLevel(stored: 400) == .percent400)
        #expect(PixelMagnifierLevel.percent1600.stepped(up: true) == nil)
        #expect(PixelMagnifierLevel.percent100.stepped(up: false) == nil)
        #expect(PixelMagnifierLevel.percent400.stepped(up: true) == .percent800)
        #expect(PixelMagnifierLevel.percent800.showsGrid && !PixelMagnifierLevel.percent400.showsGrid)
    }

    @Test("Placement: below right, flipped as a whole at the right and bottom, no flicker at the threshold, never clipped")
    func placement() {
        let canvas = CGSize(width: 1000, height: 700)
        let size = PixelMagnifierLayout.compositeSize
        let free = PixelMagnifierPlacement.place(pointer: CGPoint(x: 100, y: 100), canvas: canvas, previous: nil)
        #expect(free.origin == CGPoint(x: 120, y: 120) && !free.isLeftOfPointer && !free.isAbovePointer)
        let corner = PixelMagnifierPlacement.place(pointer: CGPoint(x: 990, y: 690), canvas: canvas, previous: nil)
        #expect(corner.isLeftOfPointer && corner.isAbovePointer)
        for pointer in [CGPoint(x: 0, y: 0), CGPoint(x: 1000, y: 0), CGPoint(x: 0, y: 700), CGPoint(x: 1000, y: 700)] {
            let placed = PixelMagnifierPlacement.place(pointer: pointer, canvas: canvas, previous: nil)
            #expect(placed.origin.x >= 8 && placed.origin.y >= 8)
            #expect(placed.origin.x + size.width <= 992 && placed.origin.y + size.height <= 692)
        }
        // The right edge's threshold: the flip holds until 24 pt to spare.
        let threshold = 1000.0 - 8 - size.width - 20
        var last = PixelMagnifierPlacement.place(pointer: CGPoint(x: threshold + 1, y: 100), canvas: canvas, previous: nil)
        #expect(last.isLeftOfPointer)
        last = PixelMagnifierPlacement.place(pointer: CGPoint(x: threshold - 1, y: 100), canvas: canvas, previous: last)
        #expect(last.isLeftOfPointer)
        last = PixelMagnifierPlacement.place(pointer: CGPoint(x: threshold - 25, y: 100), canvas: canvas, previous: last)
        #expect(!last.isLeftOfPointer)
        // A canvas too small to fit it on any side: clamped inside.
        let tiny = PixelMagnifierPlacement.place(pointer: CGPoint(x: 50, y: 50), canvas: CGSize(width: 120, height: 120), previous: nil)
        #expect(tiny.origin.x >= 0 && tiny.origin.y >= 0)
    }

    // MARK: Reuse (AC29)

    /// A tool of the test's own: its own image, and a rule that picks the
    /// darkest pixel of the 3 × 3 around the pointer, refusing bright ones.
    struct DarkestPixelTool: PixelMagnifierTool {
        let source: LinearMagnifierImage
        var image: any PixelMagnifierImage { source }
        var note: String? { nil }

        func pickedPixel(at position: SIMD2<Double>, photoPixelsPerDevicePixel: Double) -> PixelPosition? {
            let cx = Int(position.x), cy = Int(position.y)
            var best: (pixel: PixelPosition, value: Double)?
            for y in (cy - 1)...(cy + 1) {
                for x in (cx - 1)...(cx + 1) {
                    guard let color = source.color(x: x, y: y) else { continue }
                    if best == nil || color.y < best!.value { best = (PixelPosition(x: x, y: y), color.y) }
                }
            }
            return best?.pixel
        }

        func verdict(at pixel: PixelPosition) -> PixelMagnifierVerdict {
            (source.color(x: pixel.x, y: pixel.y)?.y ?? 0) > 0.5 ? .refused("Too bright") : .fine
        }
    }

    @Test("AC29: the outline and values follow a tool's own image and rule")
    func reuseByAnotherTool() throws {
        let width = 40, height = 40
        var pixels = [Float](repeating: 0.8, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 1 }
        // A dark pixel at (21, 19), one away from the pointer's (20, 20).
        pixels[(19 * width + 21) * 4 + 1] = 0.01
        let source = LinearMagnifierImage(image: LinearImage(width: width, height: height, pixels: pixels))
        let tool = DarkestPixelTool(source: source)
        let reading = try #require(PixelMagnifier.reading(tool: tool, at: SIMD2(20.5, 20.5), photoPixelsPerDevicePixel: 1))
        #expect(reading.pixel == PixelPosition(x: 21, y: 19))
        #expect(reading.values == Values(linearRec2020: SIMD3(0.8, 0.01, 0.8)))
        #expect(reading.verdict == .fine && reading.note == nil)
        let bright = try #require(PixelMagnifier.reading(tool: tool, at: SIMD2(5.5, 5.5), photoPixelsPerDevicePixel: 1))
        #expect(bright.verdict == .refused("Too bright"))
        let picture = PixelMagnifier.picture(image: tool.image, center: reading.pixel, level: .percent1600, deviceSize: 128)
        #expect(picture.cells[(picture.cellsAcross / 2) * picture.cellsAcross + picture.cellsAcross / 2] == reading.values)
    }

    // MARK: Holding the pixels (OQ14)

    @Test("OQ14: the held pixels are the decoded image, and agree with what the renderer gets")
    func samplePixelsFromAFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "d.tif")
            let image = TestScene.pixelGrid.image()
            let cgImage = try #require(image.cgImage(colorSpace: CGColorSpace(name: CGColorSpace.itur_2020)!))
            try SyntheticImages.write(cgImage, to: url, type: .tiff)
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            let held = try FringePicker.samplePixels(source: url, values: Adjustments(), generator: generator)
            #expect(held.width == image.width && held.height == image.height)
            #expect(held.byteCount == image.width * image.height * 8)
            let decoded = ReferenceTests.renderLinear(try PreviewGenerator.decode(url, longEdge: nil, draft: false).image)
            for (x, y) in [(0, 0), (255, 0), (0, 191), (100, 77)] {
                let color = held.color(x: x, y: y)
                let expected = decoded[x, y]
                #expect(abs(color.x - Double(expected.x)) <= 2e-3 && abs(color.y - Double(expected.y)) <= 2e-3
                    && abs(color.z - Double(expected.z)) <= 2e-3, "\(x),\(y)")
            }
        }
    }

    @Test("AC19: Color Alignment changes the sampled image; the magnifier is not in the stack")
    func samplingFollowsAlignmentOnly() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = folder.appending(path: "c.tif")
            let image = TestScene.lateralColor(width: 512, height: 384)
            try SyntheticImages.write(try #require(image.cgImage(colorSpace: CGColorSpace(name: CGColorSpace.itur_2020)!)), to: url, type: .tiff)
            let generator = PreviewGenerator(engine: ReferenceTests.engine)
            var edited = Adjustments()
            edited.exposure.ev = 1
            edited.presence.saturation = 40
            let plain = try FringePicker.samplePixels(source: url, values: Adjustments(), generator: generator)
            let afterEdits = try FringePicker.samplePixels(source: url, values: edited, generator: generator)
            for (x, y) in [(40, 40), (300, 200), (10, 300)] {
                #expect(plain.color(x: x, y: y) == afterEdits.color(x: x, y: y))
            }
            var aligned = Adjustments()
            aligned.colorAlignment = ColorAlignment(red: 40, blue: -30)
            let afterAlignment = try FringePicker.samplePixels(source: url, values: aligned, generator: generator)
            var changed = false
            for y in 0..<384 where !changed {
                for x in 0..<512 where plain.color(x: x, y: y) != afterAlignment.color(x: x, y: y) {
                    changed = true
                    break
                }
            }
            #expect(changed)
        }
    }
}
