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
    public var decoderVersion: String?
    public var luminanceNoiseReduction: Float?
    public var colorNoiseReduction: Float?
    /// `extendedDynamicRangeAmount`: values above white are kept instead of rolled off.
    public var extendedDynamicRange: Float?
    /// Decode the whole sensor, without the crop the camera recorded
    /// (`CameraFrame`); the edit stack crops instead, or the renderer crops to
    /// the camera's frame (`RenderContext.cameraFrame`).
    public var fullFrame = false

    public init(temperature: Float? = nil, tint: Float? = nil, boostAmount: Float? = nil, decoderVersion: String? = nil,
                luminanceNoiseReduction: Float? = nil, colorNoiseReduction: Float? = nil,
                extendedDynamicRange: Float? = nil, fullFrame: Bool = false) {
        self.temperature = temperature
        self.tint = tint
        self.boostAmount = boostAmount
        self.decoderVersion = decoderVersion
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.extendedDynamicRange = extendedDynamicRange
        self.fullFrame = fullFrame
    }

    public static let none = RAWDecodeSettings()

    public func apply(to raw: CIRAWFilter) {
        if let temperature { raw.neutralTemperature = temperature }
        if let tint { raw.neutralTint = tint }
        if let boostAmount { raw.boostAmount = boostAmount }
        if let extendedDynamicRange { raw.extendedDynamicRangeAmount = max(raw.extendedDynamicRangeAmount, extendedDynamicRange) }
        if let decoderVersion {
            let version = CIRAWDecoderVersion(rawValue: decoderVersion)
            if raw.supportedDecoderVersions.contains(version) { raw.decoderVersion = version }
        }
        if let luminanceNoiseReduction, raw.isLuminanceNoiseReductionSupported {
            raw.luminanceNoiseReductionAmount = luminanceNoiseReduction
        }
        if let colorNoiseReduction, raw.isColorNoiseReductionSupported {
            raw.colorNoiseReductionAmount = colorNoiseReduction
        }
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
