import CoreGraphics
import Foundation

/// The global adjustments of one version, as typed values over its `EditStack`.
///
/// Each module maps to one operation with a generic, persisted kind. Modules at
/// their defaults are left out of the stack, and so are parameters at their
/// defaults, so resetting everything gives back `EditStack.identity` (and the
/// original's cached previews). A module can be turned off without losing its
/// values: its operation is kept with `isEnabled` false, and `effective` (what
/// renders) leaves it out. Operations this build does not understand are kept
/// as they are and written back after the modules.
public struct Adjustments: Hashable, Sendable {
    /// Turns, straightening and crop. Not one of the `Group`s: presets never
    /// carry it, copy and paste does.
    public var crop = Crop()
    public var decode = RawDecode()
    public var whiteBalance = WhiteBalance()
    public var exposure = Exposure()
    public var tone = Tone()
    public var presence = Presence()
    public var toneCurve = ToneCurve()
    public var colorMixer = ColorMixer()
    public var colorGrade = ColorGrade()
    public var lookTable = LookTable()
    public var vignette = Vignette()
    public var noiseReduction = NoiseReduction()
    public var sharpen = Sharpen()
    public var grain = Grain()
    /// Modules that keep their values but are turned off. Change it through
    /// `setEnabled(_:_:)`, which only records modules away from their defaults.
    public private(set) var disabled: Set<EditOperationKind> = []
    /// Operations of unknown kinds or newer kind versions, and repeated kinds.
    public var preserved: [EditOperation] = []

    public init() {}

    /// Everything at its default: renders the master unchanged.
    public static let none = Adjustments()

    public init(stack: EditStack) {
        var seen = Set<EditOperationKind>()
        for operation in stack.operations {
            guard operation.kindVersion == 1, !seen.contains(operation.kind), read(operation) else {
                preserved.append(operation)
                continue
            }
            seen.insert(operation.kind)
            if !operation.isEnabled, !parameters(of: operation.kind).isEmpty {
                disabled.insert(operation.kind)
            }
        }
    }

    /// The stack for these values, modules in render order, defaults omitted.
    public var editStack: EditStack {
        var operations: [EditOperation] = []
        func add<Module: AdjustmentModule>(_ module: Module) {
            let parameters = module.parameters
            if !parameters.isEmpty {
                operations.append(EditOperation(kind: Module.kind, isEnabled: !disabled.contains(Module.kind),
                                                parameters: parameters))
            }
        }
        add(crop)
        add(decode)
        add(whiteBalance)
        add(exposure)
        add(tone)
        add(presence)
        add(toneCurve)
        add(colorMixer)
        add(colorGrade)
        add(lookTable)
        add(vignette)
        add(noiseReduction)
        add(sharpen)
        add(grain)
        return EditStack(operations: operations + preserved)
    }

    public var isDefault: Bool { self == .none }

    /// Reads a known, enabled operation into its module. False for unknown kinds.
    private mutating func read(_ operation: EditOperation) -> Bool {
        let values = ParameterValues(operation.parameters)
        switch operation.kind {
        case Crop.kind: crop = Crop(values)
        case RawDecode.kind: decode = RawDecode(values)
        case WhiteBalance.kind: whiteBalance = WhiteBalance(values)
        case Exposure.kind: exposure = Exposure(values)
        case Tone.kind: tone = Tone(values)
        case Presence.kind: presence = Presence(values)
        case ToneCurve.kind: toneCurve = ToneCurve(values)
        case ColorMixer.kind: colorMixer = ColorMixer(values)
        case ColorGrade.kind: colorGrade = ColorGrade(values)
        case LookTable.kind: lookTable = LookTable(values)
        case Vignette.kind: vignette = Vignette(values)
        case NoiseReduction.kind: noiseReduction = NoiseReduction(values)
        case Sharpen.kind: sharpen = Sharpen(values)
        case Grain.kind: grain = Grain(values)
        default: return false
        }
        return true
    }

    /// The parameters a module writes (empty at its defaults, or for unknown kinds).
    public func parameters(of kind: EditOperationKind) -> [String: EditParameter] {
        switch kind {
        case Crop.kind: crop.parameters
        case RawDecode.kind: decode.parameters
        case WhiteBalance.kind: whiteBalance.parameters
        case Exposure.kind: exposure.parameters
        case Tone.kind: tone.parameters
        case Presence.kind: presence.parameters
        case ToneCurve.kind: toneCurve.parameters
        case ColorMixer.kind: colorMixer.parameters
        case ColorGrade.kind: colorGrade.parameters
        case LookTable.kind: lookTable.parameters
        case Vignette.kind: vignette.parameters
        case NoiseReduction.kind: noiseReduction.parameters
        case Sharpen.kind: sharpen.parameters
        case Grain.kind: grain.parameters
        default: [:]
        }
    }

