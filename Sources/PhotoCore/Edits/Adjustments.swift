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
    /// carry it; Copy Adjustments does when it is checked (`CopyItem.crop`).
    public var crop = Crop()
    /// What builds with a Profile group stored about the decode. Not one of
    /// the `Group`s: presets, copy and paste never carry it (issue #219, R6);
    /// Reset All Adjustments removes it.
    public var decode = RawDecode()
    /// Which camera profile the color step of a LibRaw decode uses. Not one
    /// of the `Group`s, and no build writes it yet (`CameraProfileReference`).
    public var cameraProfile = CameraProfileReference()
    /// Lines a lens bends straightened, first among the adjustments, before
    /// the crop (issue #87). Its frame is the mask and spot frame.
    public var distortion = LensDistortion()
    /// Corners a lens darkens lifted, on the decoded image before the
    /// distortion step, so before Exposure and the tone sliders (issue #87).
    public var lensVignetting = LensVignetting()
    /// Lateral color: red and blue lined up with green, before the crop.
    public var colorAlignment = ColorAlignment()
    /// Picked fringe colors turned gray near high-contrast edges, before the crop.
    public var colorFringes = ColorFringes()
    /// Heal and clone spots, after the Lens heading's steps and before the
    /// crop (`SpotRenderer`). Their group, `.spots`, turns them off and on;
    /// presets leave them out (`Group.presetGroups`); Copy Adjustments carries
    /// them only when checked, onto photos of the same frame size (#243, R8).
    public var spots = Spots()
    public var whiteBalance = WhiteBalance()
    public var exposure = Exposure()
    public var tone = Tone()
    public var presence = Presence()
    public var toneCurve = ToneCurve()
    public var colorMixer = ColorMixer()
    /// The conversion to gray by film filters, after the Color Mixer and
    /// before Vibrance, Saturation and Color Grading (issue #218).
    public var blackAndWhite = BlackAndWhite()
    public var colorGrade = ColorGrade()
    /// Masks and their local values. Not one of the `Group`s: presets and
    /// paste leave them out.
    public var local = LocalAdjustments()
    public var lookTable = LookTable()
    public var vignette = Vignette()
    public var noiseReduction = NoiseReduction()
    public var sharpen = Sharpen()
    public var grain = Grain()
    /// A gain-map photo's HDR choice (issue #282). Not one of the `Group`s:
    /// presets, copy and paste never carry it (R3); Reset All Adjustments
    /// turns it off. Renders no SDR pixel (`HDRChoice`). Read and set the
    /// choice through `hdrIsOn`, which agrees with `EditStack.hdrChoice`.
    public var hdr = HDRChoice()

    /// The HDR choice as it applies: on, and its operation not turned off.
    /// Nothing here turns the operation off, but a stack can hold a turned-off
    /// one (a hand edit, a later build); it then reads as off everywhere, as
    /// `EditStack.hdrChoice` (the catalog's copy) reads it. Setting it turns
    /// the operation back on.
    public var hdrIsOn: Bool {
        get { hdr.isOn && !disabled.contains(HDRChoice.kind) }
        set {
            hdr.isOn = newValue
            disabled.remove(HDRChoice.kind)
        }
    }
    /// Modules that keep their values but are turned off. Change it through
    /// `setEnabled(_:_:)`, which only records modules away from their defaults.
    public private(set) var disabled: Set<EditOperationKind> = []
    /// Operations of unknown kinds or newer kind versions, and repeated kinds.
    public var preserved: [EditOperation] = []

    public init() {}

    /// Everything at its default: renders the master unchanged.
    public static let none = Adjustments()

    public init(stack: EditStack) {
        self.init(stack: stack, keepsLegacyDecoder: false)
    }

    /// The values of a preset's stored stack. Unlike a photo's, a preset
    /// saved before machine learning noise reduction had its own setting
    /// keeps the machine learning decoder its Profile group chose
    /// (`RawDecode.legacyMachineLearningVersion`), so it still turns it on
    /// when applied and is saved back as it was (ml-denoise PRD R3).
    public init(presetStack stack: EditStack) {
        self.init(stack: stack, keepsLegacyDecoder: true)
    }

    private init(stack: EditStack, keepsLegacyDecoder: Bool) {
        var seen = Set<EditOperationKind>()
        var decoderIsEnabled = true
        for operation in stack.operations {
            guard operation.kindVersion == 1, !seen.contains(operation.kind), read(operation) else {
                preserved.append(operation)
                continue
            }
            seen.insert(operation.kind)
            if operation.kind == RawDecode.kind { decoderIsEnabled = operation.isEnabled }
            if !operation.isEnabled, !parameters(of: operation.kind).isEmpty {
                disabled.insert(operation.kind)
            }
        }
        if !keepsLegacyDecoder, decode.legacyMachineLearningVersion != nil {
            // A stack saved before the setting existed, with the machine
            // learning decoder chosen in Profile: machine learning on, Profile
            // at the default (PRD R3). When Profile was turned off the decoder
            // did not apply, so nothing is turned on.
            decode.legacyMachineLearningVersion = nil
            if decoderIsEnabled { noiseReduction.machineLearning = true }
            if parameters(of: RawDecode.kind).isEmpty { disabled.remove(RawDecode.kind) }
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
        if !cameraProfile.parameters.isEmpty {
            operations.append(EditOperation(kind: CameraProfileReference.kind,
                                            isEnabled: !disabled.contains(CameraProfileReference.kind),
                                            parameters: cameraProfile.parameters))
        }
        add(distortion)
        add(lensVignetting)
        add(colorAlignment)
        add(colorFringes)
        let spotParameters = spots.parameters
        if !spotParameters.isEmpty {
            operations.append(EditOperation(kind: Spots.kind, isEnabled: !disabled.contains(Spots.kind),
                                            parameters: spotParameters))
        }
        add(whiteBalance)
        add(exposure)
        add(tone)
        add(presence)
        add(toneCurve)
        add(colorMixer)
        add(blackAndWhite)
        add(colorGrade)
        let masks = local.parameters
        if !masks.isEmpty {
            operations.append(EditOperation(kind: LocalAdjustments.kind,
                                            isEnabled: !disabled.contains(LocalAdjustments.kind), parameters: masks))
        }
        add(lookTable)
        add(vignette)
        add(noiseReduction)
        add(sharpen)
        add(grain)
        add(hdr)
        return EditStack(operations: operations + preserved)
    }

    public var isDefault: Bool { self == .none }

    /// Reads a known, enabled operation into its module. False for unknown kinds.
    private mutating func read(_ operation: EditOperation) -> Bool {
        let values = ParameterValues(operation.parameters)
        switch operation.kind {
        case Crop.kind: crop = Crop(values)
        case RawDecode.kind: decode = RawDecode(values)
        case CameraProfileReference.kind: cameraProfile = CameraProfileReference(parameters: operation.parameters)
        case LensDistortion.kind: distortion = LensDistortion(values)
        case LensVignetting.kind: lensVignetting = LensVignetting(values)
        case ColorAlignment.kind: colorAlignment = ColorAlignment(values)
        case ColorFringes.kind: colorFringes = ColorFringes(values)
        case Spots.kind:
            // Read strictly, as masks: a stack built in memory that does not read is kept as it is.
            guard let read = try? Spots(operation.parameters) else { return false }
            spots = read
        case WhiteBalance.kind: whiteBalance = WhiteBalance(values)
        case Exposure.kind: exposure = Exposure(values)
        case Tone.kind: tone = Tone(values)
        case Presence.kind: presence = Presence(values)
        case ToneCurve.kind: toneCurve = ToneCurve(values)
        case ColorMixer.kind: colorMixer = ColorMixer(values)
        case BlackAndWhite.kind: blackAndWhite = BlackAndWhite(values)
        case ColorGrade.kind: colorGrade = ColorGrade(values)
        case LocalAdjustments.kind:
            // Stored stacks were checked by `EditStack.decode`; one built in
            // memory that does not read is kept as it is.
            guard let read = try? LocalAdjustments(operation.parameters) else { return false }
            local = read
        case LookTable.kind: lookTable = LookTable(values)
        case Vignette.kind: vignette = Vignette(values)
        case NoiseReduction.kind: noiseReduction = NoiseReduction(values)
        case Sharpen.kind: sharpen = Sharpen(values)
        case Grain.kind: grain = Grain(values)
        case HDRChoice.kind: hdr = HDRChoice(values)
        default: return false
        }
        return true
    }

    /// The parameters a module writes (empty at its defaults, or for unknown kinds).
    public func parameters(of kind: EditOperationKind) -> [String: EditParameter] {
        switch kind {
        case Crop.kind: crop.parameters
        case RawDecode.kind: decode.parameters
        case CameraProfileReference.kind: cameraProfile.parameters
        case LensDistortion.kind: distortion.parameters
        case LensVignetting.kind: lensVignetting.parameters
        case ColorAlignment.kind: colorAlignment.parameters
        case ColorFringes.kind: colorFringes.parameters
        case Spots.kind: spots.parameters
        case WhiteBalance.kind: whiteBalance.parameters
        case Exposure.kind: exposure.parameters
        case Tone.kind: tone.parameters
        case Presence.kind: presence.parameters
        case ToneCurve.kind: toneCurve.parameters
        case ColorMixer.kind: colorMixer.parameters
        case BlackAndWhite.kind: blackAndWhite.parameters
        case ColorGrade.kind: colorGrade.parameters
        case LocalAdjustments.kind: local.parameters
        case LookTable.kind: lookTable.parameters
        case Vignette.kind: vignette.parameters
        case NoiseReduction.kind: noiseReduction.parameters
        case Sharpen.kind: sharpen.parameters
        case Grain.kind: grain.parameters
        case HDRChoice.kind: hdr.parameters
        default: [:]
        }
    }

    /// Puts one module back at its defaults (and on).
    private mutating func resetModule(_ kind: EditOperationKind) {
        switch kind {
        case Crop.kind: crop = Crop()
        case RawDecode.kind: decode = RawDecode()
        case CameraProfileReference.kind: cameraProfile = CameraProfileReference()
        case LensDistortion.kind: distortion = LensDistortion()
        case LensVignetting.kind: lensVignetting = LensVignetting()
        case ColorAlignment.kind: colorAlignment = ColorAlignment()
        case ColorFringes.kind: colorFringes = ColorFringes()
        case Spots.kind: spots = Spots()
        case WhiteBalance.kind: whiteBalance = WhiteBalance()
        case Exposure.kind: exposure = Exposure()
        case Tone.kind: tone = Tone()
        case Presence.kind: presence = Presence()
        case ToneCurve.kind: toneCurve = ToneCurve()
        case ColorMixer.kind: colorMixer = ColorMixer()
        case BlackAndWhite.kind: blackAndWhite = BlackAndWhite()
        case ColorGrade.kind: colorGrade = ColorGrade()
        case LocalAdjustments.kind: local = LocalAdjustments()
        case LookTable.kind: lookTable = LookTable()
        case Vignette.kind: vignette = Vignette()
        case NoiseReduction.kind: noiseReduction = NoiseReduction()
        case Sharpen.kind: sharpen = Sharpen()
        case Grain.kind: grain = Grain()
        case HDRChoice.kind: hdr = HDRChoice()
        default: break
        }
        disabled.remove(kind)
    }

    /// Takes one module's values, and whether it is on, from `source`.
    mutating func copyModule(_ kind: EditOperationKind, from source: Adjustments) {
        switch kind {
        case Crop.kind: crop = source.crop
        case RawDecode.kind: decode = source.decode
        case CameraProfileReference.kind: cameraProfile = source.cameraProfile
        case LensDistortion.kind: distortion = source.distortion
        case LensVignetting.kind: lensVignetting = source.lensVignetting
        case ColorAlignment.kind: colorAlignment = source.colorAlignment
        case ColorFringes.kind: colorFringes = source.colorFringes
        case Spots.kind: spots = source.spots
        case WhiteBalance.kind: whiteBalance = source.whiteBalance
        case Exposure.kind: exposure = source.exposure
        case Tone.kind: tone = source.tone
        case Presence.kind: presence = source.presence
        case ToneCurve.kind: toneCurve = source.toneCurve
        case ColorMixer.kind: colorMixer = source.colorMixer
        case BlackAndWhite.kind: blackAndWhite = source.blackAndWhite
        case ColorGrade.kind: colorGrade = source.colorGrade
        case LocalAdjustments.kind: local = source.local
        case LookTable.kind: lookTable = source.lookTable
        case Vignette.kind: vignette = source.vignette
        case NoiseReduction.kind: noiseReduction = source.noiseReduction
        case Sharpen.kind: sharpen = source.sharpen
        case Grain.kind: grain = source.grain
        case HDRChoice.kind: hdr = source.hdr
        default: return
        }
        if source.disabled.contains(kind) {
            disabled.insert(kind)
        } else {
            disabled.remove(kind)
        }
    }

    /// These adjustments with the modules of `groups` taken from `source`
    /// (values and on/off); everything else, unknown operations and the
    /// stored decode included, stays.
    ///
    /// A source read from a preset saved before machine learning noise
    /// reduction had its own setting, whose Profile group chose the machine
    /// learning decoder, turns it on and changes nothing else in Noise
    /// Reduction (ml-denoise PRD R3). Such a preset's stored decode is there
    /// only because it carried Profile (`AdjustmentPreset`), so the rule
    /// holds without that group (issue #219, R4).
    public func replacing(_ groups: Set<Group>, from source: Adjustments) -> Adjustments {
        var copy = copying(groups, from: source)
        if source.decode.legacyMachineLearningVersion != nil {
            copy.noiseReduction.machineLearning = true
        }
        return copy
    }

    /// As `replacing`, without the legacy machine learning rule. Spots are
    /// never copied between photos, whatever `groups` holds (PRD R11).
    func copying(_ groups: Set<Group>, from source: Adjustments) -> Adjustments {
        var copy = self
        for kind in groups.subtracting([.spots]).flatMap(\.kinds) { copy.copyModule(kind, from: source) }
        return copy
    }

    /// These adjustments with `source`'s stored decode, on or off as there:
    /// what a paste keeps of its target and a stored preset of its own
    /// values (issue #219, R3, R6).
    func keepingDecode(of source: Adjustments) -> Adjustments {
        var copy = self
        copy.copyModule(RawDecode.kind, from: source)
        return copy
    }

    /// The groups presets can carry with values away from their defaults.
    public var modifiedGroups: Set<Group> {
        Set(Group.presetGroups.filter(isModified))
    }

    /// What renders: these adjustments with the modules that are off at their
    /// defaults. Local Sharpness belongs to the Sharpening group: while the
    /// group is off, every mask's Sharpness is 0 here too, so nothing at all is
    /// sharpened; the stored amounts are kept and apply again when the group
    /// is turned back on (owner ruling 2026-11-15, issue #71).
    public var effective: Adjustments {
        guard !disabled.isEmpty else { return self }
        var copy = self
        for kind in disabled { copy.resetModule(kind) }
        if disabled.contains(Sharpen.kind) {
            for index in copy.local.masks.indices { copy.local.masks[index].adjustments.sharpen = 0 }
        }
        return copy
    }

    /// The Adjust tab's headings, used to reset a group of modules.
    public enum Section: String, CaseIterable, Sendable {
        case develop, tone, details, lens, colorMixer, blackAndWhite, colorGrading, effects, spots

        public var groups: [Group] {
            switch self {
            case .develop: [.whiteBalance, .light, .presence]
            case .tone: [.toneCurve]
            case .details: [.sharpening, .noiseReduction]
            case .lens: [.distortion, .lensVignetting, .colorFringes, .colorAlignment]
            case .colorMixer: [.colorMixer]
            case .blackAndWhite: [.blackAndWhite]
            case .colorGrading: [.colorGrade]
            case .effects: [.lookTable, .vignette, .grain]
            case .spots: [.spots]
            }
        }
    }

    /// The controls under a heading that are turned on and off together.
    public enum Group: String, CaseIterable, Sendable {
        case whiteBalance, light, presence, toneCurve, sharpening, noiseReduction, colorMixer
        /// The conversion to gray (issue #218): a preset group like the Color
        /// Mixer's, whose check box also turns it on (`setEnabled`).
        case blackAndWhite
        case colorGrade
        case lookTable, vignette, grain
        /// The Lens heading's geometry and light groups (issue #87): like
        /// Black & White, their check boxes also switch them on (`setEnabled`).
        case distortion, lensVignetting
        case colorFringes, colorAlignment
        /// Heal and clone spots: a group so its heading has an on/off check
        /// box (healing PRD R18). Not a preset group: presets leave it out
        /// (R11). Copy Adjustments carries it only when checked (#243, R8).
        case spots

        /// The groups presets carry: every group but `.spots`.
        public static let presetGroups: [Group] = allCases.filter { $0 != .spots }

        public var kinds: [EditOperationKind] {
            switch self {
            case .whiteBalance: [WhiteBalance.kind]
            case .light: [Exposure.kind, Tone.kind]
            case .presence: [Presence.kind]
            case .toneCurve: [ToneCurve.kind]
            case .sharpening: [Sharpen.kind]
            case .noiseReduction: [NoiseReduction.kind]
            case .colorMixer: [ColorMixer.kind]
            case .blackAndWhite: [BlackAndWhite.kind]
            case .colorGrade: [ColorGrade.kind]
            case .lookTable: [LookTable.kind]
            case .vignette: [Vignette.kind]
            case .grain: [Grain.kind]
            case .distortion: [LensDistortion.kind]
            case .lensVignetting: [LensVignetting.kind]
            case .colorFringes: [ColorFringes.kind]
            case .colorAlignment: [ColorAlignment.kind]
            case .spots: [Spots.kind]
            }
        }
    }

    /// True when a group has values away from its defaults (on or off).
    public func isModified(_ group: Group) -> Bool {
        group.kinds.contains { !parameters(of: $0).isEmpty }
    }

    /// A Black & White slider's value. Only the value: changing it while the
    /// group does not apply switches it on through `enableModules`, and a
    /// value that does not change changes nothing (code review C1).
    public mutating func setBlackAndWhite(_ filter: BlackAndWhite.Filter, _ value: Double) {
        blackAndWhite[filter] = value
    }

    /// The Black & White conversion renders: switched on and not turned off.
    public var blackAndWhiteApplies: Bool {
        blackAndWhite.isOn && isEnabled(.blackAndWhite)
    }

    /// False when a group's edits are turned off.
    public func isEnabled(_ group: Group) -> Bool {
        !group.kinds.contains(where: disabled.contains)
    }

    /// Turns a group's edits off (kept, not rendered) or back on. Turning
    /// Black & White on also switches its conversion on, so a photo that
    /// never had it goes gray with every filter at 0 (PRD R1); Distortion and
    /// Lens Vignetting likewise (issue #87, RI-4).
    public mutating func setEnabled(_ group: Group, _ isEnabled: Bool) {
        if group == .blackAndWhite, isEnabled { blackAndWhite.isOn = true }
        if group == .distortion, isEnabled { distortion.isOn = true }
        if group == .lensVignetting, isEnabled { lensVignetting.isOn = true }
        for kind in group.kinds {
            if isEnabled || parameters(of: kind).isEmpty {
                disabled.remove(kind)
            } else {
                disabled.insert(kind)
            }
        }
    }

    /// Turns back on every module whose values differ from `previous`: editing
    /// a control that is off turns it on. Changing a Black & White filter
    /// switches its conversion on too, unless the same change set its on
    /// state itself (design B10).
    public mutating func enableModules(changedFrom previous: Adjustments) {
        if !blackAndWhite.isOn, !previous.blackAndWhite.isOn, blackAndWhite.filtersDiffer(from: previous.blackAndWhite) {
            blackAndWhite.isOn = true
        }
        // A lens group's Source, Amount or Constrain changed switches it on (design §3.1, B10's rule).
        if !distortion.isOn, !previous.distortion.isOn, distortion.valuesDiffer(from: previous.distortion) {
            distortion.isOn = true
        }
        if !lensVignetting.isOn, !previous.lensVignetting.isOn, lensVignetting.valuesDiffer(from: previous.lensVignetting) {
            lensVignetting.isOn = true
        }
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

    /// Reset All Adjustments: every module back to its default, the stored
    /// decode removed with them (issue #219, R3); only operations this build
    /// does not understand stay.
    public func resettingAll() -> Adjustments {
        Adjustments(stack: EditStack(operations: preserved))
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
            && values.local.renderedMasks.allSatisfy { $0.adjustments.modules.preservesExtendedRange }
    }
}

// MARK: Modules

/// One group of controls stored as one operation.
public protocol AdjustmentModule: Hashable, Sendable {
    static var kind: EditOperationKind { get }
    /// Every parameter the module reads and writes (`AdjustmentParameters.swift`).
    static var parameterDescriptions: [AdjustmentParameter] { get }
    /// Parameters that differ from the defaults; empty means "leave out".
    var parameters: [String: EditParameter] { get }
}

/// What builds with a Profile group stored about the RAW decode (issue #219).
/// No control sets it any more: the operation is kept as stored, written back
/// unchanged by every write but Reset All Adjustments, and only its decoder
/// version still renders.
public struct RawDecode: AdjustmentModule {
    public static let kind: EditOperationKind = "rawDecode"

    /// The Look a Profile group stored (`neutral`, `flat`), as stored. Never
    /// rendered: every photo renders with the decoder's default (R2). Kept so
    /// the stack is written back as it was (R3); not a parameter scripts see.
    public var storedLook: String?
    /// One of the decoder's `supportedDecoderVersions` other than the machine
    /// learning one, or nil for its default (pinned below the machine
    /// learning version, `MachineLearningNoiseReduction.pinnedVersion`).
    /// Used while machine learning noise reduction is off or cannot apply.
    /// Only a stack an older build saved, or `photocli`, sets one (R4).
    public var decoderVersion: String?
    /// The machine learning decoder version a preset saved before
    /// `NoiseReduction.machineLearning` existed chose here; nil otherwise.
    /// Kept only in presets' values (`Adjustments(presetStack:)`), where it
    /// is saved back as `decoderVersion`; a photo's values read it as
    /// machine learning on.
    public var legacyMachineLearningVersion: String?

    public init(storedLook: String? = nil, decoderVersion: String? = nil) {
        self.storedLook = storedLook
        self.decoderVersion = decoderVersion
    }

    /// The parameter a stored Look is kept under.
    static let storedLookParameter = "look"

    init(_ values: ParameterValues) {
        storedLook = values.string(Self.storedLookParameter)
        let version = values.string("decoderVersion")
        if let version, MachineLearningNoiseReduction.isMachineLearningVersion(version) {
            legacyMachineLearningVersion = version
        } else {
            decoderVersion = version
        }
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set(Self.storedLookParameter, storedLook)
        out.set("decoderVersion", legacyMachineLearningVersion ?? decoderVersion)
        return out.values
    }
}

/// The camera profile a version asks for, by reference (issue #170, R8): the
/// room an edit stack has for it, kept for #89 (Adobe `.dcp` profiles).
///
/// **No build writes this operation yet, and none resolves it**: a stack
/// that holds one renders with the built-in profile
/// (`PreviewGenerator.decodeWithLibRaw`). Its parameters are kept exactly as
/// stored and written back as they were, also the ones this build has no
/// name for, so a stack a later build wrote loses nothing here. A build
/// from before this type existed keeps the operation too, as one of a kind
/// it does not know (`Adjustments.preserved`).
///
/// Persisted as kind `cameraProfile`; the one parameter named so far is
/// `identifier`, a string.
public struct CameraProfileReference: Hashable, Sendable {
    public static let kind: EditOperationKind = "cameraProfile"

    /// The operation's parameters as stored; empty for no reference.
    public var parameters: [String: EditParameter]

    public init(parameters: [String: EditParameter] = [:]) {
        self.parameters = parameters
    }

    /// The profile asked for; nil for the built-in one.
    public var identifier: String? {
        if case .string(let identifier)? = parameters["identifier"] { return identifier }
        return nil
    }
}

/// Neutral point. RAW files take an absolute Kelvin and tint, which their
/// decode applies (the system decoder, or the color step after LibRaw's);
/// other files take relative shifts, applied after decoding.
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
    /// Kelvin of the scene's light (RAW, by either decoder). Nil keeps the camera's as-shot value.
    public var temperature: Double?
    /// Green (−) to magenta (+) of the picture, for light that lies that far
    /// to the other side of the black body's color (RAW; `ColorTemperature`).
    /// Nil keeps as shot.
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

    /// The mode to show for a file that is not decoded as a raw, among
    /// `Preset.relativePresets` (raf-not-rendering design review D5):
    ///
    /// 1. the stored mode, when it is one of those three and the balance
    ///    holds no Kelvin values: a mode picked from the pop-up sticks,
    ///    Custom with both sliders at 0 included;
    /// 2. otherwise (a named light source, or any mode carrying Kelvin
    ///    values, as a paste or preset from a raw the system decodes leaves)
    ///    the mode that renders: As Shot when both relative values are 0,
    ///    else Custom. Only the relative values reach such a file.
    ///
    /// Display only: the stored preset and values are never rewritten.
    public var relativeDisplayPreset: Preset {
        if Preset.relativePresets.contains(preset), temperature == nil, tint == nil { return preset }
        return relativeTemperature == 0 && relativeTint == 0 ? .asShot : .custom
    }

    /// The mode to show for a raw, whichever decoder reads it
    /// (white-balance-across-decoders design §5). Only the Kelvin values
    /// reach a raw; the relative ones never render on it:
    ///
    /// 1. the stored mode, when the balance holds Kelvin values or the mode
    ///    is a named light source: every mode this build writes on a raw;
    /// 2. Custom, when it is stored without Kelvin values and both relative
    ///    values are 0: the person chose it from the pop-up and it sticks
    ///    (it renders as shot, as choosing Custom on a raw always has);
    /// 3. otherwise As Shot, which is what renders: As Shot itself, an Auto
    ///    without Kelvin values (measured on a rendered image, or by a
    ///    build that gave LibRaw's photos relative values), a Custom that
    ///    carries relative values.
    ///
    /// Display only: the stored preset and values are never rewritten.
    public var kelvinDisplayPreset: Preset {
        if temperature != nil || tint != nil || preset.neutral != nil { return preset }
        if preset == .custom, relativeTemperature == 0, relativeTint == 0 { return .custom }
        return .asShot
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
    /// RAW only. Not used while machine learning applies (the decoder ignores it).
    public var color: Double?
    /// RAW only: decode with the RAW decoder's machine learning model
    /// (`MachineLearningNoiseReduction`), `luminance` being its amount. Off
    /// unless chosen; kept where it cannot apply.
    public var machineLearning = false

    public init(luminance: Double? = nil, color: Double? = nil, machineLearning: Bool = false) {
        self.luminance = luminance
        self.color = color
        self.machineLearning = machineLearning
    }

    init(_ values: ParameterValues) {
        luminance = values.optionalNumber("luminance")
        color = values.optionalNumber("color")
        machineLearning = values.bool("machineLearning", default: false)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("luminance", luminance)
        out.set("color", color)
        out.set("machineLearning", machineLearning, default: false)
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

    func bool(_ key: String, default value: Bool) -> Bool {
        if case .bool(let stored)? = raw[key] { return stored }
        return value
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

    mutating func set(_ key: String, _ value: Bool, default defaultValue: Bool) {
        if value != defaultValue { values[key] = .bool(value) }
    }
}
