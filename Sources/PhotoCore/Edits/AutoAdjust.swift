import CoreImage
import Foundation

/// What the White Balance group offers a photo, and the values its controls
/// start from (white-balance-across-decoders design §2).
public enum WhiteBalanceControls: Sendable, Hashable {
    /// A raw by either decoder: the nine modes, Kelvin and tint, starting
    /// from the as-shot values.
    ///
    /// For a raw LibRaw decodes the as-shot values are the ones its color
    /// step renders (`CameraColorStep.rendered`): inside `WhiteBalance`'s
    /// ranges. A camera's own white outside them (candle light under
    /// 2000 K, a tint past ±150) is shown at the range's end, so what the
    /// sliders show, what Custom stores and what then renders are one
    /// number; As Shot itself still renders the camera's own neutral.
    case kelvin(asShot: ColorTemperature)
    /// A raw LibRaw decodes whose color data cannot be used (no matrix for
    /// the camera, no white balance coefficients): it renders as shot and
    /// white balance cannot be changed (design §6).
    case unavailable
    /// A file that is not a raw: As Shot, Auto and Custom, relative values.
    case relative

    /// - Parameters:
    ///   - systemDefaults: The system decoder's defaults, for a raw it reads.
    ///   - fallbackColor: `LibRawDecoder.cameraColor` of a raw it does not read.
    public init(systemDefaults: RawDefaults?, usesFallbackDecoder: Bool, fallbackColor: CameraColor?) {
        if let systemDefaults {
            self = .kelvin(asShot: ColorTemperature(kelvin: systemDefaults.temperature, tint: systemDefaults.tint))
        } else if usesFallbackDecoder {
            self = fallbackColor?.asShot.map { .kelvin(asShot: CameraColorStep.rendered($0)) } ?? .unavailable
        } else {
            self = .relative
        }
    }

    public var asShot: ColorTemperature? {
        if case .kelvin(let asShot) = self { return asShot }
        return nil
    }

    /// The Mode pop-up's state for a stored white balance.
    public enum Mode: Sendable, Hashable {
        /// The full list for the kind of file, `selected` chosen.
        case offered([WhiteBalance.Preset], selected: WhiteBalance.Preset)
        /// Dimmed on As Shot: nothing is stored and nothing can be (design §6, W1).
        case unavailable
        /// A white balance is stored and not applied: As Shot and the stored
        /// mode are offered, so the person can see it and remove it (W2).
        case notApplied(stored: WhiteBalance.Preset)
    }

    public func mode(for balance: WhiteBalance) -> Mode {
        switch self {
        case .kelvin: .offered(WhiteBalance.Preset.allCases, selected: balance.kelvinDisplayPreset)
        case .relative: .offered(WhiteBalance.Preset.relativePresets, selected: balance.relativeDisplayPreset)
        case .unavailable:
            balance.kelvinDisplayPreset == .asShot ? .unavailable : .notApplied(stored: balance.kelvinDisplayPreset)
        }
    }

    /// The white balance after `preset` is picked from the Mode pop-up, or
    /// nil when picking it starts a measurement instead (Auto) or changes
    /// nothing. As Shot clears the white balance. A named light source
    /// stores its Kelvin and tint on a raw.
    ///
    /// Custom on a raw, by either decoder, stores Custom with the Kelvin and
    /// tint the sliders show (design §17.1): a value already stored is kept
    /// (a Tungsten turned into Custom keeps 2850 K and 0), one that is not
    /// becomes the as-shot value, unrounded, so its slider stays on its
    /// default and the field reads what it read. The relative values are
    /// left as stored (R10). Custom then means "these numbers": the pop-up
    /// shows it (`kelvinDisplayPreset`, rule 1), and a paste carries them.
    /// On a file that is not a raw, Custom stores Custom beside the stored
    /// values (#161's D5).
    public func picking(_ preset: WhiteBalance.Preset, from balance: WhiteBalance) -> WhiteBalance? {
        switch (self, preset) {
        case (_, .asShot): return WhiteBalance()
        case (.unavailable, _), (_, .auto): return nil
        case (.kelvin(let asShot), .custom):
            var custom = balance
            custom.preset = .custom
            custom.temperature = custom.temperature ?? asShot.kelvin
            custom.tint = custom.tint ?? asShot.tint
            return custom
        case (.relative, .custom):
            var custom = balance
            custom.preset = .custom
            return custom
        case (.kelvin, _): return .raw(preset)
        case (.relative, _): return nil
        }
    }
}

