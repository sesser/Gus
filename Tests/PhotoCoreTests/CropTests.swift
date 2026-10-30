import CoreImage
import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

@Suite("Crop")
struct CropTests {
    // MARK: Values

    @Test func noCropLeavesTheStackAlone() {
        #expect(Adjustments().editStack == .identity)
        #expect(Adjustments().decodeSettings.fullFrame == false)
    }

    @Test func cropRoundTripsAndComesFirst() throws {
        var adjustments = Adjustments()
        adjustments.exposure.ev = 0.3
        adjustments.crop = Crop(rect: CropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6), quarterTurns: 3, angle: -4.5)
        let stack = adjustments.editStack
        #expect(stack.operations.map(\.kind.rawValue) == ["crop", "exposure"])
        #expect(stack.operations[0].parameters == [
            "x": .number(0.1), "y": .number(0.2), "width": .number(0.5), "height": .number(0.6),
            "quarterTurns": .number(3), "angle": .number(-4.5),
        ])
        #expect(Adjustments(stack: try EditStack.decode(from: try stack.jsonData())) == adjustments)
        #expect(adjustments.decodeSettings.fullFrame)
    }

    @Test func turnsAloneKeepTheWholeFrame() {
        var adjustments = Adjustments()
        adjustments.crop.quarterTurns = 1
        let parameters = adjustments.editStack.operations[0].parameters
        #expect(parameters == ["quarterTurns": .number(1)])
        #expect(Adjustments(stack: adjustments.editStack).crop == Crop(quarterTurns: 1))
    }

    @Test func storedValuesAreKeptInRange() {
        let operation = EditOperation(kind: Crop.kind, parameters: [
            "quarterTurns": .number(-1), "angle": .number(90), "x": .number(0), "y": .number(0),
            "width": .number(0), "height": .number(1),
        ])
        let crop = Adjustments(stack: EditStack(operations: [operation])).crop
        #expect(crop.quarterTurns == 3)
        #expect(crop.angle == 45)
        #expect(crop.rect == nil)
    }

    @Test func presetsNeverCarryOrReplaceTheCrop() {
        var source = Adjustments()
        source.crop = Crop(rect: CropRect(x: 0, y: 0, width: 0.5, height: 0.5))
        source.exposure.ev = 1
        let preset = AdjustmentPreset(name: "P", adjustments: source)
        #expect(preset.adjustments.crop.isIdentity)
        #expect(preset.adjustments.exposure.ev == 1)

        var target = Adjustments()
        target.crop = Crop(quarterTurns: 2)
        #expect(preset.applied(onto: target).crop == Crop(quarterTurns: 2))
        #expect(source.pasted(onto: target).crop == source.crop)
        #expect(!source.modifiedGroups.isEmpty)
        #expect(Adjustments(stack: EditStack(operations: source.preserved)).crop.isIdentity)
    }

    // MARK: Rectangles

    @Test func quarterTurnsOfARectangle() {
        let rect = CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(rect.turned(clockwise: true).isClose(to: CropRect(x: 0.4, y: 0.1, width: 0.4, height: 0.3)))
        #expect(rect.turned(clockwise: true).turned(clockwise: false).isClose(to: rect))
        var turned = rect
        for _ in 0..<4 { turned = turned.turned(clockwise: true) }
        #expect(turned.isClose(to: rect))
    }

    @Test func orientingASensorRectangle() {
        let rect = CropRect(x: 0, y: 0.125, width: 1, height: 0.75)
        #expect(rect.oriented(.up) == rect)
        #expect(rect.oriented(.down).isClose(to: CropRect(x: 0, y: 0.125, width: 1, height: 0.75)))
        #expect(rect.oriented(.right).isClose(to: CropRect(x: 0.125, y: 0, width: 0.75, height: 1)))
        #expect(rect.oriented(.left).isClose(to: CropRect(x: 0.125, y: 0, width: 0.75, height: 1)))
        let corner = CropRect(x: 0, y: 0, width: 0.5, height: 0.25)
        #expect(corner.oriented(.right).isClose(to: CropRect(x: 0.75, y: 0, width: 0.25, height: 0.5)))
        #expect(corner.oriented(.left).isClose(to: CropRect(x: 0, y: 0.5, width: 0.25, height: 0.5)))
        #expect(corner.oriented(.upMirrored).isClose(to: CropRect(x: 0.5, y: 0, width: 0.5, height: 0.25)))
    }

    @Test func sourceZoomFollowsTheKeptPart() {
        #expect(Crop(quarterTurns: 1).sourceZoom(sourceSize: CGSize(width: 300, height: 200)) == 1)
        let half = Crop(rect: CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(abs(half.sourceZoom(sourceSize: CGSize(width: 300, height: 200)) - 2) < 1e-9)
        // A tall strip of a landscape frame: its height is the long edge kept.
        let strip = Crop(rect: CropRect(x: 0.4, y: 0, width: 0.2, height: 1))
        #expect(abs(strip.sourceZoom(sourceSize: CGSize(width: 300, height: 200)) - 1.5) < 1e-9)
    }

    // MARK: Rendering

    /// A `width` × `height` image whose left half is red and right half blue.
    private func halves(width: CGFloat, height: CGFloat) -> CIImage {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: width / 2, height: height))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return red.composited(over: blue)
    }

    /// RGBA8 pixels, top row first.
    private func pixels(_ image: CIImage) -> (width: Int, data: [UInt8]) {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &data, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: nil)
        return (width, data)
    }

    private func color(_ pixels: (width: Int, data: [UInt8]), x: Int, y: Int) -> [UInt8] {
        let index = (y * pixels.width + x) * 4
        return Array(pixels.data[index..<index + 3])
    }

    @Test func aClockwiseTurnPutsTheLeftSideOnTop() {
        let image = Crop(quarterTurns: 1).apply(to: halves(width: 40, height: 20))
        #expect(image.extent == CGRect(x: 0, y: 0, width: 20, height: 40))
        let rendered = pixels(image)
        #expect(color(rendered, x: 10, y: 5) == [255, 0, 0])
        #expect(color(rendered, x: 10, y: 35) == [0, 0, 255])
    }

    @Test func theRectangleIsCutFromTheTopLeft() {
        // The top left quarter of a 40 × 20 image: all red.
        let image = Crop(rect: CropRect(x: 0, y: 0, width: 0.5, height: 0.5)).apply(to: halves(width: 40, height: 20))
        #expect(image.extent == CGRect(x: 0, y: 0, width: 20, height: 10))
        let rendered = pixels(image)
        #expect(color(rendered, x: 2, y: 2) == [255, 0, 0])
        #expect(color(rendered, x: 18, y: 8) == [255, 0, 0])

        let right = Crop(rect: CropRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5)).apply(to: halves(width: 40, height: 20))
        #expect(right.extent.size == CGSize(width: 10, height: 10))
        #expect(color(pixels(right), x: 5, y: 5) == [0, 0, 255])
    }

    @Test func straighteningKeepsTheRectangleSize() {
        let source = halves(width: 400, height: 200)
        let size = CGSize(width: 400, height: 200)
        let rect = CropGeometry.fitted(.full, angle: 5, size: size)
        let image = Crop(rect: rect, angle: 5).apply(to: source)
        #expect(abs(image.extent.width - rect.width * 400) <= 1)
        #expect(abs(image.extent.height - rect.height * 200) <= 1)
        #expect(image.extent.origin == .zero)
    }

    @Test func theRendererCropsBeforeTheOtherSteps() throws {
        var adjustments = Adjustments()
        adjustments.crop = Crop(rect: CropRect(x: 0, y: 0, width: 0.5, height: 1), quarterTurns: 1)
        adjustments.vignette.amount = -50
        let image = try AdjustmentRenderer().apply(adjustments.editStack, to: halves(width: 40, height: 20))
        #expect(image.extent == CGRect(x: 0, y: 0, width: 10, height: 40))
    }

    @Test func croppedPreviewsDecodeLarger() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "a.jpg")
        try SyntheticImages.writeJPEG(to: url, width: 1200, height: 800, seed: 1)
        let generator = PreviewGenerator()
        var adjustments = Adjustments()
        #expect(generator.decodeLongEdge(url, stack: adjustments.editStack, longEdge: 300) == 300)
        adjustments.crop = Crop(rect: CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(generator.decodeLongEdge(url, stack: adjustments.editStack, longEdge: 300) == 600)
        let image = try generator.image(source: url, stack: adjustments.editStack, longEdge: 300)
        #expect(max(image.extent.width, image.extent.height) == 300)
        #expect(abs(image.extent.width / image.extent.height - 1.5) < 0.02)
    }

    // MARK: Geometry

    private let size = CGSize(width: 300, height: 200)

    @Test func theWholeFrameFitsOnlyUnrotated() {
        #expect(CropGeometry.fits(.full, angle: 0, size: size))
        #expect(!CropGeometry.fits(.full, angle: 3, size: size))
        #expect(!CropGeometry.fits(CropRect(x: -0.01, y: 0, width: 0.5, height: 0.5), angle: 0, size: size))
    }

    @Test func fittingShrinksAboutTheCenter() {
        for angle in [-45.0, -10, 2, 30] {
            let fitted = CropGeometry.fitted(.full, angle: angle, size: size)
            #expect(CropGeometry.fits(fitted, angle: angle, size: size))
            #expect(abs(fitted.midX - 0.5) < 1e-9 && abs(fitted.midY - 0.5) < 1e-9)
            #expect(abs(CropGeometry.ratio(of: fitted, size: size) - 1.5) < 1e-6)
            #expect(fitted.width < 1)
            // As large as it can be: a little larger no longer fits.
            let larger = CropRect(x: fitted.x - 0.001, y: fitted.y - 0.001, width: fitted.width + 0.002,
                                  height: fitted.height + 0.002)
            #expect(!CropGeometry.fits(larger, angle: angle, size: size))
        }
        #expect(CropGeometry.fitted(.full, angle: 0, size: size).isClose(to: .full))
    }

    @Test func fittingMovesAnOffImageCenterIn() {
        let outside = CropRect(x: 0.95, y: -0.2, width: 0.2, height: 0.2)
        let fitted = CropGeometry.fitted(outside, angle: 20, size: size)
        #expect(CropGeometry.fits(fitted, angle: 20, size: size))
        #expect(fitted.width > 0)
    }

    @Test func largestAndConstrainedRectangles() {
        let square = CropGeometry.largest(ratio: 1, angle: 0, size: size)
        #expect(square.isClose(to: CropRect(x: 1.0 / 6, y: 0, width: 2.0 / 3, height: 1)))
        let wide = CropGeometry.constrained(.full, to: 16.0 / 9, angle: 0, size: size)
        #expect(abs(CropGeometry.ratio(of: wide, size: size) - 16.0 / 9) < 1e-9)
        #expect(abs(wide.width - 1) < 1e-9 && abs(wide.midY - 0.5) < 1e-9)
        let tilted = CropGeometry.largest(ratio: 1, angle: 12, size: size)
        #expect(CropGeometry.fits(tilted, angle: 12, size: size))
        #expect(abs(CropGeometry.ratio(of: tilted, size: size) - 1) < 1e-6)
        let portrait = CropGeometry.flipped(wide, angle: 0, size: size)
        #expect(abs(CropGeometry.ratio(of: portrait, size: size) - 9.0 / 16) < 1e-6)
        #expect(CropGeometry.fits(portrait, angle: 0, size: size))
    }

    @Test func movingStopsAtTheEdgeAndSlides() {
        let rect = CropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        #expect(CropGeometry.moved(rect, dx: 0.1, dy: 0.05, angle: 0, size: size)
            .isClose(to: CropRect(x: 0.3, y: 0.25, width: 0.4, height: 0.4)))
        let moved = CropGeometry.moved(rect, dx: 1, dy: 0.1, angle: 0, size: size)
        #expect(abs(moved.x - 0.6) < 1e-6)
        #expect(abs(moved.y - 0.3) < 1e-6)
        #expect(CropGeometry.moved(.full, dx: 0.2, dy: 0, angle: 0, size: size).isClose(to: .full))
    }

    @Test func resizingFollowsThePointerWithinTheImage() {
        let rect = CropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let free = CropGeometry.resized(rect, handle: .bottomRight, to: CGPoint(x: 0.8, y: 0.7), ratio: nil, angle: 0, size: size)
        #expect(free.isClose(to: CropRect(x: 0.2, y: 0.2, width: 0.6, height: 0.5)))
        let past = CropGeometry.resized(rect, handle: .right, to: CGPoint(x: 1.5, y: 0.5), ratio: nil, angle: 0, size: size)
        #expect(abs(past.x + past.width - 1) < 1e-6)
        let tiny = CropGeometry.resized(rect, handle: .left, to: CGPoint(x: 0.9, y: 0.5), ratio: nil, angle: 0, size: size)
        #expect(abs(tiny.width * size.width - CropGeometry.minimumEdge(size)) < 1e-6)

        let square = CropGeometry.largest(ratio: 1, angle: 0, size: size)
        let corner = CropGeometry.resized(square, handle: .topLeft, to: CGPoint(x: 0.5, y: 0.3), ratio: 1, angle: 0, size: size)
        #expect(abs(CropGeometry.ratio(of: corner, size: size) - 1) < 1e-6)
        #expect(abs(corner.x + corner.width - (square.x + square.width)) < 1e-9)
        let edge = CropGeometry.resized(square, handle: .bottom, to: CGPoint(x: 0.5, y: 0.5), ratio: 1, angle: 0, size: size)
        #expect(abs(CropGeometry.ratio(of: edge, size: size) - 1) < 1e-6)
        #expect(abs(edge.midX - square.midX) < 1e-9)
        let tilted = CropGeometry.resized(CropGeometry.fitted(.full, angle: 10, size: size), handle: .topRight,
                                          to: CGPoint(x: 1.2, y: -0.2), ratio: nil, angle: 10, size: size)
        #expect(CropGeometry.fits(tilted, angle: 10, size: size))
    }

    // MARK: Camera frames

    @Test func readsAnOlympusAspectFrame() throws {
        let url = try Self.writeORF(frame: [0, 486, 5183, 3401], orientation: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = try #require(CameraFrame(contentsOf: url))
        #expect(!frame.isFullFrame)
        #expect(frame.rect.isClose(to: CropRect(x: 0, y: 0.125, width: 1, height: 0.75)))
        #expect(CameraFrame.rect(of: url)?.isClose(to: frame.rect) == true)

        let data = try #require(frame.fullFrameData(of: url))
        let original = try Data(contentsOf: url)
        #expect(data.count == original.count)
        let start = Int(frame.patches[0].offset)
        #expect(Array(data[start..<start + 8]) == [0, 0, 0, 0, 0x3F, 0x14, 0x2F, 0x0F])
        #expect(data.prefix(start) == original.prefix(start))
        #expect(data.dropFirst(start + 8) == original.dropFirst(start + 8))
    }

    @Test func aPortraitFrameIsOriented() throws {
        let url = try Self.writeORF(frame: [0, 486, 5183, 3401], orientation: 6, omSystem: true)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CameraFrame.rect(of: url)?.isClose(to: CropRect(x: 0.125, y: 0, width: 0.75, height: 1)) == true)
    }

    @Test func aFullFrameOrAnotherFormatHasNoCameraCrop() throws {
        let url = try Self.writeORF(frame: [0, 0, 5183, 3887], orientation: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CameraFrame(contentsOf: url)?.isFullFrame == true)
        #expect(CameraFrame.rect(of: url) == nil)
        let renamed = url.deletingPathExtension().appendingPathExtension("dng")
        try FileManager.default.copyItem(at: url, to: renamed)
        defer { try? FileManager.default.removeItem(at: renamed) }
        #expect(CameraFrame(contentsOf: renamed) == nil)
    }

    @Test func readsAPanasonicCrop() throws {
        // A GX7 Mark II at 16:9: sensor rows 8 … 3456, kept 440 … 3024.
        let url = try Self.writeRW2(crop: [440, 8, 3024, 4600])
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = try #require(CameraFrame(contentsOf: url))
        #expect(!frame.isFullFrame)
        #expect(frame.size == CGSize(width: 4592, height: 3448))
        #expect(frame.rect.isClose(to: CropRect(x: 0, y: 432.0 / 3448, width: 1, height: 2584.0 / 3448)))

        let data = try #require(frame.fullFrameData(of: url))
        let patchedURL = try Self.write(data, extension: "rw2")
        defer { try? FileManager.default.removeItem(at: patchedURL) }
        #expect(CameraFrame(contentsOf: patchedURL)?.isFullFrame == true)
        #expect(data.count == (try Data(contentsOf: url)).count)
    }

    @Test func aPanasonicFullFrameAndAnOrientedOne() throws {
        let full = try Self.writeRW2(crop: [8, 8, 3456, 4600])
        defer { try? FileManager.default.removeItem(at: full) }
        #expect(CameraFrame(contentsOf: full)?.isFullFrame == true)
        #expect(CameraFrame.rect(of: full) == nil)

        let portrait = try Self.writeRW2(crop: [440, 8, 3024, 4600], orientation: 8)
        defer { try? FileManager.default.removeItem(at: portrait) }
        #expect(CameraFrame.rect(of: portrait)?.isClose(to: CropRect(x: 432.0 / 3448, y: 0, width: 2584.0 / 3448, height: 1))
                == true)
    }

    /// A little-endian RW2 skeleton: IFD0 with the sensor borders 8, 8, 3456,
    /// 4600 and `crop` (top, left, bottom, right), all SHORT values in place.
    static func writeRW2(crop: [UInt16], orientation: UInt16? = nil) throws -> URL {
        var data = Data()
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        var entries: [(UInt16, UInt16)] = [(0x04, 8), (0x05, 8), (0x06, 3456), (0x07, 4600),
                                           (0x2F, crop[0]), (0x30, crop[1]), (0x31, crop[2]), (0x32, crop[3])]
        if let orientation { entries.append((0x0112, orientation)) }
        data.append(contentsOf: [0x49, 0x49, 0x55, 0x00])
        u32(8)
        u16(UInt16(entries.count))
        for (tag, value) in entries {
            u16(tag); u16(3); u32(1); u16(value); u16(0)
        }
        u32(0)
        return try write(data, extension: "rw2")
    }

    static func write(_ data: Data, extension pathExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(pathExtension)")
        try data.write(to: url)
        return url
    }

    /// A little-endian ORF skeleton: IFD0 (orientation, Exif pointer), the Exif
    /// IFD with a maker note, and the maker note's image processing IFD with
    /// the full size and `frame`.
    static func writeORF(frame: [UInt16], orientation: UInt16, omSystem: Bool = false) throws -> URL {
        var data = Data()
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func entry(_ tag: UInt16, _ type: UInt16, _ count: UInt32, _ value: UInt32) {
            u16(tag); u16(type); u32(count); u32(value)
        }
        data.append(contentsOf: Array("IIRO".utf8))
        u32(8)
        // IFD0 at 8: two entries, then the next-IFD offset.
        u16(2)
        entry(0x0112, 3, 1, UInt32(orientation))
        entry(0x8769, 4, 1, 38)
        u32(0)
        // Exif IFD at 38: the maker note at 56.
        let noteStart: UInt32 = 56
        let header = omSystem ? Array("OM SYSTEM\0\0\0II".utf8) + [4, 0] : Array("OLYMPUS\0II".utf8) + [3, 0]
        let ifdOffset = UInt32(header.count)
        // Maker note: header, IFD (1 entry), image processing IFD (3 entries), frame values.
        let processingOffset = ifdOffset + 2 + 12 + 4
        let frameOffset = processingOffset + 2 + 3 * 12 + 4
        let noteLength = frameOffset + 8
        u16(1)
        entry(0x927C, 7, noteLength, noteStart)
        u32(0)
        #expect(UInt32(data.count) == noteStart)
        data.append(contentsOf: header)
        u16(1)
        entry(0x2040, 13, 1, processingOffset)
        u32(0)
        u16(3)
        entry(0x0614, 4, 1, 5184)
        entry(0x0615, 4, 1, 3888)
        entry(0x1113, 3, 4, frameOffset)
        u32(0)
        for value in frame { u16(value) }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).orf")
        try data.write(to: url)
        return url
    }
}
