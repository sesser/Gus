import Foundation

/// The tools of a preset pack (`.lnpc`) that the mapping knows: the one
/// identifier table the import may hold (PRD #203 R11). Each raw value is the
/// identifier exactly as a pack gives it (a tool's `tool_name`, an effect's
/// `id`, a setting's name, or a key of the template's structure); a case is
/// here only because `LuminarMapping` maps, approximates or leaves it out by
/// name. Display names are the app's (`PresetText.title(_:)`, String Catalog),
/// never stored here. Anything else a pack holds is reported by its identifier
/// as `LuminarToolReference.unknown`.
public enum LuminarTool: String, CaseIterable, Sendable {
    // Mapped (approximated where a setting has no exact equivalent).
    case develop = "DefaultEffects"
    case rawDevelop = "DefaultEffectsRAW"
    case lookUpTable = "LUTMappingEffect"
    case color = "ExtendedColorAdjustmentLayer"
    case colorToning = "ColorToningAdjustmentLayer"
    case grain = "GrainNewAdjustmentLayer"
    case vignette = "VignetteAdjustmentLayer"
    case sharpening = "MIPLSharpenEffect"
    case dehaze = "MIPLDehazeEffect"

    // Approximated.
    case supercontrast = "ProContrastAdjustmentLayer"
    case matte = "FadeEffect"
    case colorBalance = "MIPLColorBalanceEffect"
    case warmth = "Warmth"
    case vividness = "Vividness"
    case warmAndCoolColors = "MIPLSplitWarmthEffect"
    case structure = "AIStructureEffect"
    case detailsEnhancer = "MIPLDetailsEffect"
    case dramatic = "ComplexBleachAdjustmentLayer"
    case blackAndWhite = "BWChannels_v1_Effect"
    /// Layer opacity, blend modes and several layers, merged into one set of values.
    case layers = "layers_array"

    // Left out: the tools PRD R6 names.
    case accentAI = "MIPLDynamicContrastEffect"
    case skyEnhancer = "MIPLSkyEnhancerEffect"
    case atmosphere = "AIFogEffect"
    case glow = "GlowOrtonAdjustmentLayer"
    case highKey = "HighKeyAdjustmentLayer"
    case goldenHour = "MIPLWarmSkylight_v1_Effect"
    case foliage = "MIPLFoliageEnhanceEffect"
    case colorContrast = "MIPLContrastColorRangeEffect"
    case removeColorCast = "MIPLRemoveColorCastEffect"
    case hueShift = "MIPLHueShiftEffect"
    /// A masked tool (the template's `mask` key).
    case masks = "mask"

    // Left out: settings the mapping reads by name and has no control for.
    case smartTone = "Smart Tone"
    case texture = "Texture"
    case noiseReduction = "MIPLDenoiseLaplacianEffect"
    case aiNoiseReduction = "DenoiseAIRaw"
    case lensCorrection = "MIPLLensCorrectionEffect"
}

/// A tool as a report names it: one the table knows, or the identifier the
/// pack gave, kept exactly (it may be empty).
public enum LuminarToolReference: Hashable, Sendable {
    case known(LuminarTool)
    case unknown(String)

    /// The table's tool for `identifier`, or the identifier itself.
    public init(identifier: String) {
        self = LuminarTool(rawValue: identifier).map(Self.known) ?? .unknown(identifier)
    }
}

/// The app's controls an approximated tool went into, for "(as …)".
public enum PresetControl: String, CaseIterable, Sendable {
    case toneCurve, contrast, clarity, saturation, vibrance, colorMixer, colorGrading
}

/// What became of one tool of a converted preset.
public struct LuminarToolReport: Hashable, Sendable {
    public enum Status: Int, Hashable, Sendable, Comparable {
        case mapped, approximated, leftOut

        public static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    public var tool: LuminarToolReference
    public var status: Status
    /// For an approximated tool, the controls it went into (may be empty).
    public var controls: [PresetControl]

    public init(tool: LuminarToolReference, status: Status, controls: [PresetControl] = []) {
        self.tool = tool
        self.status = status
        self.controls = controls
    }
}
