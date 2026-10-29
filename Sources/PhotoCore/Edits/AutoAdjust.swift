import CoreImage
import Foundation

/// What the RAW decoder chose for a file before any edit: shown by controls
/// whose value is "as shot" or "camera default".
public struct RawDefaults: Sendable, Hashable {
    public var temperature: Double
    public var tint: Double
    public var decoderVersions: [String]
    public var defaultDecoderVersion: String
    /// 0 … 100, nil when the decoder does not offer it for this camera.
    public var luminanceNoiseReduction: Double?
    public var colorNoiseReduction: Double?

    public init(temperature: Double, tint: Double, decoderVersions: [String], defaultDecoderVersion: String,
                luminanceNoiseReduction: Double?, colorNoiseReduction: Double?) {
        self.temperature = temperature
        self.tint = tint
        self.decoderVersions = decoderVersions
        self.defaultDecoderVersion = defaultDecoderVersion
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
    }

    public init?(source: URL) {
        guard SupportedFormats.isRaw(pathExtension: source.pathExtension), let raw = CIRAWFilter(imageURL: source) else {
            return nil
        }
        self.init(temperature: Double(raw.neutralTemperature), tint: Double(raw.neutralTint),
                  decoderVersions: raw.supportedDecoderVersions.map(\.rawValue),
                  defaultDecoderVersion: raw.decoderVersion.rawValue,
                  luminanceNoiseReduction: raw.isLuminanceNoiseReductionSupported
                      ? Double(raw.luminanceNoiseReductionAmount) * 100 : nil,
                  colorNoiseReduction: raw.isColorNoiseReductionSupported ? Double(raw.colorNoiseReductionAmount) * 100 : nil)
    }
}

/// Measures an image to suggest exposure and white balance. Results are plain
/// numbers written into the adjustments, so renders stay reproducible.
public struct AutoAdjuster: Sendable {
    /// Long edge of the reduced copy that is measured.
    static let measureSize = 256

    public let generator: PreviewGenerator

    public init(generator: PreviewGenerator) {
        self.generator = generator
    }

    // MARK: Exposure

    /// Stops that bring the image's average brightness near mid grey without
    /// pushing its brightest half percent past white. Measured with every other
    /// adjustment as it is.
    public func exposure(source: URL, adjustments: Adjustments) throws -> Double {
        var measured = adjustments
        measured.exposure = Exposure()
        let image = try generator.image(source: source, stack: measured.editStack, longEdge: Self.measureSize, draft: true)
        guard let pixels = PixelSample(image, engine: generator.engine) else { return 0 }
        return Self.exposure(for: pixels.luminances())
    }

    static func exposure(for luminances: [Double]) -> Double {
        let values = luminances.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !values.isEmpty else { return 0 }
        // Geometric mean, ignoring pure black so it cannot pull the mean to zero.
        let logs = values.map { log2(max($0, 1e-4)) }
        let meanLog = logs.reduce(0, +) / Double(logs.count)
        let toMidGrey = log2(0.18) - meanLog
        let bright = values[min(values.count - 1, Int(Double(values.count) * 0.995))]
        let toClip = bright > 0 ? log2(0.98 / bright) : toMidGrey
        // Highlights may hold exposure back, but by one stop at most.
        let ev = max(min(toMidGrey, toClip), toMidGrey - 1)
        return (min(max(ev, -4), 4) * 20).rounded() / 20
    }

    // MARK: White balance