    /// Puts one module back at its defaults (and on).
    private mutating func resetModule(_ kind: EditOperationKind) {
        switch kind {
        case Crop.kind: crop = Crop()
        case RawDecode.kind: decode = RawDecode()
        case WhiteBalance.kind: whiteBalance = WhiteBalance()
        case Exposure.kind: exposure = Exposure()
        case Tone.kind: tone = Tone()
        case Presence.kind: presence = Presence()
        case ToneCurve.kind: toneCurve = ToneCurve()
        case ColorMixer.kind: colorMixer = ColorMixer()
        case ColorGrade.kind: colorGrade = ColorGrade()
        case LookTable.kind: lookTable = LookTable()
        case Vignette.kind: vignette = Vignette()
        case NoiseReduction.kind: noiseReduction = NoiseReduction()
        case Sharpen.kind: sharpen = Sharpen()
        case Grain.kind: grain = Grain()
        default: break
        }
        disabled.remove(kind)
    }

    /// Takes one module's values, and whether it is on, from `source`.
    private mutating func copyModule(_ kind: EditOperationKind, from source: Adjustments) {
        switch kind {
        case Crop.kind: crop = source.crop
        case RawDecode.kind: decode = source.decode
        case WhiteBalance.kind: whiteBalance = source.whiteBalance
        case Exposure.kind: exposure = source.exposure
        case Tone.kind: tone = source.tone
        case Presence.kind: presence = source.presence
        case ToneCurve.kind: toneCurve = source.toneCurve
        case ColorMixer.kind: colorMixer = source.colorMixer
        case ColorGrade.kind: colorGrade = source.colorGrade
        case LookTable.kind: lookTable = source.lookTable
        case Vignette.kind: vignette = source.vignette
        case NoiseReduction.kind: noiseReduction = source.noiseReduction
        case Sharpen.kind: sharpen = source.sharpen
        case Grain.kind: grain = source.grain
        default: return
        }
        if source.disabled.contains(kind) {
            disabled.insert(kind)
        } else {
            disabled.remove(kind)
        }
    }

    /// These adjustments with the modules of `groups` taken from `source`
    /// (values and on/off); everything else, unknown operations included, stays.
    public func replacing(_ groups: Set<Group>, from source: Adjustments) -> Adjustments {
        var copy = self
        for kind in groups.flatMap(\.kinds) { copy.copyModule(kind, from: source) }
        return copy
    }

    /// The groups with values away from their defaults.
    public var modifiedGroups: Set<Group> {
        Set(Group.allCases.filter(isModified))
    }

    /// What renders: these adjustments with the modules that are off at their defaults.
    public var effective: Adjustments {
        guard !disabled.isEmpty else { return self }
        var copy = self
        for kind in disabled { copy.resetModule(kind) }
        return copy
    }

    /// The Adjust tab's headings, used to reset a group of modules.
    public enum Section: String, CaseIterable, Sendable {
        case develop, tone, details, colorMixer, colorGrading, effects

        public var groups: [Group] {
            switch self {
            case .develop: [.profile, .whiteBalance, .light, .presence]
            case .tone: [.toneCurve]
            case .details: [.sharpening, .noiseReduction]
            case .colorMixer: [.colorMixer]
            case .colorGrading: [.colorGrade]
            case .effects: [.lookTable, .vignette, .grain]
            }
        }
    }

    /// The controls under a heading that are turned on and off together.
    public enum Group: String, CaseIterable, Sendable {
        case profile, whiteBalance, light, presence, toneCurve, sharpening, noiseReduction, colorMixer, colorGrade
        case lookTable, vignette, grain

        public var kinds: [EditOperationKind] {
            switch self {
            case .profile: [RawDecode.kind]
            case .whiteBalance: [WhiteBalance.kind]
            case .light: [Exposure.kind, Tone.kind]
            case .presence: [Presence.kind]
            case .toneCurve: [ToneCurve.kind]
            case .sharpening: [Sharpen.kind]
            case .noiseReduction: [NoiseReduction.kind]
            case .colorMixer: [ColorMixer.kind]
            case .colorGrade: [ColorGrade.kind]
            case .lookTable: [LookTable.kind]
            case .vignette: [Vignette.kind]
            case .grain: [Grain.kind]
            }
        }
    }