/// What the RAW decoder chose for a file before any edit: shown by controls
/// whose value is "as shot" or "camera default". There are none for a raw the
/// system decoder gives no image for (`SystemRAWDecoder`): LibRaw's as-shot
/// white balance comes from `LibRawDecoder.cameraColor`
/// (`WhiteBalanceControls`), and it has no other decoder defaults.
public struct RawDefaults: Sendable, Hashable {
    public var temperature: Double
    public var tint: Double
    public var decoderVersions: [String]
    /// The version a photo without a decoder choice decodes with: the
    /// decoder's default, pinned below the machine learning version
    /// (`MachineLearningNoiseReduction.pinnedVersion`).
    public var defaultDecoderVersion: String
    /// 0 … 100, nil when the decoder does not offer it for this camera.
    public var luminanceNoiseReduction: Double?
    public var colorNoiseReduction: Double?
    /// Whether machine learning noise reduction is available for this file on this Mac.
    public var machineLearning: MachineLearningNoiseReduction.Availability
    /// Luminance's default under the machine learning decoder (nil when it
    /// is not available or does not offer the amount).
    public var machineLearningLuminanceNoiseReduction: Double?

    /// The versions the Decoder pop-up offers: the machine learning one only
    /// where it is available (ml-denoise design §4). The pop-up shows when
    /// this has more than one.
    public var offeredDecoderVersions: [String] {
        decoderVersions.filter { !MachineLearningNoiseReduction.isMachineLearningVersion($0) || machineLearning == .available }
    }

    public init(temperature: Double, tint: Double, decoderVersions: [String], defaultDecoderVersion: String,
                luminanceNoiseReduction: Double?, colorNoiseReduction: Double?,
                machineLearning: MachineLearningNoiseReduction.Availability = .notOnThisMac,
                machineLearningLuminanceNoiseReduction: Double? = nil) {
        self.temperature = temperature
        self.tint = tint
        self.decoderVersions = decoderVersions
        self.defaultDecoderVersion = defaultDecoderVersion
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.machineLearning = machineLearning
        self.machineLearningLuminanceNoiseReduction = machineLearningLuminanceNoiseReduction
    }