    /// A white balance that renders the image's average color neutral (grey world,
    /// ignoring clipped and very dark pixels). RAW files get a Kelvin and tint,
    /// other files relative shifts; the preset is `.auto`.
    public func whiteBalance(source: URL, adjustments: Adjustments) throws -> WhiteBalance {
        let engine = generator.engine
        if SupportedFormats.isRaw(pathExtension: source.pathExtension), let raw = CIRAWFilter(imageURL: source) {
            var settings = adjustments.decodeSettings
            settings.temperature = nil
            settings.tint = nil
            settings.apply(to: raw)
            let native = raw.nativeSize
            if native.width > 0 {
                raw.scaleFactor = Float(min(1, Double(Self.measureSize) / max(native.width, native.height)))
            }
            raw.isDraftModeEnabled = true
            let start = (mired: 1_000_000 / Double(raw.neutralTemperature), tint: Double(raw.neutralTint))
            let solved = Self.neutralize(start: start, steps: (10, 4),
                                         mired: 1_000_000 / WhiteBalance.temperatureRange.upperBound
                                             ... 1_000_000 / WhiteBalance.temperatureRange.lowerBound,
                                         tint: WhiteBalance.tintRange) { mired, tint in
                raw.neutralTemperature = Float(1_000_000 / mired)
                raw.neutralTint = Float(tint)
                return raw.outputImage.flatMap { PixelSample($0, engine: engine)?.neutralAverage() }
            }
            let temperature = (1_000_000 / solved.mired).rounded()
            return WhiteBalance(preset: .auto, temperature: temperature, tint: solved.tint.rounded())
        }

        let decoded = try PreviewGenerator.decode(source, longEdge: Self.measureSize, draft: true)
        let solved = Self.neutralize(start: (0, 0), steps: (5, 5), mired: -100...100, tint: -100...100) { warmth, tint in
            let balanced = AdjustmentRenderer.relativeWhiteBalance(
                decoded.image, WhiteBalance(relativeTemperature: warmth, relativeTint: tint))
            return PixelSample(balanced, engine: engine)?.neutralAverage()
        }
        return WhiteBalance(preset: .auto, relativeTemperature: solved.mired.rounded(), relativeTint: solved.tint.rounded())
    }

    /// Newton iterations on two parameters (with finite-difference slopes) that
    /// drive the blue/red and green/magenta balance of `measure` to zero.
    static func neutralize(start: (mired: Double, tint: Double), steps: (Double, Double),
                           mired miredRange: ClosedRange<Double>, tint tintRange: ClosedRange<Double>,
                           measure: (Double, Double) -> SIMD3<Double>?) -> (mired: Double, tint: Double) {
        func error(_ a: Double, _ b: Double) -> SIMD2<Double>? {
            guard let rgb = measure(a, b), rgb.x > 0, rgb.y > 0, rgb.z > 0 else { return nil }
            return SIMD2(log(rgb.z / rgb.x), log(rgb.y / (rgb.x * rgb.z).squareRoot()))
        }
        var a = start.mired
        var b = start.tint
        for _ in 0..<6 {
            guard let e = error(a, b) else { break }
            if abs(e.x) < 0.005 && abs(e.y) < 0.005 { break }
            guard let ea = error(a + steps.0, b), let eb = error(a, b + steps.1) else { break }
            let da = (ea - e) / steps.0
            let db = (eb - e) / steps.1
            let determinant = da.x * db.y - db.x * da.y
            guard abs(determinant) > 1e-12 else { break }
            // Solve J · Δ = −e.
            let deltaA = (-e.x * db.y + db.x * e.y) / determinant
            let deltaB = (-da.x * e.y + e.x * da.y) / determinant
            a = min(max(a + deltaA, miredRange.lowerBound), miredRange.upperBound)
            b = min(max(b + deltaB, tintRange.lowerBound), tintRange.upperBound)
        }
        return (a, b)
    }
}

/// A small render read back as linear working-space floats.
struct PixelSample {
    let rgba: [Float]

    init?(_ image: CIImage, engine: RenderEngine) {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return nil }
        var reduced = image
        let longest = max(extent.width, extent.height)
        if longest > CGFloat(AutoAdjuster.measureSize) {
            reduced = image.scaledToFit(longEdge: AutoAdjuster.measureSize)
        } else {
            reduced = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        }
        let bounds = reduced.extent.integral
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }
        var buffer = [Float](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { bytes in
            engine.withContext {
                $0.render(reduced, toBitmap: bytes.baseAddress!, rowBytes: width * 16, bounds: bounds,
                          format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
            }
        }
        rgba = buffer
    }

    /// Rec. 2020 luminance of every pixel.
    func luminances() -> [Double] {
        stride(from: 0, to: rgba.count, by: 4).map {
            0.2627 * Double(rgba[$0]) + 0.6780 * Double(rgba[$0 + 1]) + 0.0593 * Double(rgba[$0 + 2])
        }
    }

    /// Mean color of the pixels that are neither nearly black nor clipped.
    func neutralAverage() -> SIMD3<Double>? {
        var sum = SIMD3<Double>(0, 0, 0)
        var count = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let pixel = SIMD3(Double(rgba[i]), Double(rgba[i + 1]), Double(rgba[i + 2]))
            let high = max(pixel.x, pixel.y, pixel.z)
            if high > 0.95 || high < 0.01 { continue }
            sum += pixel
            count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }
}
