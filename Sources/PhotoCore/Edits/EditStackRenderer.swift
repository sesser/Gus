import CoreImage

/// What a renderer needs to know about the image it is given.
public struct RenderContext: Sendable, Hashable {
    /// Decoded pixels per master pixel (1 at full resolution), so radii given at
    /// full resolution can be scaled to the decode.
    public var scale: Double
    /// The image came from the RAW decoder, which already applied the stack's
    /// decode settings.
    public var isRaw: Bool
    /// The camera's crop of the whole sensor (`CameraFrame`), when the decoder
    /// gave the whole sensor for a stack that asked for it and the file has
    /// one: a stack with masks but no crop of its own crops to it, so the
    /// photo keeps its frame.
    public var cameraFrame: CropRect?

    public init(scale: Double = 1, isRaw: Bool = false, cameraFrame: CropRect? = nil) {
        self.scale = scale
        self.isRaw = isRaw
        self.cameraFrame = cameraFrame
    }
}

/// Settings the RAW decoder applies while demosaicing. Nil leaves the
/// decoder's default for the file, so an empty value decodes exactly as before.
public struct RAWDecodeSettings: Sendable, Hashable {
    public var temperature: Float?
    public var tint: Float?
    public var boostAmount: Float?
    /// The Profile group's decoder choice: used while machine learning is
    /// not asked for or cannot apply. Never a machine learning version
    /// (`Adjustments` reads one as `machineLearning`).
    public var decoderVersion: String?
    /// Decode with the machine learning version where the file offers it
    /// (`MachineLearningNoiseReduction`); `luminanceNoiseReduction` is then its amount.
    public var machineLearning = false
    public var luminanceNoiseReduction: Float?
    public var colorNoiseReduction: Float?
    /// `extendedDynamicRangeAmount`: values above white are kept instead of rolled off.
    public var extendedDynamicRange: Float?
    /// Decode the whole sensor, without the crop the camera recorded
    /// (`CameraFrame`); the edit stack crops instead, or the renderer crops to
    /// the camera's frame (`RenderContext.cameraFrame`).
    public var fullFrame = false

    public init(temperature: Float? = nil, tint: Float? = nil, boostAmount: Float? = nil, decoderVersion: String? = nil,
                machineLearning: Bool = false, luminanceNoiseReduction: Float? = nil, colorNoiseReduction: Float? = nil,
                extendedDynamicRange: Float? = nil, fullFrame: Bool = false) {
        self.temperature = temperature
        self.tint = tint
        self.boostAmount = boostAmount
        self.decoderVersion = decoderVersion
        self.machineLearning = machineLearning
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.extendedDynamicRange = extendedDynamicRange
        self.fullFrame = fullFrame
    }

    public static let none = RAWDecodeSettings()

    /// These settings without the machine learning request: what renders
    /// when it cannot apply.
    public var classical: RAWDecodeSettings {
        var copy = self
        copy.machineLearning = false
        return copy
    }

