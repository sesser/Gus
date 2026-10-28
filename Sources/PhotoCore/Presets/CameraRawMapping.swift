import Foundation

/// Kinds of Camera Raw settings that have no equivalent here, or only an
/// approximate one. An import reports them when a preset changes them.
public enum CameraRawFeature: String, CaseIterable, Sendable {
    /// Auto white balance or auto tone, measured per photo there.
    case autoSettings
    /// A camera profile or creative look other than the standard ones.
    case profile
    case texture
    /// Camera calibration (primaries and shadow tint).
    case calibration
    /// The global wheel of color grading.
    case globalColorGrade
    /// Point color, or other targeted color ranges.
    case pointColor
    /// Black-and-white conversion, approximated by desaturating after the mixer.
    case blackAndWhite
    /// Masks, gradients and brushes.
    case localAdjustments
    /// Spot removal and other retouching.
    case retouching
    case crop
    /// Lens profiles, distortion, lens vignetting, chromatic aberration.
    case lensCorrections
    /// Perspective and upright corrections.
    case transform
    case defringe
    /// Vignette feather, style and highlight protection.
    case vignetteStyle
    /// Settings of process versions before 2012, mapped as if they were current.
    case legacyProcess
}

/// A Camera Raw preset converted to adjustments.
public struct CameraRawConversion: Sendable {
    public var adjustments: Adjustments
    /// The groups the preset sets, which applying it replaces.
    public var groups: Set<Adjustments.Group>
    /// What it changes that could not be carried over exactly.
    public var unsupported: Set<CameraRawFeature>
}

/// Maps Camera Raw settings onto adjustment modules. The two share most
/// controls and their ranges (−100 … +100, stops, Kelvin, 0 … 255 curves);
/// the rendering differs, so a converted preset is close rather than identical.
/// Only groups the preset names are included, as only those change when it
/// is applied there.
public enum CameraRawMapping {
    public static func convert(_ settings: CameraRawSettings) -> CameraRawConversion {
        var converter = Converter(values: settings.values)
        converter.run()
        return CameraRawConversion(adjustments: converter.adjustments, groups: converter.groups,
                                   unsupported: converter.unsupported)
    }

    /// Band names as the format spells them (HueAdjustmentRed, GrayMixerAqua, …).
    static func formatName(_ band: ColorMixer.Band) -> String {
        band.rawValue.prefix(1).uppercased() + band.rawValue.dropFirst()
    }

    private struct Converter {
        let values: [String: CameraRawValue]
        var adjustments = Adjustments()
        var groups = Set<Adjustments.Group>()
        var unsupported = Set<CameraRawFeature>()

        func number(_ key: String) -> Double? { values[key]?.number }

        func has(_ keys: [String]) -> Bool { keys.contains { values[$0] != nil } }

        /// True when any of `keys` is set to something other than `neutral`.
        func changes(_ keys: [String], from neutral: Double = 0) -> Bool {
            keys.contains { key in number(key).map { abs($0 - neutral) > 1e-6 } ?? false }
        }

        func clamped(_ key: String, _ range: ClosedRange<Double> = -100...100) -> Double? {
            number(key).map { min(max($0, range.lowerBound), range.upperBound) }
        }

        var isGrayscale: Bool { values["ConvertToGrayscale"]?.bool == true || profileName?.lowercased().contains("monochrome") == true }

        /// The profile: the look's name (newer presets) or the camera profile.
        var profileName: String? {
            if let look = values["Look"]?.record, let name = look["Name"]?.string, !name.isEmpty { return name }
            return values["CameraProfile"]?.string
        }

        mutating func run() {
            profile()
            whiteBalance()
            light()
            presence()
            toneCurve()
            colorMixer()
            colorGrade()
            details()
            effects()
            notes()
        }

        mutating func profile() {
            guard let name = profileName?.lowercased() else { return }
            let look: RawDecode.Look?
            if name.contains("flat") {
                look = .flat
            } else if name.contains("neutral") {
                look = .neutral
            } else if ["standard", "adobe color", "default", "embedded", "monochrome"].contains(where: name.contains) {
                look = .standard
            } else {
                look = nil
            }
            if let look {
                adjustments.decode.look = look
                groups.insert(.profile)
            } else {
                unsupported.insert(.profile)
            }
        }

