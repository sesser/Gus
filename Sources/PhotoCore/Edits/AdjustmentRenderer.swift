import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders `Adjustments` with built-in Core Image filters.
///
/// The order is fixed, whatever the order of operations in the stack: white
/// balance (non-RAW; RAW files get it from the decoder), exposure, highlights and
/// shadows, dehaze, clarity, the tone table (contrast, whites, blacks, curves),
/// vibrance and saturation, color grading, the look-up table, noise reduction
/// (non-RAW) and sharpening.
public struct AdjustmentRenderer: EditStackRenderer {
    /// Encoding for tone curves and the grading cube: Rec. 2020 primaries with the
    /// sRGB transfer curve, so curve points are spaced the way tones are seen.
    static let perceptualSpace = CGColorSpace(name: CGColorSpace.itur_2020_sRGBGamma)!
    /// `.cube` files are made for display-referred sRGB input.
    static let lookTableSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public let lookTables: LookTableStore?
    /// Noise reduction for files the RAW decoder does not handle.
    public let denoiser: any Denoiser

    public init(lookTables: LookTableStore? = nil, denoiser: any Denoiser = CoreImageDenoiser()) {
        self.lookTables = lookTables
        self.denoiser = denoiser
    }

    public func decodeSettings(for stack: EditStack) -> RAWDecodeSettings {
        Adjustments(stack: stack).decodeSettings
    }

    public func preservesExtendedRange(_ stack: EditStack) -> Bool {
        Adjustments(stack: stack).preservesExtendedRange
    }

    public func apply(_ stack: EditStack, to image: CIImage, context: RenderContext) throws -> CIImage {
        render(Adjustments(stack: stack), to: image, context: context)
    }