    /// Nil exactly when `SystemRAWDecoder.reads(source)` is false.
    public init?(source: URL) {
        guard SupportedFormats.isRaw(pathExtension: source.pathExtension), let raw = CIRAWFilter(imageURL: source),
              // Sets the filter up as an untouched photo decodes: the defaults read below are that version's.
              SystemRAWDecoder.givesImageUntouched(raw)
        else { return nil }
        let versions = raw.supportedDecoderVersions.map(\.rawValue)
        let availability = MachineLearningNoiseReduction.availability(for: source, decoderVersions: versions)
        self.init(temperature: Double(raw.neutralTemperature), tint: Double(raw.neutralTint),
                  decoderVersions: versions,
                  defaultDecoderVersion: raw.decoderVersion.rawValue,
                  luminanceNoiseReduction: raw.isLuminanceNoiseReductionSupported
                      ? Double(raw.luminanceNoiseReductionAmount) * 100 : nil,
                  colorNoiseReduction: raw.isColorNoiseReductionSupported ? Double(raw.colorNoiseReductionAmount) * 100 : nil,
                  machineLearning: availability)
        if availability == .available, let version = MachineLearningNoiseReduction.machineLearningVersion(in: versions) {
            raw.decoderVersion = CIRAWDecoderVersion(rawValue: version)
            if raw.decoderVersion.rawValue == version, raw.isLuminanceNoiseReductionSupported {
                machineLearningLuminanceNoiseReduction = Double(raw.luminanceNoiseReductionAmount) * 100
            }
        }
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

    public enum Failure: Error, Equatable {
        /// A raw LibRaw decodes whose color data cannot be used: there is no
        /// white balance to measure, and nothing is stored for it.
        case whiteBalanceUnavailable
    }

    /// A white balance that renders the image's average color neutral (grey world,
    /// ignoring clipped and very dark pixels). RAW files get a Kelvin and tint,
    /// whichever decoder reads them; other files relative shifts. The preset
    /// is `.auto`.
    public func whiteBalance(source: URL, adjustments: Adjustments) throws -> WhiteBalance {
        let engine = generator.engine
        if SupportedFormats.isRaw(pathExtension: source.pathExtension), let raw = CIRAWFilter(imageURL: source),
           SystemRAWDecoder.givesImageUntouched(raw) {
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
                return RAWDecodeGraph.output(of: raw).flatMap { PixelSample($0, engine: engine)?.neutralAverage() }
            }
            let temperature = (1_000_000 / solved.mired).rounded()
            return WhiteBalance(preset: .auto, temperature: temperature, tint: solved.tint.rounded())
        }

        let decoded = try PreviewGenerator.decode(source, longEdge: Self.measureSize, draft: true)
        if decoded.decoder == .libRaw, let camera = decoded.camera {
            // The search runs on the decode before its color step, reduced once (LibRaw's
            // smallest decode is half the sensor): each step is the color step alone.
            guard let asShot = camera.step.asShot else { throw Failure.whiteBalanceUnavailable }
            let linear = Self.reducedOnce(camera.linear, engine: engine)
            let solved = Self.neutralize(start: (1_000_000 / asShot.kelvin, asShot.tint), steps: (10, 4),
                                         mired: 1_000_000 / WhiteBalance.temperatureRange.upperBound
                                             ... 1_000_000 / WhiteBalance.temperatureRange.lowerBound,
                                         tint: WhiteBalance.tintRange) { mired, tint in
                PixelSample(camera.step.apply(to: linear, temperature: 1_000_000 / mired, tint: tint), engine: engine)?
                    .neutralAverage()
            }
            return WhiteBalance(preset: .auto, temperature: (1_000_000 / solved.mired).rounded(), tint: solved.tint.rounded())
        }
        let image = Self.reducedOnce(decoded.image, engine: engine)
        let solved = Self.neutralize(start: (0, 0), steps: (5, 5), mired: -100...100, tint: -100...100) { warmth, tint in
            let balanced = AdjustmentRenderer.relativeWhiteBalance(
                image, WhiteBalance(relativeTemperature: warmth, relativeTint: tint))
            return PixelSample(balanced, engine: engine)?.neutralAverage()
        }
        return WhiteBalance(preset: .auto, relativeTemperature: solved.mired.rounded(), relativeTint: solved.tint.rounded())
    }

    /// `image` at the measuring size, rendered once, when it is much larger: a
    /// decode that cannot be asked for a small size (LibRaw's is half the
    /// sensor at least) would otherwise be reduced again for every step of
    /// the search. Smaller images are returned as they are.
    static func reducedOnce(_ image: CIImage, engine: RenderEngine) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, max(extent.width, extent.height) > CGFloat(measureSize * 2) else { return image }
        let reduced = image.scaledToFit(longEdge: measureSize)
        let bounds = reduced.extent.integral
        guard let rendered = engine.withContext({
            $0.createCGImage(reduced, from: bounds, format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
        }) else { return image }
        return CIImage(cgImage: rendered)
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