        mutating func whiteBalance() {
            guard has(["WhiteBalance", "Temperature", "Tint", "IncrementalTemperature", "IncrementalTint"]) else { return }
            groups.insert(.whiteBalance)
            var balance = WhiteBalance()
            switch values["WhiteBalance"]?.string ?? (has(["Temperature", "Tint"]) ? "Custom" : "As Shot") {
            case "Auto":
                unsupported.insert(.autoSettings)
            case "Daylight": balance = .raw(.daylight)
            case "Cloudy": balance = .raw(.cloudy)
            case "Shade": balance = .raw(.shade)
            case "Tungsten": balance = .raw(.tungsten)
            case "Fluorescent": balance = .raw(.fluorescent)
            case "Flash": balance = .raw(.flash)
            case "Custom":
                balance.preset = .custom
                balance.temperature = clamped("Temperature", WhiteBalance.temperatureRange)
                balance.tint = clamped("Tint", WhiteBalance.tintRange)
            default: break
            }
            balance.relativeTemperature = clamped("IncrementalTemperature") ?? 0
            balance.relativeTint = clamped("IncrementalTint") ?? 0
            adjustments.whiteBalance = balance
        }

        mutating func light() {
            let keys = ["Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012"]
            if has(keys) {
                groups.insert(.light)
                adjustments.exposure.ev = clamped("Exposure2012", Exposure.range) ?? 0
                adjustments.tone = Tone(contrast: clamped("Contrast2012") ?? 0, highlights: clamped("Highlights2012") ?? 0,
                                        shadows: clamped("Shadows2012") ?? 0, whites: clamped("Whites2012") ?? 0,
                                        blacks: clamped("Blacks2012") ?? 0)
            } else if has(["Exposure"]) {
                groups.insert(.light)
                adjustments.exposure.ev = clamped("Exposure", Exposure.range) ?? 0
            }
        }

        mutating func presence() {
            if has(["Clarity2012", "Clarity", "Dehaze", "Vibrance", "Saturation"]) {
                groups.insert(.presence)
                adjustments.presence = Presence(clarity: clamped("Clarity2012") ?? clamped("Clarity") ?? 0,
                                                dehaze: clamped("Dehaze") ?? 0, vibrance: clamped("Vibrance") ?? 0,
                                                saturation: clamped("Saturation") ?? 0)
            }
            if isGrayscale {
                groups.insert(.presence)
                adjustments.presence.vibrance = 0
                adjustments.presence.saturation = -100
            }
        }

        mutating func toneCurve() {
            let channels: [(ToneCurve.Channel, String)] = [
                (.rgb, "ToneCurvePV2012"), (.red, "ToneCurvePV2012Red"),
                (.green, "ToneCurvePV2012Green"), (.blue, "ToneCurvePV2012Blue"),
            ]
            let parametric = ["ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights"]
            guard has(channels.map(\.1) + parametric) else { return }
            groups.insert(.toneCurve)
            for (channel, key) in channels {
                if let points = values[key].flatMap(Self.curvePoints) { adjustments.toneCurve[channel] = points }
            }
            if changes(parametric) {
                adjustments.toneCurve.rgb = ParametricCurve(
                    shadows: number("ParametricShadows") ?? 0, darks: number("ParametricDarks") ?? 0,
                    lights: number("ParametricLights") ?? 0, highlights: number("ParametricHighlights") ?? 0,
                    shadowSplit: number("ParametricShadowSplit") ?? 25, midtoneSplit: number("ParametricMidtoneSplit") ?? 50,
                    highlightSplit: number("ParametricHighlightSplit") ?? 75
                ).composed(with: adjustments.toneCurve.rgb)
            }
        }

        /// `[x0, y0, x1, y1, …]` (templates) or `["x0, y0", …]` (XMP), 0 … 255.
        static func curvePoints(_ value: CameraRawValue) -> [CurvePoint]? {
            guard let items = value.list else { return nil }
            var numbers: [Double] = []
            for item in items {
                if let text = item.string, text.contains(",") {
                    numbers += text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                } else if let number = item.number {
                    numbers.append(number)
                }
            }
            guard numbers.count >= 4, numbers.count.isMultiple(of: 2) else { return nil }
            return stride(from: 0, to: numbers.count, by: 2).map {
                CurvePoint(x: numbers[$0] / 255, y: numbers[$0 + 1] / 255)
            }
        }