    /// True when a group has values away from its defaults (on or off).
    public func isModified(_ group: Group) -> Bool {
        group.kinds.contains { !parameters(of: $0).isEmpty }
    }

    /// False when a group's edits are turned off.
    public func isEnabled(_ group: Group) -> Bool {
        !group.kinds.contains(where: disabled.contains)
    }

    /// Turns a group's edits off (kept, not rendered) or back on.
    public mutating func setEnabled(_ group: Group, _ isEnabled: Bool) {
        for kind in group.kinds {
            if isEnabled || parameters(of: kind).isEmpty {
                disabled.remove(kind)
            } else {
                disabled.insert(kind)
            }
        }
    }

    /// Turns back on every module whose values differ from `previous`: editing
    /// a control that is off turns it on.
    public mutating func enableModules(changedFrom previous: Adjustments) {
        for kind in disabled where parameters(of: kind) != previous.parameters(of: kind) {
            disabled.remove(kind)
        }
        for kind in disabled where parameters(of: kind).isEmpty {
            disabled.remove(kind)
        }
    }

    /// Returns these adjustments with one heading's modules back at their defaults.
    public func resetting(_ section: Section) -> Adjustments {
        var copy = self
        for kind in section.groups.flatMap(\.kinds) { copy.resetModule(kind) }
        return copy
    }

    /// True when a heading has anything away from its defaults.
    public func isModified(_ section: Section) -> Bool {
        resetting(section) != self
    }

    /// Operations that work on values above SDR white. Curve tables, the
    /// mixer and grading cubes, LUTs and grain clamp at white, so an HDR
    /// rendition is not offered while any of them is active.
    public var preservesExtendedRange: Bool {
        let values = effective
        return values.tone.contrast == 0 && values.tone.whites == 0 && values.tone.blacks == 0
            && values.tone.highlights <= 0 && values.toneCurve.isIdentity && values.colorMixer.isIdentity
            && values.colorGrade == ColorGrade()
            && values.lookTable.identifier == nil && values.presence.dehaze == 0 && values.grain.isIdentity
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

/// Hue, saturation and luminance of eight ranges of hues, each −100 … +100.
/// Near-grey colors are left alone.
public struct ColorMixer: AdjustmentModule {
    public static let kind: EditOperationKind = "colorMixer"

    public enum Band: String, CaseIterable, Sendable {
        case red, orange, yellow, green, aqua, blue, purple, magenta

        /// The hue the band is centered on, in degrees as in `GradeWheel`.
        public var centerHue: Double {
            switch self {
            case .red: 0
            case .orange: 30
            case .yellow: 60
            case .green: 120
            case .aqua: 180
            case .blue: 240
            case .purple: 270
            case .magenta: 300
            }
        }
    }

    /// The changes made to one band.
    public struct Shift: Hashable, Sendable {
        /// Negative toward the previous band's hue, positive toward the next.
        public var hue: Double = 0
        public var saturation: Double = 0
        public var luminance: Double = 0

        public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
            self.hue = hue
            self.saturation = saturation
            self.luminance = luminance
        }

        public var isZero: Bool { hue == 0 && saturation == 0 && luminance == 0 }
    }

    /// Bands that change anything; the others are left out.
    private var shifts: [Band: Shift] = [:]

    public init() {}

    init(_ values: ParameterValues) {
        for band in Band.allCases {
            self[band] = Shift(hue: values.number("\(band.rawValue)Hue", default: 0),
                               saturation: values.number("\(band.rawValue)Saturation", default: 0),
                               luminance: values.number("\(band.rawValue)Luminance", default: 0))
        }
    }

    public subscript(band: Band) -> Shift {
        get { shifts[band] ?? Shift() }
        set { shifts[band] = newValue.isZero ? nil : newValue }
    }

    public var isIdentity: Bool { shifts.isEmpty }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        for (band, shift) in shifts {
            out.set("\(band.rawValue)Hue", shift.hue, default: 0)
            out.set("\(band.rawValue)Saturation", shift.saturation, default: 0)
            out.set("\(band.rawValue)Luminance", shift.luminance, default: 0)
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

    /// The encoding a table expects its input in, and writes its output in.
    /// Creative tables are usually made for sRGB; some for wider spaces.
    public enum ColorSpace: String, CaseIterable, Sendable {
        case sRGB, displayP3, adobeRGB, proPhoto

        public var cgColorSpace: CGColorSpace {
            switch self {
            case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
            case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
            case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)!
            // ROMM RGB is ProPhoto RGB.
            case .proPhoto: CGColorSpace(name: CGColorSpace.rommrgb)!
            }
        }
    }

    /// SHA-256 of the file, which names its copy in the library.
    public var identifier: String?
    /// The table's name when it was applied, for display.
    public var name: String = ""
    /// 0 … 100.
    public var intensity: Double = 100
    public var colorSpace = ColorSpace.sRGB

    public init(identifier: String? = nil, name: String = "", intensity: Double = 100,
                colorSpace: ColorSpace = .sRGB) {
        self.identifier = identifier
        self.name = name
        self.intensity = intensity
        self.colorSpace = colorSpace
    }

    init(_ values: ParameterValues) {
        identifier = values.string("identifier")
        name = values.string("name") ?? ""
        intensity = values.number("intensity", default: 100)
        colorSpace = values.string("colorSpace").flatMap(ColorSpace.init(rawValue:)) ?? .sRGB
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("identifier", identifier)
        out.set("name", name, default: "")
        out.set("intensity", intensity, default: 100)
        out.set("colorSpace", colorSpace.rawValue, default: ColorSpace.sRGB.rawValue)
        return out.values
    }
}

/// Darkens (or lightens) toward the frame's edges, as an exposure falloff.
public struct Vignette: AdjustmentModule {
    public static let kind: EditOperationKind = "vignette"

