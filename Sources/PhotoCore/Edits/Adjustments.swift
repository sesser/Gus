import Foundation

/// The global adjustments of one version, as typed values over its `EditStack`.
///
/// Each module maps to one operation with a generic, persisted kind. Modules at
/// their defaults are left out of the stack, and so are parameters at their
/// defaults, so resetting everything gives back `EditStack.identity` (and the
/// original's cached previews). Operations this build does not understand, or
/// that are disabled, are kept as they are and written back after the modules.
public struct Adjustments: Hashable, Sendable {
    public var decode = RawDecode()
    public var whiteBalance = WhiteBalance()
    public var exposure = Exposure()
    public var tone = Tone()
    public var presence = Presence()
    public var toneCurve = ToneCurve()
    public var colorGrade = ColorGrade()
    public var lookTable = LookTable()
    public var noiseReduction = NoiseReduction()
    public var sharpen = Sharpen()
    /// Operations of unknown kinds or newer kind versions, and disabled ones.
    public var preserved: [EditOperation] = []

    public init() {}

    /// Everything at its default: renders the master unchanged.
    public static let none = Adjustments()

    public init(stack: EditStack) {
        var seen = Set<EditOperationKind>()
        for operation in stack.operations {
            guard operation.isEnabled, operation.kindVersion == 1, !seen.contains(operation.kind),
                  read(operation)
            else {
                preserved.append(operation)
                continue
            }
            seen.insert(operation.kind)
        }
    }

    /// The stack for these values, modules in render order, defaults omitted.
    public var editStack: EditStack {
        var operations: [EditOperation] = []
        func add<Module: AdjustmentModule>(_ module: Module) {
            let parameters = module.parameters
            if !parameters.isEmpty {
                operations.append(EditOperation(kind: Module.kind, parameters: parameters))
            }
        }
        add(decode)
        add(whiteBalance)
        add(exposure)
        add(tone)
        add(presence)
        add(toneCurve)
        add(colorGrade)
        add(lookTable)
        add(noiseReduction)
        add(sharpen)
        return EditStack(operations: operations + preserved)
    }

    public var isDefault: Bool { self == .none }

    /// Reads a known, enabled operation into its module. False for unknown kinds.
    private mutating func read(_ operation: EditOperation) -> Bool {
        let values = ParameterValues(operation.parameters)
        switch operation.kind {
        case RawDecode.kind: decode = RawDecode(values)
        case WhiteBalance.kind: whiteBalance = WhiteBalance(values)
        case Exposure.kind: exposure = Exposure(values)
        case Tone.kind: tone = Tone(values)
        case Presence.kind: presence = Presence(values)
        case ToneCurve.kind: toneCurve = ToneCurve(values)
        case ColorGrade.kind: colorGrade = ColorGrade(values)
        case LookTable.kind: lookTable = LookTable(values)
        case NoiseReduction.kind: noiseReduction = NoiseReduction(values)
        case Sharpen.kind: sharpen = Sharpen(values)
        default: return false
        }
        return true
    }

    /// The sidebar's headings, used to reset or copy a group of modules.
    public enum Section: String, CaseIterable, Sendable {
        case develop, tone, details, colorGrading
    }

    /// Returns these adjustments with one heading's modules back at their defaults.
    public func resetting(_ section: Section) -> Adjustments {
        var copy = self
        switch section {
        case .develop:
            copy.decode = RawDecode()
            copy.whiteBalance = WhiteBalance()
            copy.exposure = Exposure()
            copy.tone = Tone()
            copy.presence = Presence()
        case .tone:
            copy.toneCurve = ToneCurve()
        case .details:
            copy.noiseReduction = NoiseReduction()
            copy.sharpen = Sharpen()
        case .colorGrading:
            copy.colorGrade = ColorGrade()
            copy.lookTable = LookTable()
        }
        return copy
    }

    /// True when a heading has anything away from its defaults.
    public func isModified(_ section: Section) -> Bool {
        resetting(section) != self
    }