        mutating func colorMixer() {
            let bands = ColorMixer.Band.allCases
            if isGrayscale {
                groups.insert(.colorMixer)
                for band in bands {
                    adjustments.colorMixer[band] = .init(luminance: clamped("GrayMixer\(formatName(band))") ?? 0)
                }
                return
            }
            let keys = bands.flatMap { band in
                ["Hue", "Saturation", "Luminance"].map { "\($0)Adjustment\(formatName(band))" }
            }
            guard has(keys) else { return }
            groups.insert(.colorMixer)
            for band in bands {
                let name = formatName(band)
                adjustments.colorMixer[band] = .init(hue: clamped("HueAdjustment\(name)") ?? 0,
                                                     saturation: clamped("SaturationAdjustment\(name)") ?? 0,
                                                     luminance: clamped("LuminanceAdjustment\(name)") ?? 0)
            }
        }

        mutating func colorGrade() {
            let keys = values.keys.filter { $0.hasPrefix("SplitToning") || $0.hasPrefix("ColorGrade") }
            guard !keys.isEmpty else { return }
            groups.insert(.colorGrade)
            var grade = ColorGrade()
            grade.shadows = GradeWheel(hue: number("SplitToningShadowHue") ?? 0,
                                       amount: clamped("SplitToningShadowSaturation", 0...100) ?? 0,
                                       luminance: clamped("ColorGradeShadowLum") ?? 0)
            grade.midtones = GradeWheel(hue: number("ColorGradeMidtoneHue") ?? 0,
                                        amount: clamped("ColorGradeMidtoneSat", 0...100) ?? 0,
                                        luminance: clamped("ColorGradeMidtoneLum") ?? 0)
            grade.highlights = GradeWheel(hue: number("SplitToningHighlightHue") ?? 0,
                                          amount: clamped("SplitToningHighlightSaturation", 0...100) ?? 0,
                                          luminance: clamped("ColorGradeHighlightLum") ?? 0)
            grade.balance = clamped("SplitToningBalance") ?? 0
            grade.blending = clamped("ColorGradeBlending", 0...100) ?? 50
            adjustments.colorGrade = grade
            if changes(["ColorGradeGlobalSat", "ColorGradeGlobalLum"]) { unsupported.insert(.globalColorGrade) }
        }

        mutating func details() {
            if has(["Sharpness", "SharpenRadius", "SharpenDetail", "SharpenEdgeMasking"]) {
                groups.insert(.sharpening)
                adjustments.sharpen = Sharpen(amount: clamped("Sharpness", Sharpen.amountRange) ?? 0,
                                              radius: clamped("SharpenRadius", Sharpen.radiusRange) ?? 1,
                                              detail: clamped("SharpenDetail", 0...100) ?? 25,
                                              masking: clamped("SharpenEdgeMasking", 0...100) ?? 0)
            }
            if has(["LuminanceSmoothing", "ColorNoiseReduction"]) {
                groups.insert(.noiseReduction)
                adjustments.noiseReduction = NoiseReduction(luminance: clamped("LuminanceSmoothing", 0...100),
                                                            color: clamped("ColorNoiseReduction", 0...100))
            }
        }

        mutating func effects() {
            if has(["PostCropVignetteAmount"]) {
                groups.insert(.vignette)
                let amount = clamped("PostCropVignetteAmount") ?? 0
                adjustments.vignette = Vignette(amount: amount, size: clamped("PostCropVignetteMidpoint", 0...100) ?? 50,
                                                roundness: clamped("PostCropVignetteRoundness") ?? 0)
                if amount != 0, changes(["PostCropVignetteFeather"], from: 50) || changes(["PostCropVignetteStyle"], from: 1)
                    || changes(["PostCropVignetteHighlightContrast"]) {
                    unsupported.insert(.vignetteStyle)
                }
            }
            if has(["GrainAmount"]) {
                groups.insert(.grain)
                // Size 25 there is about the finest grain on a 35 mm frame here (1).
                let size = number("GrainSize") ?? 25
                adjustments.grain = Grain(strength: clamped("GrainAmount", 0...100) ?? 0,
                                          roughness: clamped("GrainFrequency", 0...100) ?? 50,
                                          size: min(max(size <= 25 ? 0.5 + size / 50 : 1 + (size - 25) / 37.5,
                                                        Grain.sizeRange.lowerBound), Grain.sizeRange.upperBound))
            }
        }