    /// −100 (dark edges) … +100 (light edges).
    public var amount: Double = 0
    /// 0 (reaches the center) … 100 (only the corners).
    public var size: Double = 50
    /// −100 (follows the frame's rectangle) … 0 (an ellipse of the frame's
    /// proportions) … +100 (a circle).
    public var roundness: Double = 0

    public init(amount: Double = 0, size: Double = 50, roundness: Double = 0) {
        self.amount = amount
        self.size = size
        self.roundness = roundness
    }

    init(_ values: ParameterValues) {
        amount = values.number("amount", default: 0)
        size = values.number("size", default: 50)
        roundness = values.number("roundness", default: 0)
    }

    public var isIdentity: Bool { amount == 0 }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("amount", amount, default: 0)
        out.set("size", size, default: 50)
        out.set("roundness", roundness, default: 0)
        return out.values
    }
}

/// Film-like grain, added last. Its size follows the frame, so every rendition
/// of a photo shows the same grain relative to the picture.
public struct Grain: AdjustmentModule {
    public static let kind: EditOperationKind = "grain"

    public static let strengthRange: ClosedRange<Double> = 0...200
    public static let sizeRange: ClosedRange<Double> = 0.5...3

    /// 0 … 200: scales the three tonal amounts. Zero renders nothing.
    public var strength: Double = 0
    /// 0 … 100, how much grain the dark, middle and light tones get.
    public var shadows: Double = 30
    public var midtones: Double = 40
    public var highlights: Double = 15
    /// 0 (soft, even) … 100 (sharp, clumped).
    public var roughness: Double = 50
    /// 0 (monochrome) … 100 (independent per channel).
    public var color: Double = 0
    /// 0.5 … 3, relative to fine grain on a 35 mm frame.
    public var size: Double = 1

    public init(strength: Double = 0, shadows: Double = 30, midtones: Double = 40, highlights: Double = 15,
                roughness: Double = 50, color: Double = 0, size: Double = 1) {
        self.strength = strength
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
        self.roughness = roughness
        self.color = color
        self.size = size
    }

    init(_ values: ParameterValues) {
        strength = values.number("strength", default: 0)
        shadows = values.number("shadows", default: 30)
        midtones = values.number("midtones", default: 40)
        highlights = values.number("highlights", default: 15)
        roughness = values.number("roughness", default: 50)
        color = values.number("color", default: 0)
        size = values.number("size", default: 1)
    }

    public var isIdentity: Bool {
        strength == 0 || (shadows == 0 && midtones == 0 && highlights == 0)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("strength", strength, default: 0)
        out.set("shadows", shadows, default: 30)
        out.set("midtones", midtones, default: 40)
        out.set("highlights", highlights, default: 15)
        out.set("roughness", roughness, default: 50)
        out.set("color", color, default: 0)
        out.set("size", size, default: 1)
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