    /// Operations that work on values above SDR white. Curve tables, the
    /// grading cube and LUTs clamp at white, so an HDR rendition is not offered
    /// while any of them is active.
    public var preservesExtendedRange: Bool {
        tone.contrast == 0 && tone.whites == 0 && tone.blacks == 0 && tone.highlights <= 0
            && toneCurve.isIdentity && colorGrade == ColorGrade() && lookTable.identifier == nil
            && presence.dehaze == 0
    }
}

// MARK: Modules

/// One group of controls stored as one operation.
public protocol AdjustmentModule: Hashable, Sendable {
    static var kind: EditOperationKind { get }
    /// Parameters that differ from the defaults; empty means "leave out".
    var parameters: [String: EditParameter] { get }
}

/// How the RAW decoder renders the file before any other step.
public struct RawDecode: AdjustmentModule {
    public static let kind: EditOperationKind = "rawDecode"

    /// Base renderings built from the decoder's own tone controls.
    public enum Look: String, CaseIterable, Sendable {
        /// The decoder's default tone and color.
        case standard
        /// Half of the decoder's base contrast boost: softer, more room to grade.
        case neutral
        /// No base boost: a linear response, for heavy grading.
        case flat

        /// The decoder's `boostAmount`, or nil to leave its default.
        var boostAmount: Float? {
            switch self {
            case .standard: nil
            case .neutral: 0.5
            case .flat: 0
            }
        }
    }

    public var look = Look.standard
    /// One of the decoder's `supportedDecoderVersions`, or nil for its default.
    public var decoderVersion: String?

    public init(look: Look = .standard, decoderVersion: String? = nil) {
        self.look = look
        self.decoderVersion = decoderVersion
    }

    init(_ values: ParameterValues) {
        look = values.string("look").flatMap(Look.init(rawValue:)) ?? .standard
        decoderVersion = values.string("decoderVersion")
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("look", look.rawValue, default: Look.standard.rawValue)
        out.set("decoderVersion", decoderVersion)
        return out.values
    }
}

/// Neutral point. RAW files take an absolute Kelvin and tint, which the decoder
/// applies; other files take relative shifts, applied after decoding.
public struct WhiteBalance: AdjustmentModule {
    public static let kind: EditOperationKind = "whiteBalance"

    public enum Preset: String, CaseIterable, Sendable {
        case asShot, auto, daylight, cloudy, shade, tungsten, fluorescent, flash, custom

        /// Kelvin and tint for the named light sources (RAW only).
        public var neutral: (temperature: Double, tint: Double)? {
            switch self {
            case .daylight: (5500, 0)
            case .cloudy: (6500, 5)
            case .shade: (7500, 5)
            case .tungsten: (2850, 0)
            case .fluorescent: (3800, 20)
            case .flash: (5500, 0)
            case .asShot, .auto, .custom: nil
            }
        }

        /// The presets offered for files that are not RAW.
        public static let relativePresets: [Preset] = [.asShot, .auto, .custom]
    }

    public static let temperatureRange: ClosedRange<Double> = 2000...50000
    public static let tintRange: ClosedRange<Double> = -150...150

    public var preset = Preset.asShot
    /// Kelvin of the scene's light (RAW). Nil keeps the camera's as-shot value.
    public var temperature: Double?
    /// Green (−) to magenta (+) of the scene's light (RAW). Nil keeps as shot.
    public var tint: Double?
    /// −100 (cooler) … +100 (warmer), for files that are not RAW.
    public var relativeTemperature: Double = 0
    /// −100 (greener) … +100 (more magenta), for files that are not RAW.
    public var relativeTint: Double = 0

    public init(preset: Preset = .asShot, temperature: Double? = nil, tint: Double? = nil,
                relativeTemperature: Double = 0, relativeTint: Double = 0) {
        self.preset = preset
        self.temperature = temperature
        self.tint = tint
        self.relativeTemperature = relativeTemperature
        self.relativeTint = relativeTint
    }