        /// Settings with no equivalent, reported when they change anything.
        mutating func notes() {
            if values["AutoTone"]?.bool == true || values["AutoExposure"]?.bool == true {
                unsupported.insert(.autoSettings)
            }
            if changes(["Texture"]) { unsupported.insert(.texture) }
            if changes(["ShadowTint", "RedHue", "RedSaturation", "GreenHue", "GreenSaturation", "BlueHue", "BlueSaturation"]) {
                unsupported.insert(.calibration)
            }
            if isGrayscale { unsupported.insert(.blackAndWhite) }
            if let colors = values["PointColors"]?.list, !colors.isEmpty { unsupported.insert(.pointColor) }
            let corrections = ["GradientBasedCorrections", "CircularGradientBasedCorrections", "PaintBasedCorrections",
                               "MaskGroupBasedCorrections"]
            if corrections.contains(where: { values[$0].map(Self.hasActiveCorrection) ?? false }) {
                unsupported.insert(.localAdjustments)
            }
            if ["RetouchInfo", "RetouchAreas"].contains(where: { !(values[$0]?.list?.isEmpty ?? true) }) {
                unsupported.insert(.retouching)
            }
            if values["HasCrop"]?.bool == true || changes(["CropAngle"]) { unsupported.insert(.crop) }
            if values["LensProfileEnable"]?.bool == true || values["AutoLateralCA"]?.bool == true
                || changes(["LensManualDistortionAmount", "VignetteAmount"]) {
                unsupported.insert(.lensCorrections)
            }
            if changes(["PerspectiveVertical", "PerspectiveHorizontal", "PerspectiveRotate", "PerspectiveAspect",
                        "PerspectiveX", "PerspectiveY", "PerspectiveUpright"])
                || changes(["PerspectiveScale"], from: 100) {
                unsupported.insert(.transform)
            }
            if changes(["DefringePurpleAmount", "DefringeGreenAmount"]) { unsupported.insert(.defringe) }
            if let version = values["ProcessVersion"]?.number, version < 6.7 { unsupported.insert(.legacyProcess) }
        }

        /// True when a list of local corrections has one that is on and changes something.
        static func hasActiveCorrection(_ value: CameraRawValue) -> Bool {
            (value.list ?? []).contains { item in
                guard let correction = item.record, correction["CorrectionActive"]?.bool != false,
                      correction["CorrectionAmount"]?.number != 0 else { return false }
                return correction.contains { key, value in
                    key.hasPrefix("Local") && !key.contains("Curve") && !key.contains("Refine")
                        && (value.number.map { abs($0) > 1e-6 } ?? false)
                }
            }
        }
    }
}

/// A curve set by four tonal regions, sampled into points. The regions'
/// boundaries are the three splits (0 … 100); each region value (−100 … +100)
/// raises or lowers its range of tones, by up to about a quarter at ±100.
struct ParametricCurve {
    var shadows: Double
    var darks: Double
    var lights: Double
    var highlights: Double
    var shadowSplit: Double
    var midtoneSplit: Double
    var highlightSplit: Double

    static let sampleCount = 17
    static let maximumShift = 0.25

    func value(at x: Double) -> Double {
        let splits = [0, shadowSplit / 100, midtoneSplit / 100, highlightSplit / 100, 1]
        let amounts = [shadows, darks, lights, highlights]
        var y = x
        for region in 0..<4 {
            let center = (splits[region] + splits[region + 1]) / 2
            let width = max(splits[region + 1] - splits[region], 0.05)
            // A bell over the region, held to zero at black and white.
            let distance = (x - center) / width
            let bell = exp(-2 * distance * distance)
            y += amounts[region] / 100 * Self.maximumShift * bell * min(1, 8 * x * (1 - x))
        }
        return min(max(y, 0), 1)
    }

    /// Points of this curve followed by `points` (a point curve), never decreasing.
    func composed(with points: [CurvePoint]) -> [CurvePoint] {
        var result: [CurvePoint] = []
        var highest = 0.0
        for index in 0..<Self.sampleCount {
            let x = Double(index) / Double(Self.sampleCount - 1)
            highest = max(highest, Self.interpolate(points, at: value(at: x)))
            result.append(CurvePoint(x: x, y: highest))
        }
        return result
    }

    /// Straight lines between `points` (sorted by x).
    static func interpolate(_ points: [CurvePoint], at x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return x }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            return b.x - a.x < 1e-9 ? b.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        return last.y
    }
}