    /// Sets the decoder up for these settings and returns what became of a
    /// machine learning request.
    ///
    /// The decoder version is, in order: the machine learning version when
    /// asked for and available for this file; else the Profile group's
    /// choice; else the decoder's default, pinned below the machine learning
    /// version (`MachineLearningNoiseReduction.pinnedVersion`). A filter
    /// whose `decoderVersion` was changed before the call is treated as
    /// having that default, which is how tests stand in for a later macOS.
    ///
    /// - Parameter source: The master, for the availability overrides of tests and the debug script.
    @discardableResult
    public func apply(to raw: CIRAWFilter, source: URL? = nil) -> MachineLearningNoiseReduction.Outcome {
        if let temperature { raw.neutralTemperature = temperature }
        if let tint { raw.neutralTint = tint }
        if let boostAmount { raw.boostAmount = boostAmount }
        if let extendedDynamicRange { raw.extendedDynamicRangeAmount = max(raw.extendedDynamicRangeAmount, extendedDynamicRange) }
        let supported = raw.supportedDecoderVersions
        var outcome = MachineLearningNoiseReduction.Outcome.notRequested
        if machineLearning {
            outcome = Self.applyMachineLearning(to: raw, supported: supported.map(\.rawValue), source: source)
        }
        if !outcome.isApplied {
            if let decoderVersion, !MachineLearningNoiseReduction.isMachineLearningVersion(decoderVersion) {
                let version = CIRAWDecoderVersion(rawValue: decoderVersion)
                if supported.contains(version) { raw.decoderVersion = version }
            } else if let pinned = MachineLearningNoiseReduction.pinnedVersion(default: raw.decoderVersion.rawValue,
                                                                                supported: supported.map(\.rawValue)) {
                raw.decoderVersion = CIRAWDecoderVersion(rawValue: pinned)
            }
        }
        if let luminanceNoiseReduction, raw.isLuminanceNoiseReductionSupported {
            raw.luminanceNoiseReductionAmount = luminanceNoiseReduction
        }
        if let colorNoiseReduction, raw.isColorNoiseReductionSupported {
            raw.colorNoiseReductionAmount = colorNoiseReduction
        }
        return outcome
    }

    /// Switches `raw` to the machine learning version, or says why not.
    private static func applyMachineLearning(to raw: CIRAWFilter, supported: [String],
                                             source: URL?) -> MachineLearningNoiseReduction.Outcome {
        let availability = source.map { MachineLearningNoiseReduction.availability(for: $0, decoderVersions: supported) }
            ?? MachineLearningNoiseReduction.availability(
                isRaw: true, systemSupports: MachineLearningNoiseReduction.systemSupportsMachineLearning,
                decoderVersions: supported)
        if let reason = MachineLearningNoiseReduction.Reason(availability) { return .notApplied(reason) }
        guard availability == .available,
              source.flatMap(MachineLearningNoiseReduction.override(for:))?.failsDecode != true,
              let version = MachineLearningNoiseReduction.machineLearningVersion(in: supported)
        else { return .notApplied(.failed) }
        raw.decoderVersion = CIRAWDecoderVersion(rawValue: version)
        // The decoder ignores a version it cannot use.
        return raw.decoderVersion.rawValue == version ? .applied : .notApplied(.failed)
    }
}

/// Applies an edit stack to a decoded master.
///
/// Input and output are in the pipeline's linear working space; conversion to the
/// output color space happens after rendering. Implementations must be cheap to
/// call: they build a lazy Core Image graph, they do not render.
public protocol EditStackRenderer: Sendable {
    /// Settings for the RAW decoder, applied before `apply` sees the image.
    func decodeSettings(for stack: EditStack) -> RAWDecodeSettings

    func apply(_ stack: EditStack, to image: CIImage, context: RenderContext) throws -> CIImage

    /// The stack's turns, straightening and crop, so the source can be decoded
    /// large enough for the part that is kept.
    func geometry(for stack: EditStack) -> Crop

    /// False when the stack's result would clip values above SDR white, so no
    /// HDR rendition should be made from it.
    func preservesExtendedRange(_ stack: EditStack) -> Bool
}

extension EditStackRenderer {
    public func decodeSettings(for stack: EditStack) -> RAWDecodeSettings { .none }

    public func preservesExtendedRange(_ stack: EditStack) -> Bool { true }

    public func geometry(for stack: EditStack) -> Crop { Crop() }

    public func apply(_ stack: EditStack, to image: CIImage) throws -> CIImage {
        try apply(stack, to: image, context: RenderContext())
    }
}

/// Phase 1 renderer: returns the input untouched regardless of the stack.
public struct PassThroughRenderer: EditStackRenderer {
    public init() {}

    public func apply(_ stack: EditStack, to image: CIImage, context: RenderContext) throws -> CIImage {
        image
    }
}