    /// The lazy graph for `adjustments` over a decoded image.
    public func render(_ adjustments: Adjustments, to input: CIImage, context: RenderContext) -> CIImage {
        guard !adjustments.isDefault else { return input }
        let extent = input.extent
        var image = input

        if !context.isRaw {
            image = Self.relativeWhiteBalance(image, adjustments.whiteBalance)
        }
        if adjustments.exposure.ev != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(adjustments.exposure.ev)
            image = filter.outputImage ?? image
        }
        let tone = adjustments.tone
        if tone.shadows != 0 || tone.highlights < 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            filter.shadowAmount = Float(tone.shadows / 100 * 0.6)
            filter.highlightAmount = Float(1 + min(tone.highlights, 0) / 100 * 0.6)
            filter.radius = 0
            image = filter.outputImage ?? image
        }
        let presence = adjustments.presence
        if presence.dehaze != 0 {
            image = Self.dehaze(image, amount: presence.dehaze / 100)
        }
        if presence.clarity != 0 {
            image = Self.clarity(image, amount: presence.clarity / 100, extent: extent)
        }
        let table = ToneTable(contrast: tone.contrast / 100 + max(presence.dehaze, 0) / 100 * 0.15,
                              highlights: max(tone.highlights, 0) / 100, whites: tone.whites / 100,
                              blacks: tone.blacks / 100, curve: adjustments.toneCurve)
        if !table.isIdentity {
            image = Self.curves(image, table)
        }
        if presence.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(presence.vibrance / 100)
            image = filter.outputImage ?? image
        }
        let saturation = presence.saturation / 100 + max(presence.dehaze, 0) / 100 * 0.2
        if saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.saturation = Float(1 + saturation)
            filter.brightness = 0
            filter.contrast = 1
            image = filter.outputImage ?? image
        }
        if !adjustments.colorGrade.isIdentity {
            image = Self.cube(image, ColorGradeCube.make(adjustments.colorGrade), colorSpace: Self.perceptualSpace)
        }
        if let identifier = adjustments.lookTable.identifier, adjustments.lookTable.intensity > 0,
           let cube = lookTables?.cube(for: identifier) {
            image = Self.lookTable(image, cube, intensity: adjustments.lookTable.intensity / 100)
        }
        if !context.isRaw, let luminance = adjustments.noiseReduction.luminance, luminance > 0 {
            image = denoiser.denoise(image, amount: luminance / 100, context: context).cropped(to: extent)
        }
        if adjustments.sharpen.amount > 0 {
            image = Self.sharpen(image, adjustments.sharpen, scale: context.scale, extent: extent)
        }
        return image.cropped(to: extent)
    }

    // MARK: Steps

    /// Relative warmth and tint for files that are not RAW.
    static func relativeWhiteBalance(_ image: CIImage, _ balance: WhiteBalance) -> CIImage {
        guard balance.relativeTemperature != 0 || balance.relativeTint != 0 else { return image }
        // Warmer means rendering as if the light were lower in Kelvin: shift in mireds.
        let mired = 1_000_000 / 6500 + balance.relativeTemperature / 100 * 60
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500, y: 0)
        // The filter's positive tint is greener; ours is more magenta.
        filter.targetNeutral = CIVector(x: 1_000_000 / mired, y: -balance.relativeTint / 100 * 50)
        return filter.outputImage ?? image
    }

    /// Positive amounts subtract an estimated veil (the darkest level of each
    /// channel in a reduced copy) and rescale; negative ones add a grey veil.
    static func dehaze(_ image: CIImage, amount: Double) -> CIImage {
        if amount < 0 {
            let k = CGFloat(-amount * 0.5)
            let filter = CIFilter.colorMatrix()
            filter.inputImage = image
            filter.rVector = CIVector(x: 1 - k, y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: 1 - k, z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: 1 - k, w: 0)
            filter.biasVector = CIVector(x: k * 0.3, y: k * 0.3, z: k * 0.3, w: 0)
            return filter.outputImage ?? image
        }
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > 0 else { return image }
        let reduce = CIFilter.lanczosScaleTransform()
        reduce.inputImage = image
        reduce.scale = Float(min(1, 64 / longest))
        reduce.aspectRatio = 1
        guard let small = reduce.outputImage else { return image }
        let minimum = CIFilter.areaMinimum()
        minimum.inputImage = small
        minimum.extent = small.extent
        guard let veil = minimum.outputImage?.clampedToExtent() else { return image }

        let k = CGFloat(amount * 0.9)
        let scaled = CIFilter.colorMatrix()
        scaled.inputImage = veil
        scaled.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        scaled.gVector = CIVector(x: 0, y: k, z: 0, w: 0)
        scaled.bVector = CIVector(x: 0, y: 0, z: k, w: 0)
        scaled.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        scaled.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let remaining = CIFilter.colorMatrix()
        remaining.inputImage = veil
        remaining.rVector = CIVector(x: -k, y: 0, z: 0, w: 0)
        remaining.gVector = CIVector(x: 0, y: -k, z: 0, w: 0)
        remaining.bVector = CIVector(x: 0, y: 0, z: -k, w: 0)
        remaining.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        remaining.biasVector = CIVector(x: 1, y: 1, z: 1, w: 1)

        // Blend modes compute background − input and background ÷ input.
        let subtract = CIFilter.subtractBlendMode()
        subtract.inputImage = scaled.outputImage
        subtract.backgroundImage = image
        let divide = CIFilter.divideBlendMode()
        divide.inputImage = remaining.outputImage
        divide.backgroundImage = subtract.outputImage
        return divide.outputImage?.cropped(to: extent) ?? image
    }

    /// Large-radius unsharp mask in the perceptual encoding. The radius follows
    /// the image size, so every tier shows the same local contrast.
    static func clarity(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image.clampedToExtent()
        let mask = CIFilter.unsharpMask()
        mask.inputImage = encode.outputImage
        mask.radius = Float(max(extent.width, extent.height) * 0.012)
        mask.intensity = Float(amount * 0.6)
        let decode = CIFilter.sRGBToneCurveToLinear()
        decode.inputImage = mask.outputImage
        return decode.outputImage?.cropped(to: extent) ?? image
    }

    static func curves(_ image: CIImage, _ table: ToneTable) -> CIImage {
        let values = table.rgbTable()
        let filter = CIFilter.colorCurves()
        filter.inputImage = image
        filter.curvesData = values.withUnsafeBytes { Data($0) }
        filter.curvesDomain = CIVector(x: 0, y: CGFloat(ToneTable.domainMaximum))
        filter.colorSpace = perceptualSpace
        return filter.outputImage ?? image
    }

    static func cube(_ image: CIImage, _ cube: ColorCube, colorSpace: CGColorSpace) -> CIImage {
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(cube.dimension)
        filter.cubeData = cube.data
        filter.colorSpace = colorSpace
        return filter.outputImage ?? image
    }

    /// Applies a look-up table, mixed with the input by `intensity` (0 … 1).
    public static func lookTable(_ image: CIImage, _ table: ColorCube, intensity: Double) -> CIImage {
        let looked = cube(image, table, colorSpace: lookTableSpace)
        guard intensity < 1 else { return looked }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = image
        mix.targetImage = looked
        mix.time = Float(intensity)
        return mix.outputImage ?? looked
    }

    /// Unsharp mask whose result can be held inside each pixel's neighborhood
    /// (low Detail: no halos) and limited to edges (Masking).
    static func sharpen(_ image: CIImage, _ settings: Sharpen, scale: Double, extent: CGRect) -> CIImage {
        // Sharpening for full-resolution pixels has no visible effect on small renditions.
        guard scale >= 0.2 else { return image }
        let radius = max(settings.radius * scale, 0.25)
        let clamped = image.clampedToExtent()
        let mask = CIFilter.unsharpMask()
        mask.inputImage = clamped
        mask.radius = Float(radius)
        mask.intensity = Float(settings.amount / 100)
        guard var sharpened = mask.outputImage else { return image }

        let detail = settings.detail / 100
        if detail < 1 {
            let neighborhood = Float(max(1, radius))
            let low = CIFilter.morphologyMinimum()
            low.inputImage = clamped
            low.radius = neighborhood
            let high = CIFilter.morphologyMaximum()
            high.inputImage = clamped
            high.radius = neighborhood
            let floor = CIFilter.maximumCompositing()
            floor.inputImage = sharpened
            floor.backgroundImage = low.outputImage
            let ceiling = CIFilter.minimumCompositing()
            ceiling.inputImage = floor.outputImage
            ceiling.backgroundImage = high.outputImage
            if let held = ceiling.outputImage {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = held
                mix.targetImage = sharpened
                mix.time = Float(detail)
                sharpened = mix.outputImage ?? held
            }
        }

        if settings.masking > 0, let edgeMask = edgeMask(clamped, masking: settings.masking / 100, radius: radius) {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = sharpened
            blend.backgroundImage = clamped
            blend.maskImage = edgeMask
            sharpened = blend.outputImage ?? sharpened
        }
        return sharpened.cropped(to: extent)
    }

    /// White where the image has edges stronger than the threshold `masking` sets.
    static func edgeMask(_ image: CIImage, masking: Double, radius: Double) -> CIImage? {
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image
        let edges = CIFilter.edges()
        edges.inputImage = encode.outputImage
        edges.intensity = 1
        let threshold = CGFloat(masking * 0.25)
        let gain = CGFloat(1 / max(0.02, masking * 0.25)) / 3
        // Average the channels, then map the threshold to 0 and twice it to 1.
        let mono = CIFilter.colorMatrix()
        mono.inputImage = edges.outputImage
        let row = CIVector(x: gain, y: gain, z: gain, w: 0)
        mono.rVector = row
        mono.gVector = row
        mono.bVector = row
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: -threshold * gain * 3, y: -threshold * gain * 3, z: -threshold * gain * 3, w: 1)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = mono.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = clamp.outputImage
        blur.radius = Float(radius)
        return blur.outputImage
    }
}

