import CoreImage
import Foundation

/// The full-resolution pixels of the image a fringe pick samples, held while
/// a slot is picking (status.md, OQ14): half float, as the working format.
/// Immutable once made.
public final class FringeSamplePixels: Sendable {
    public let width: Int
    public let height: Int
    /// R, G, B, A half floats, rows from the top.
    private let halves: [UInt16]

    public init(width: Int, height: Int, halves: [UInt16]) {
        precondition(halves.count == width * height * 4)
        self.width = width
        self.height = height
        self.halves = halves
    }

    /// Bytes held.
    public var byteCount: Int { halves.count * MemoryLayout<UInt16>.size }

    /// The pixel's linear Rec. 2020 color, for a pixel inside the image.
    public func color(x: Int, y: Int) -> SIMD3<Double> {
        let i = (y * width + x) * 4
        return SIMD3(Self.double(halves[i]), Self.double(halves[i + 1]), Self.double(halves[i + 2]))
    }

    /// An IEEE half float from its bits.
    static func double(_ bits: UInt16) -> Double {
        let magnitude: Double
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Double(bits & 0x3FF)
        switch exponent {
        case 0: magnitude = fraction * 0x1p-24
        case 31: magnitude = fraction == 0 ? .infinity : .nan
        default: magnitude = (1 + fraction * 0x1p-10) * pow(2, Double(exponent - 15))
        }
        return bits & 0x8000 != 0 ? -magnitude : magnitude
    }
}

/// The fringe tool's use of the pixel magnifier: `pixels` as the view shows
/// them (quarter turns applied; straightening leaves a picture a few degrees
/// off the view's, prd Assumptions), the crop as its edge, the pick rule, and
/// the refusal of a spot with almost no color.
public struct FringeMagnifierTool: PixelMagnifierTool {
    public struct Image: PixelMagnifierImage {
        let pixels: FringeSamplePixels
        let crop: Crop
        /// False when the crop can leave nothing out, the usual case.
        let isCropped: Bool

        public var width: Int { crop.quarterTurns.isMultiple(of: 2) ? pixels.width : pixels.height }
        public var height: Int { crop.quarterTurns.isMultiple(of: 2) ? pixels.height : pixels.width }

        /// The sampled image's pixel shown at view pixel (x, y).
        func maskPixel(x: Int, y: Int) -> PixelPosition {
            switch crop.quarterTurns {
            case 1: PixelPosition(x: y, y: pixels.height - 1 - x)
            case 2: PixelPosition(x: pixels.width - 1 - x, y: pixels.height - 1 - y)
            case 3: PixelPosition(x: pixels.width - 1 - y, y: x)
            default: PixelPosition(x: x, y: y)
            }
        }

