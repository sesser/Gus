import CoreImage

/// What a renderer needs to know about the image it is given.
public struct RenderContext: Sendable, Hashable {
    /// Decoded pixels per master pixel (1 at full resolution), so radii given at
    /// full resolution can be scaled to the decode.
    public var scale: Double
    /// The image came from the RAW decoder, which already applied the stack's
    /// decode settings.
    public var isRaw: Bool

    public init(scale: Double = 1, isRaw: Bool = false) {
        self.scale = scale
        self.isRaw = isRaw
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

    public init(temperature: Float? = nil, tint: Float? = nil, boostAmount: Float? = nil, decoderVersion: String? = nil,
                luminanceNoiseReduction: Float? = nil, colorNoiseReduction: Float? = nil) {
        self.temperature = temperature
        self.tint = tint
        self.boostAmount = boostAmount
        self.decoderVersion = decoderVersion
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
    }

    public static let none = RAWDecodeSettings()

    public func apply(to raw: CIRAWFilter) {
        if let temperature { raw.neutralTemperature = temperature }
        if let tint { raw.neutralTint = tint }
        if let boostAmount { raw.boostAmount = boostAmount }
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

    /// False when the stack's result would clip values above SDR white, so no
    /// HDR rendition should be made from it.
    func preservesExtendedRange(_ stack: EditStack) -> Bool
}

extension EditStackRenderer {
    public func decodeSettings(for stack: EditStack) -> RAWDecodeSettings { .none }

    public func preservesExtendedRange(_ stack: EditStack) -> Bool { true }

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