extension Adjustments {
    /// What the RAW decoder should apply for these adjustments.
    public var decodeSettings: RAWDecodeSettings {
        var settings = RAWDecodeSettings()
        if whiteBalance.preset != .asShot {
            settings.temperature = whiteBalance.temperature.map(Float.init)
            settings.tint = whiteBalance.tint.map(Float.init)
        }
        settings.boostAmount = decode.look.boostAmount
        settings.decoderVersion = decode.decoderVersion
        settings.luminanceNoiseReduction = noiseReduction.luminance.map { Float($0 / 100) }
        settings.colorNoiseReduction = noiseReduction.color.map { Float($0 / 100) }
        return settings
    }
}

/// Reduces luminance noise in an image that did not come from the RAW decoder
/// (which has its own). A protocol so a learned denoiser can replace it.
public protocol Denoiser: Sendable {
    /// `amount` is 0 … 1.
    func denoise(_ image: CIImage, amount: Double, context: RenderContext) -> CIImage
}

/// Core Image's noise reduction: smooths flat areas, keeps edges above a threshold.
public struct CoreImageDenoiser: Denoiser {
    public init() {}

    public func denoise(_ image: CIImage, amount: Double, context: RenderContext) -> CIImage {
        let filter = CIFilter.noiseReduction()
        filter.inputImage = image.clampedToExtent()
        filter.noiseLevel = Float(amount * 0.04)
        filter.sharpness = 0.4
        return filter.outputImage ?? image
    }
}