        public func color(x: Int, y: Int) -> SIMD3<Double>? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let mask = maskPixel(x: x, y: y)
            if isCropped {
                let w = Double(pixels.width), h = Double(pixels.height)
                let center = CGPoint(x: (Double(mask.x) + 0.5) / w, y: (Double(mask.y) + 0.5) / h)
                let output = CropGeometry.maskToOutput(center, crop: crop, sourceSize: CGSize(width: w, height: h))
                guard output.x >= 0, output.y >= 0, output.x < 1, output.y < 1 else { return nil }
            }
            return pixels.color(x: mask.x, y: mask.y)
        }
    }

    public let pixels: FringeSamplePixels
    public let crop: Crop
    private let concreteImage: Image
    private let refusal: String
    public let note: String?

    /// - Parameters:
    ///   - crop: The crop the output is cut with (`AdjustmentEditor.maskCrop`).
    ///   - note: The plate's note, in the app's words.
    ///   - refusal: The plate's words for a spot a click would refuse.
    public init(pixels: FringeSamplePixels, crop: Crop, note: String? = nil, refusal: String = "") {
        self.pixels = pixels
        self.crop = crop
        self.note = note
        self.refusal = refusal
        let isCropped = crop.angle != 0 || !(crop.rect ?? .full).isClose(to: .full)
        concreteImage = Image(pixels: pixels, crop: crop, isCropped: isCropped)
    }

    public var image: any PixelMagnifierImage { concreteImage }

    /// Photo pixels across the output (the crop's width, after quarter turns).
    public var outputPixelWidth: Double {
        (crop.rect?.width ?? 1) * Double(concreteImage.width)
    }

    /// `output` (output unit coordinates, y down) as a position in this tool's
    /// image: photo pixels, continuous, the way the view shows them.
    public func position(forOutput output: CGPoint) -> SIMD2<Double> {
        let w = Double(pixels.width), h = Double(pixels.height)
        let m = CropGeometry.outputToMask(output, crop: crop, sourceSize: CGSize(width: w, height: h))
        let x = Double(m.x) * w, y = Double(m.y) * h
        switch crop.quarterTurns {
        case 1: return SIMD2(h - y, x)
        case 2: return SIMD2(w - x, h - y)
        case 3: return SIMD2(y, w - x)
        default: return SIMD2(x, y)
        }
    }

    public func pickedPixel(at position: SIMD2<Double>, photoPixelsPerDevicePixel: Double) -> PixelPosition? {
        FringePicker.pickedPixel(at: position, photoPixelsPerDevicePixel: photoPixelsPerDevicePixel, image: concreteImage)
    }

    public func verdict(at pixel: PixelPosition) -> PixelMagnifierVerdict {
        guard let color = concreteImage.color(x: pixel.x, y: pixel.y) else { return .refused(refusal) }
        return FringePicker.chroma(of: ColorRange.okLab(linearRec2020: color)) < ColorFringes.neutralChroma ? .refused(refusal) : .fine
    }

    /// `pixel` as mask-frame unit coordinates, y down (its center).
    public func maskPoint(of pixel: PixelPosition) -> CGPoint {
        let mask = concreteImage.maskPixel(x: pixel.x, y: pixel.y)
        return CGPoint(x: (Double(mask.x) + 0.5) / Double(pixels.width),
                       y: (Double(mask.y) + 0.5) / Double(pixels.height))
    }
}

/// Picking a fringe color from the photo (design §4 "Which pixel that is",
/// §14 OQ2, §20): from the photo's data, never from screen pixels, on the
/// image the fringe step works on (`AdjustmentRenderer.fringeInput`: the
/// decoded master, aligned, before any graying and before every other
/// adjustment), at full resolution whatever the loupe shows. A spot with
/// almost no color is refused.
public enum FringePicker {
    public enum Result: Equatable, Sendable {
        /// The OkLab color to store, and the pixel it came from (mask-frame unit coordinates, y down).
        case color(SIMD3<Double>, at: CGPoint)
        /// The pixel has less than `ColorFringes.neutralChroma`.
        case almostNoColor(at: CGPoint)
    }

    public static func chroma(of lab: SIMD3<Double>) -> Double {
        (lab.y * lab.y + lab.z * lab.z).squareRoot()
    }