    init(_ values: ParameterValues) {
        preset = values.string("preset").flatMap(Preset.init(rawValue:)) ?? .asShot
        temperature = values.optionalNumber("temperature")
        tint = values.optionalNumber("tint")
        relativeTemperature = values.number("relativeTemperature", default: 0)
        relativeTint = values.number("relativeTint", default: 0)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("preset", preset.rawValue, default: Preset.asShot.rawValue)
        out.set("temperature", temperature)
        out.set("tint", tint)
        out.set("relativeTemperature", relativeTemperature, default: 0)
        out.set("relativeTint", relativeTint, default: 0)
        return out.values
    }

    /// Picks a named preset for a RAW file.
    public static func raw(_ preset: Preset) -> WhiteBalance {
        guard let neutral = preset.neutral else { return WhiteBalance(preset: preset) }
        return WhiteBalance(preset: preset, temperature: neutral.temperature, tint: neutral.tint)
    }
}

public struct Exposure: AdjustmentModule {
    public static let kind: EditOperationKind = "exposure"
    public static let range: ClosedRange<Double> = -5...5

    /// Stops, applied in linear light.
    public var ev: Double = 0

    public init(ev: Double = 0) { self.ev = ev }

    init(_ values: ParameterValues) {
        ev = values.number("ev", default: 0)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("ev", ev, default: 0)
        return out.values
    }
}

/// Tonal range controls, each −100 … +100.
public struct Tone: AdjustmentModule {
    public static let kind: EditOperationKind = "tone"

    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var whites: Double = 0
    public var blacks: Double = 0

    public init(contrast: Double = 0, highlights: Double = 0, shadows: Double = 0, whites: Double = 0, blacks: Double = 0) {
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
    }

    init(_ values: ParameterValues) {
        contrast = values.number("contrast", default: 0)
        highlights = values.number("highlights", default: 0)
        shadows = values.number("shadows", default: 0)
        whites = values.number("whites", default: 0)
        blacks = values.number("blacks", default: 0)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("contrast", contrast, default: 0)
        out.set("highlights", highlights, default: 0)
        out.set("shadows", shadows, default: 0)
        out.set("whites", whites, default: 0)
        out.set("blacks", blacks, default: 0)
        return out.values
    }
}

/// Local contrast, haze and color intensity, each −100 … +100.
public struct Presence: AdjustmentModule {
    public static let kind: EditOperationKind = "presence"

    public var clarity: Double = 0
    public var dehaze: Double = 0
    public var vibrance: Double = 0
    public var saturation: Double = 0

    public init(clarity: Double = 0, dehaze: Double = 0, vibrance: Double = 0, saturation: Double = 0) {
        self.clarity = clarity
        self.dehaze = dehaze
        self.vibrance = vibrance
        self.saturation = saturation
    }

    init(_ values: ParameterValues) {
        clarity = values.number("clarity", default: 0)
        dehaze = values.number("dehaze", default: 0)
        vibrance = values.number("vibrance", default: 0)
        saturation = values.number("saturation", default: 0)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("clarity", clarity, default: 0)
        out.set("dehaze", dehaze, default: 0)
        out.set("vibrance", vibrance, default: 0)
        out.set("saturation", saturation, default: 0)
        return out.values
    }
}

/// A point of a tone curve; both coordinates 0 … 1 in a perceptual encoding.
public struct CurvePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Point curves on the composite and on each channel.
public struct ToneCurve: AdjustmentModule {
    public static let kind: EditOperationKind = "toneCurve"

    public enum Channel: String, CaseIterable, Sendable {
        case rgb, red, green, blue
    }

    public static let identityPoints = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    public var rgb = ToneCurve.identityPoints
    public var red = ToneCurve.identityPoints
    public var green = ToneCurve.identityPoints
    public var blue = ToneCurve.identityPoints

    public init() {}

    init(_ values: ParameterValues) {
        for channel in Channel.allCases {
            if let points = values.points(channel.rawValue) {
                self[channel] = points
            }
        }
    }