    /// The one rule for which pixel a click takes, used by the click and the
    /// magnifier's outline alike (ruling 18): at the view's 100 % and closer
    /// the pixel under the pointer, even when a neighbor is more colorful;
    /// zoomed out further, the most colorful photo pixel under the pointer's
    /// device pixel (`position` is that device pixel's middle), ties going
    /// to the one nearest its middle. Always a pixel of the image.
    public static func pickedPixel(at position: SIMD2<Double>, photoPixelsPerDevicePixel: Double,
                                   image: any PixelMagnifierImage) -> PixelPosition? {
        let under = PixelPosition(x: Int(position.x.rounded(.down)), y: Int(position.y.rounded(.down)))
        guard photoPixelsPerDevicePixel > 1 else { return nearestDrawn(to: under, image: image) }
        let half = photoPixelsPerDevicePixel / 2
        let minimumX = Int((position.x - half).rounded(.down)), maximumX = Int((position.x + half).rounded(.up))
        let minimumY = Int((position.y - half).rounded(.down)), maximumY = Int((position.y + half).rounded(.up))
        var best: (pixel: PixelPosition, chroma: Double, distance: Double)?
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                let dx = Double(x) + 0.5 - position.x, dy = Double(y) + 0.5 - position.y
                guard abs(dx) <= half, abs(dy) <= half, let color = image.color(x: x, y: y) else { continue }
                let chroma = Self.chroma(of: ColorRange.okLab(linearRec2020: color))
                let distance = dx * dx + dy * dy
                if let current = best, chroma < current.chroma || (chroma == current.chroma && distance >= current.distance) {
                    continue
                }
                best = (PixelPosition(x: x, y: y), chroma, distance)
            }
        }
        return best?.pixel ?? nearestDrawn(to: under, image: image)
    }

    /// `pixel` when the image shows it, else the nearest that it does (a
    /// pointer at the very edge of the photo, or of a straightened crop).
    private static func nearestDrawn(to pixel: PixelPosition, image: any PixelMagnifierImage) -> PixelPosition? {
        if image.color(x: pixel.x, y: pixel.y) != nil { return pixel }
        for ring in 1...3 {
            for y in -ring...ring {
                for x in -ring...ring where max(abs(x), abs(y)) == ring {
                    if image.color(x: pixel.x + x, y: pixel.y + y) != nil {
                        return PixelPosition(x: pixel.x + x, y: pixel.y + y)
                    }
                }
            }
        }
        return nil
    }

    /// What a click at `output` (output unit coordinates, y down) takes.
    /// `devicePixelsAcross` is the output's width on screen in device pixels.
    public static func pick(tool: FringeMagnifierTool, atOutput output: CGPoint, devicePixelsAcross: Double) -> Result? {
        let scale = tool.outputPixelWidth / max(devicePixelsAcross, 1)
        guard let pixel = tool.pickedPixel(at: tool.position(forOutput: output), photoPixelsPerDevicePixel: scale),
              let color = tool.image.color(x: pixel.x, y: pixel.y) else { return nil }
        let lab = ColorRange.okLab(linearRec2020: color)
        let at = tool.maskPoint(of: pixel)
        return chroma(of: lab) < ColorFringes.neutralChroma ? .almostNoColor(at: at) : .color(lab, at: at)
    }

    /// Renders the image picks sample for `values`, at full resolution, into
    /// memory (one render when picking starts; R20, R30, R36).
    public static func samplePixels(source: URL, values: Adjustments, generator: PreviewGenerator) throws -> FringeSamplePixels {
        guard let renderer = generator.renderer as? AdjustmentRenderer else { throw PreviewGenerator.Failure.renderFailed }
        // A raw LibRaw decodes takes no decode settings and has one frame only.
        let isRaw = SystemRAWDecoder.reads(source)
        var settings = isRaw ? renderer.decodeSettings(for: values.editStack) : .none
        // Mask-frame points are on the whole sensor, whatever the camera cropped.
        settings.fullFrame = isRaw
        let decoded = try PreviewGenerator.decode(source, longEdge: nil, draft: false, settings: settings)
        let image = renderer.fringeInput(values, to: decoded.image)
        let extent = image.extent.integral
        guard !extent.isInfinite, !extent.isEmpty else { throw PreviewGenerator.Failure.renderFailed }
        let width = Int(extent.width), height = Int(extent.height)
        let halves = [UInt16](unsafeUninitializedCapacity: width * height * 4) { buffer, count in
            generator.engine.withContext {
                $0.render(image, toBitmap: UnsafeMutableRawPointer(buffer.baseAddress!), rowBytes: width * 8, bounds: extent,
                          format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
            }
            count = width * height * 4
        }
        return FringeSamplePixels(width: width, height: height, halves: halves)
    }

    /// The slot's color as a pixel of it looks in the photo now, after the
    /// adjustments that follow the fringe step (design §14 OQ2, point 3), in
    /// linear Rec. 2020, for its swatch.
    public static func swatch(_ okLab: SIMD3<Double>, values: Adjustments, isRaw: Bool,
                              generator: PreviewGenerator) -> SIMD3<Double>? {
        guard let renderer = generator.renderer as? AdjustmentRenderer else { return nil }
        let image = renderer.swatch(okLab, values: values, context: RenderContext(isRaw: isRaw))
        var buffer = [Float](repeating: 0, count: 4)
        buffer.withUnsafeMutableBytes { bytes in
            generator.engine.withContext {
                $0.render(image, toBitmap: bytes.baseAddress!, rowBytes: 16, bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        return SIMD3(Double(buffer[0]), Double(buffer[1]), Double(buffer[2]))
    }
}