    public subscript(channel: Channel) -> [CurvePoint] {
        get {
            switch channel {
            case .rgb: rgb
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            let points = Self.normalized(newValue)
            switch channel {
            case .rgb: rgb = points
            case .red: red = points
            case .green: green = points
            case .blue: blue = points
            }
        }
    }

    public var isIdentity: Bool {
        Channel.allCases.allSatisfy { Self.isIdentity(self[$0]) }
    }

    /// Sorted by x, clamped to the unit square, at least two points.
    static func normalized(_ points: [CurvePoint]) -> [CurvePoint] {
        let clamped = points.map { CurvePoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
            .sorted { $0.x < $1.x }
        return clamped.count >= 2 ? clamped : identityPoints
    }

    static func isIdentity(_ points: [CurvePoint]) -> Bool {
        points.allSatisfy { abs($0.x - $0.y) < 1e-9 }
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        for channel in Channel.allCases where !Self.isIdentity(self[channel]) {
            out.values[channel.rawValue] = .list(self[channel].flatMap { [.number($0.x), .number($0.y)] })
        }
        return out.values
    }
}

/// Color added to one tonal range.
public struct GradeWheel: Hashable, Sendable {
    /// Degrees, 0 … 360 (0 red, 120 green, 240 blue).
    public var hue: Double = 0
    /// 0 … 100.
    public var amount: Double = 0
    /// −100 … +100.
    public var luminance: Double = 0

    public init(hue: Double = 0, amount: Double = 0, luminance: Double = 0) {
        self.hue = hue
        self.amount = amount
        self.luminance = luminance
    }
}

/// Split toning over shadows, midtones and highlights.
public struct ColorGrade: AdjustmentModule {
    public static let kind: EditOperationKind = "colorGrade"

    public enum Range: String, CaseIterable, Sendable {
        case shadows, midtones, highlights
    }

    public var shadows = GradeWheel()
    public var midtones = GradeWheel()
    public var highlights = GradeWheel()
    /// −100 (favor shadows) … +100 (favor highlights).
    public var balance: Double = 0
    /// 0 (hard split) … 100 (wide overlap).
    public var blending: Double = 50

    public init() {}

    init(_ values: ParameterValues) {
        for range in Range.allCases {
            self[range] = GradeWheel(hue: values.number("\(range.rawValue)Hue", default: 0),
                                     amount: values.number("\(range.rawValue)Amount", default: 0),
                                     luminance: values.number("\(range.rawValue)Luminance", default: 0))
        }
        balance = values.number("balance", default: 0)
        blending = values.number("blending", default: 50)
    }

    public subscript(range: Range) -> GradeWheel {
        get {
            switch range {
            case .shadows: shadows
            case .midtones: midtones
            case .highlights: highlights
            }
        }
        set {
            switch range {
            case .shadows: shadows = newValue
            case .midtones: midtones = newValue
            case .highlights: highlights = newValue
            }
        }
    }

    /// True when rendering cannot change the image (balance and blending alone do nothing).
    public var isIdentity: Bool {
        Range.allCases.allSatisfy { self[$0].amount == 0 && self[$0].luminance == 0 }
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        for range in Range.allCases {
            out.set("\(range.rawValue)Hue", self[range].hue, default: 0)
            out.set("\(range.rawValue)Amount", self[range].amount, default: 0)
            out.set("\(range.rawValue)Luminance", self[range].luminance, default: 0)
        }
        out.set("balance", balance, default: 0)
        out.set("blending", blending, default: 50)
        return out.values
    }
}

/// A `.cube` look-up table copied into the library.
public struct LookTable: AdjustmentModule {
    public static let kind: EditOperationKind = "lookTable"

    /// SHA-256 of the file, which names its copy in the library.
    public var identifier: String?
    /// File name without extension, for display.
    public var name: String = ""
    /// 0 … 100.
    public var intensity: Double = 100

    public init(identifier: String? = nil, name: String = "", intensity: Double = 100) {
        self.identifier = identifier
        self.name = name
        self.intensity = intensity
    }

    init(_ values: ParameterValues) {
        identifier = values.string("identifier")
        name = values.string("name") ?? ""
        intensity = values.number("intensity", default: 100)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("identifier", identifier)
        out.set("name", name, default: "")
        out.set("intensity", intensity, default: 100)
        return out.values
    }
}

/// Noise reduction, 0 … 100. RAW files use the decoder's own reduction (nil
/// keeps its default for the camera); other files a Core Image filter.
public struct NoiseReduction: AdjustmentModule {
    public static let kind: EditOperationKind = "noiseReduction"

    public var luminance: Double?
    /// RAW only.
    public var color: Double?

    public init(luminance: Double? = nil, color: Double? = nil) {
        self.luminance = luminance
        self.color = color
    }

    init(_ values: ParameterValues) {
        luminance = values.optionalNumber("luminance")
        color = values.optionalNumber("color")
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("luminance", luminance)
        out.set("color", color)
        return out.values
    }
}

/// Capture sharpening as an unsharp mask with halo and edge control.
public struct Sharpen: AdjustmentModule {
    public static let kind: EditOperationKind = "sharpen"

    public static let amountRange: ClosedRange<Double> = 0...150
    public static let radiusRange: ClosedRange<Double> = 0.5...3

    /// 0 … 150.
    public var amount: Double = 0
    /// Pixels at full resolution, 0.5 … 3.
    public var radius: Double = 1
    /// 0 (sharpen edges only, no halos) … 100 (all fine detail).
    public var detail: Double = 25
    /// 0 (everywhere) … 100 (only on strong edges).
    public var masking: Double = 0

    public init(amount: Double = 0, radius: Double = 1, detail: Double = 25, masking: Double = 0) {
        self.amount = amount
        self.radius = radius
        self.detail = detail
        self.masking = masking
    }

    init(_ values: ParameterValues) {
        amount = values.number("amount", default: 0)
        radius = values.number("radius", default: 1)
        detail = values.number("detail", default: 25)
        masking = values.number("masking", default: 0)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("amount", amount, default: 0)
        out.set("radius", radius, default: 1)
        out.set("detail", detail, default: 25)
        out.set("masking", masking, default: 0)
        return out.values
    }
}

// MARK: Parameter helpers

/// Typed reads from an operation's parameters, tolerating missing or mistyped values.
struct ParameterValues {
    let raw: [String: EditParameter]

    init(_ raw: [String: EditParameter]) { self.raw = raw }

    func optionalNumber(_ key: String) -> Double? {
        if case .number(let value)? = raw[key], value.isFinite { return value }
        return nil
    }

    func number(_ key: String, default value: Double) -> Double {
        optionalNumber(key) ?? value
    }

    func string(_ key: String) -> String? {
        if case .string(let value)? = raw[key] { return value }
        return nil
    }

    /// A flat `[x0, y0, x1, y1, …]` list.
    func points(_ key: String) -> [CurvePoint]? {
        guard case .list(let list)? = raw[key] else { return nil }
        let numbers = list.compactMap { item -> Double? in
            if case .number(let value) = item, value.isFinite { return value }
            return nil
        }
        guard numbers.count == list.count, numbers.count >= 4, numbers.count.isMultiple(of: 2) else { return nil }
        return ToneCurve.normalized(stride(from: 0, to: numbers.count, by: 2).map {
            CurvePoint(x: numbers[$0], y: numbers[$0 + 1])
        })
    }
}

/// Collects parameters, leaving out values at their defaults.
struct ParameterBuilder {
    var values: [String: EditParameter] = [:]

    mutating func set(_ key: String, _ value: Double, default defaultValue: Double) {
        if value != defaultValue { values[key] = .number(value) }
    }

    mutating func set(_ key: String, _ value: Double?) {
        if let value { values[key] = .number(value) }
    }

    mutating func set(_ key: String, _ value: String, default defaultValue: String) {
        if value != defaultValue { values[key] = .string(value) }
    }

    mutating func set(_ key: String, _ value: String?) {
        if let value { values[key] = .string(value) }
    }
}
