import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders `Adjustments` with built-in Core Image filters.
///
/// The order is fixed, whatever the order of operations in the stack: the
/// turns, straightening and crop, white
/// balance (non-RAW; RAW files get it from the decoder), exposure, highlights and
/// shadows, dehaze, clarity, the tone table (contrast, whites, blacks, curves),
/// the color mixer, vibrance and saturation, color grading, the masks (local
/// adjustments, in list order), the look-up table, the vignette, noise
/// reduction (non-RAW), sharpening (then each mask's local sharpening) and
/// grain. Modules that are turned off are rendered at their defaults.
public struct AdjustmentRenderer: EditStackRenderer {
    /// Encoding for tone curves and the grading cube: Rec. 2020 primaries with the
    /// sRGB transfer curve, so curve points are spaced the way tones are seen.
    static let perceptualSpace = CGColorSpace(name: CGColorSpace.itur_2020_sRGBGamma)!

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

    public func geometry(for stack: EditStack) -> Crop {
        Adjustments(stack: stack).effective.crop
    }

    public func apply(_ stack: EditStack, to image: CIImage, context: RenderContext) throws -> CIImage {
        render(Adjustments(stack: stack), to: image, context: context)
    }

    /// The lazy graph for `adjustments` over a decoded image.
    public func render(_ values: Adjustments, to input: CIImage, context: RenderContext) -> CIImage {
        let adjustments = values.effective
        guard !adjustments.isDefault else { return input }
        let masks = adjustments.local.renderedMasks
        var crop = adjustments.crop
        if crop.isIdentity, let cameraFrame = context.cameraFrame {
            // Decoded whole for the masks: crop back to the camera's frame.
            crop = Crop(rect: cameraFrame)
        }
        var image = crop.apply(to: input)
        let extent = image.extent

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
        let local = LocalToneCurve(shadows: tone.shadows / 100, recovery: max(-tone.highlights, 0) / 100)
        if !local.isIdentity {
            image = Self.localTone(image, local, extent: extent)
        }
        let presence = adjustments.presence
        if presence.dehaze != 0 {
            image = Self.dehaze(image, amount: presence.dehaze / 100, extent: extent)
        }
        if presence.clarity != 0 {
            image = Self.clarity(image, amount: presence.clarity / 100, extent: extent)
        }
        let toneTable = ToneTable(contrast: tone.contrast / 100,
                              highlights: max(tone.highlights, 0) / 100, whites: tone.whites / 100,
                              blacks: tone.blacks / 100, curve: adjustments.toneCurve)
        if !toneTable.isIdentity {
            image = Self.curves(image, toneTable)
        }
        // Before saturation, so a black-and-white conversion (saturation at −100)
        // takes the mixer's luminance changes as its mix.
        if !adjustments.colorMixer.isIdentity {
            image = Self.cube(image, ColorMixerCube.make(adjustments.colorMixer), colorSpace: Self.perceptualSpace)
        }
        if presence.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(presence.vibrance / 100)
            image = filter.outputImage ?? image
        }
        let saturation = presence.saturation / 100
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
        // Masks are made in the mask frame (the image before the crop) and
        // select ranges on the image as it enters this step, the same for each.
        var sharpening: [(amount: Double, alpha: CIImage)] = []
        if !masks.isEmpty {
            let maskRenderer = MaskRenderer(maskFrame: input.extent, crop: crop, selection: image)
            for mask in masks {
                let alpha = maskRenderer.alpha(mask)
                image = applyLocal(image, mask.adjustments, alpha: alpha, context: context, extent: extent)
                if mask.adjustments.sharpen > 0 { sharpening.append((mask.adjustments.sharpen, alpha)) }
            }
        }
        let table = adjustments.lookTable
        if let identifier = table.identifier, table.intensity > 0, let cube = lookTables?.cube(for: identifier) {
            image = Self.lookTable(image, cube, intensity: table.intensity / 100, colorSpace: table.colorSpace)
        }
        if !adjustments.vignette.isIdentity {
            image = Self.vignette(image, adjustments.vignette, extent: extent)
        }
        if !context.isRaw, let luminance = adjustments.noiseReduction.luminance, luminance > 0 {
            image = denoiser.denoise(image, amount: luminance / 100, context: context).cropped(to: extent)
        }
        if adjustments.sharpen.amount > 0 {
            image = Self.sharpen(image, adjustments.sharpen, scale: context.scale, extent: extent)
        }
        for (amount, alpha) in sharpening {
            // The global radius, detail and masking at the local amount, after noise reduction.
            var settings = adjustments.sharpen
            settings.amount = amount
            image = Self.blend(Self.sharpen(image, settings, scale: context.scale, extent: extent), over: image,
                               alpha: alpha, extent: extent)
        }
        if !adjustments.grain.isIdentity {
            image = Self.grain(image, adjustments.grain, extent: extent)
        }
        return image.cropped(to: extent)
    }

    // MARK: Masks

    /// The alpha of the mask `id` of `values` over the rendered frame (grey,
    /// 0 … 1), from the image as it enters the mask step: for the overlay
    /// that shows a mask. Nil when there is no such mask.
    public func maskAlpha(_ values: Adjustments, id: UUID, to input: CIImage, context: RenderContext) -> CIImage? {
        let adjustments = values.effective
        guard let mask = adjustments.local.masks.first(where: { $0.id == id }) else { return nil }
        var crop = adjustments.crop
        if crop.isIdentity, let cameraFrame = context.cameraFrame { crop = Crop(rect: cameraFrame) }
        // Everything before the mask step, nothing after it.
        var upstream = adjustments
        upstream.local = LocalAdjustments()
        upstream.lookTable = LookTable()
        upstream.vignette = Vignette()
        upstream.noiseReduction = NoiseReduction()
        upstream.sharpen = Sharpen()
        upstream.grain = Grain()
        upstream.crop = crop
        let selection = upstream.isDefault ? crop.apply(to: input) : render(upstream, to: input, context: context)
        return MaskRenderer(maskFrame: input.extent, crop: crop, selection: selection).alpha(mask)
    }

    /// One mask's local values over `image`: exposure exactly, as a gain
    /// 2^(EV · α) multiplied in linear light (as the vignette's gain map), then
    /// the other modules on the whole image, blended by α. Estimates that need
    /// the whole image (local tone's smoothed luminance, dehaze's haze) come
    /// from the whole image, never from the masked area.
    func applyLocal(_ image: CIImage, _ values: LocalValues, alpha: CIImage, context: RenderContext,
               extent: CGRect) -> CIImage {
        var result = image
        if values.exposure != 0 {
            let ev = values.exposure
            let gain = MaskRenderer.table(alpha, domain: 0...1) { pow(2, ev * $0) }
            let multiply = CIFilter.multiplyCompositing()
            multiply.inputImage = gain
            multiply.backgroundImage = result
            result = multiply.outputImage?.settingAlphaOne(in: extent).cropped(to: extent) ?? result
        }
        let modules = values.modules
        if !modules.isDefault {
            // Relative white balance applies to RAW files too: their Kelvin is the decoder's, and stays global.
            let adjusted = render(modules, to: result, context: RenderContext(scale: context.scale, isRaw: false))
            result = Self.blend(adjusted, over: result, alpha: alpha, extent: extent)
        }
        return result
    }

    /// base + α · (adjusted − base).
    static func blend(_ adjusted: CIImage, over base: CIImage, alpha: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = adjusted
        filter.backgroundImage = base
        filter.maskImage = alpha
        return filter.outputImage?.cropped(to: extent) ?? base
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

    /// Shadows and highlight recovery: a gain per pixel from an edge-aware,
    /// smoothed luminance, so tones move by region and local detail is kept.
    /// The smoothing is done on a fixed-size copy, so every tier looks the same.
    static func localTone(_ image: CIImage, _ curve: LocalToneCurve, extent: CGRect) -> CIImage {
        let longest = max(extent.width, extent.height)
        guard longest > 0, let guide = luminanceGuide(image, extent: extent) else { return image }

        let reduce = CIFilter.lanczosScaleTransform()
        reduce.inputImage = guide
        reduce.scale = Float(min(1, 256 / longest))
        reduce.aspectRatio = 1
        guard let small = reduce.outputImage else { return image }
        let upsample = CIFilter.edgePreserveUpsample()
        upsample.inputImage = guide
        upsample.smallImage = small
        upsample.spatialSigma = 3
        upsample.lumaSigma = 0.12

        let gain = CIFilter.colorCurves()
        gain.inputImage = upsample.outputImage
        gain.curvesData = curve.gainTable().withUnsafeBytes { Data($0) }
        gain.curvesDomain = CIVector(x: 0, y: CGFloat(LocalToneCurve.domainMaximum))
        gain.colorSpace = RenderEngine.workingColorSpace
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = gain.outputImage
        multiply.backgroundImage = image
        // The upsampled mask's alpha is a hair under one.
        return multiply.outputImage?.settingAlphaOne(in: extent).cropped(to: extent) ?? image
    }

    /// Luminance to a low power, as a grey image: the guide for edge-aware upsampling.
    static func luminanceGuide(_ image: CIImage, extent: CGRect) -> CIImage? {
        let luminance = CIFilter.colorMatrix()
        luminance.inputImage = image
        let row = CIVector(x: 0.2627, y: 0.6780, z: 0.0593, w: 0)
        luminance.rVector = row
        luminance.gVector = row
        luminance.bVector = row
        luminance.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        luminance.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = luminance.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 16, y: 16, z: 16, w: 1)
        // Luminance to a low power: averages are not pulled up by bright areas.
        let encode = CIFilter.gammaAdjust()
        encode.inputImage = clamp.outputImage
        encode.power = Float(LocalToneCurve.encodingPower)
        // The bias makes the matrix's output infinite.
        return encode.outputImage?.cropped(to: extent)
    }

    /// Positive amounts invert the haze model I = J·t + A·(1 − t), as J = I·g − A·(g − 1)
    /// with g = 1/t. The airlight A is the brightest level of the dark channel (each
    /// pixel's lowest component, at its minimum over a small neighborhood), and t
    /// falls as the dark channel nears A, so bright, colorless regions lose the most
    /// veil. The dark channel is found on a fixed-size copy, so every tier looks the
    /// same, and upsampled along the image's edges. Negative amounts add a grey veil.
    static func dehaze(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
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
        guard let guide = luminanceGuide(image, extent: extent),
              let (haze, airlight) = hazeEstimate(image, extent: extent)
        else { return image }
        let upsample = CIFilter.edgePreserveUpsample()
        upsample.inputImage = guide
        upsample.smallImage = haze
        upsample.spatialSigma = 3
        upsample.lumaSigma = 0.12
        let tables = DehazeTables(amount: amount)
        func lookUp(_ values: [Float]) -> CIImage? {
            let filter = CIFilter.colorCurves()
            filter.inputImage = upsample.outputImage
            filter.curvesData = values.withUnsafeBytes { Data($0) }
            filter.curvesDomain = CIVector(x: 0, y: 1)
            filter.colorSpace = RenderEngine.workingColorSpace
            return filter.outputImage
        }
        let gained = CIFilter.multiplyCompositing()
        gained.inputImage = lookUp(tables.gain)
        gained.backgroundImage = image
        let offset = CIFilter.multiplyCompositing()
        offset.inputImage = lookUp(tables.offset)
        offset.backgroundImage = airlight
        // The subtract blend mode clamps to 0 … 1. Addition works on premultiplied
        // values, so each term is doubled at half opacity: the sum is opaque.
        func halfOpacity(_ term: CIImage?, scale: CGFloat) -> CIImage? {
            let filter = CIFilter.colorMatrix()
            filter.inputImage = term
            filter.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.5)
            return filter.outputImage
        }
        let subtract = CIFilter.additionCompositing()
        subtract.inputImage = halfOpacity(offset.outputImage, scale: -2)
        subtract.backgroundImage = halfOpacity(gained.outputImage, scale: 2)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = subtract.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 64, y: 64, z: 64, w: 1)
        // The upsampled haze's alpha is a hair under one.
        return clamp.outputImage?.settingAlphaOne(in: extent).cropped(to: extent) ?? image
    }

    /// The dark channel relative to the airlight (0 … 1) on a reduced copy, and the
    /// airlight as an infinite grey image.
    static func hazeEstimate(_ image: CIImage, extent: CGRect) -> (haze: CIImage, airlight: CIImage)? {
        let longest = max(extent.width, extent.height)
        guard longest > 0 else { return nil }
        let reduce = CIFilter.lanczosScaleTransform()
        reduce.inputImage = image
        reduce.scale = Float(min(1, 256 / longest))
        reduce.aspectRatio = 1
        guard let small = reduce.outputImage else { return nil }
        let smallExtent = small.extent

        // The lowest of the three components, never below zero (resampling rings).
        func component(_ vector: CIVector) -> CIImage? {
            let filter = CIFilter.colorMatrix()
            filter.inputImage = small
            filter.rVector = vector
            filter.gVector = vector
            filter.bVector = vector
            filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return filter.outputImage
        }
        let lowest = CIFilter.minimumCompositing()
        lowest.inputImage = component(CIVector(x: 1, y: 0, z: 0, w: 0))
        lowest.backgroundImage = component(CIVector(x: 0, y: 1, z: 0, w: 0))
        let lowestOfThree = CIFilter.minimumCompositing()
        lowestOfThree.inputImage = lowest.outputImage
        lowestOfThree.backgroundImage = component(CIVector(x: 0, y: 0, z: 1, w: 0))
        let floor = CIFilter.colorClamp()
        floor.inputImage = lowestOfThree.outputImage
        floor.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        floor.maxComponents = CIVector(x: 16, y: 16, z: 16, w: 1)
        let patch = CIFilter.morphologyMinimum()
        // The clamp's alpha floor makes its output infinite.
        patch.inputImage = floor.outputImage?.cropped(to: smallExtent).clampedToExtent()
        patch.radius = 3
        let smooth = CIFilter.gaussianBlur()
        smooth.inputImage = patch.outputImage
        smooth.radius = 3
        guard let dark = smooth.outputImage?.cropped(to: smallExtent) else { return nil }

        let brightest = CIFilter.areaMaximum()
        brightest.inputImage = dark
        brightest.extent = smallExtent
        let airlightFloor = CIFilter.colorClamp()
        airlightFloor.inputImage = brightest.outputImage
        airlightFloor.minComponents = CIVector(x: 0.02, y: 0.02, z: 0.02, w: 1)
        airlightFloor.maxComponents = CIVector(x: 16, y: 16, z: 16, w: 1)
        guard let level = brightest.outputImage?.extent,
              let airlight = airlightFloor.outputImage?.cropped(to: level).clampedToExtent()
        else { return nil }
        // Background ÷ input, at most one.
        let relative = CIFilter.divideBlendMode()
        relative.inputImage = airlight
        relative.backgroundImage = dark
        guard let haze = relative.outputImage?.cropped(to: smallExtent) else { return nil }
        return (haze, airlight)
    }

    /// Large-radius unsharp mask in the perceptual encoding, p + i · (p − G(p)).
    /// The radius follows the image size, so every tier shows the same local
    /// contrast. `CIUnsharpMask` takes no negative intensity (its minimum is 0),
    /// so negative amounts blend toward the same Gaussian instead: the formula
    /// with i < 0.
    static func clarity(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image.clampedToExtent()
        guard let perceptual = encode.outputImage else { return image }
        let radius = Float(max(extent.width, extent.height) * 0.012)
        let intensity = Float(amount * 0.6)
        let sharpened: CIImage?
        if intensity >= 0 {
            let mask = CIFilter.unsharpMask()
            mask.inputImage = perceptual
            mask.radius = radius
            mask.intensity = intensity
            sharpened = mask.outputImage
        } else {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = perceptual
            blur.radius = radius
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = perceptual
            mix.targetImage = blur.outputImage
            mix.time = -intensity
            sharpened = mix.outputImage
        }
        let decode = CIFilter.sRGBToneCurveToLinear()
        decode.inputImage = sharpened
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

    /// Applies a look-up table made for `colorSpace`, mixed with the input by
    /// `intensity` (0 … 1).
    public static func lookTable(_ image: CIImage, _ table: ColorCube, intensity: Double,
                                 colorSpace: LookTable.ColorSpace = .sRGB) -> CIImage {
        let looked = cube(image, table, colorSpace: colorSpace.cgColorSpace)
        guard intensity < 1 else { return looked }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = image
        mix.targetImage = looked
        mix.time = Float(intensity)
        return mix.outputImage ?? looked
    }

    /// An exposure falloff toward the edges: a gain map multiplied in linear
    /// light. Distances are measured so that 1 is a corner, whatever the shape.
    static func vignette(_ image: CIImage, _ settings: Vignette, extent: CGRect) -> CIImage {
        guard extent.width > 0, extent.height > 0 else { return image }
        let midpoint = 0.3 + settings.size / 100 * 0.6
        let inner = max(0, midpoint - 0.35)
        let outer = midpoint + 0.35
        let roundness = settings.roundness / 100
        guard var mask = ellipseMask(extent: extent, inner: inner, outer: outer, roundness: max(roundness, 0))
        else { return image }
        if roundness < 0, let rectangle = rectangleMask(extent: extent, inner: inner, outer: outer) {
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = mask
            mix.targetImage = rectangle
            mix.time = Float(-roundness)
            mask = mix.outputImage ?? mask
        }

        // Smoothstep of the mask to a gain of up to two stops at the edges.
        let stops = settings.amount / 100 * 2
        let count = 256
        var table = [Float](repeating: 1, count: count * 3)
        for i in 0..<count {
            let x = Double(i) / Double(count - 1)
            let value = Float(pow(2, stops * x * x * (3 - 2 * x)))
            table[i * 3] = value
            table[i * 3 + 1] = value
            table[i * 3 + 2] = value
        }
        let gain = CIFilter.colorCurves()
        gain.inputImage = mask.cropped(to: extent)
        gain.curvesData = table.withUnsafeBytes { Data($0) }
        gain.curvesDomain = CIVector(x: 0, y: 1)
        gain.colorSpace = RenderEngine.workingColorSpace
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = gain.outputImage
        multiply.backgroundImage = image
        return multiply.outputImage?.settingAlphaOne(in: extent).cropped(to: extent) ?? image
    }

    /// Black inside, white outside: an ellipse through the corners with the
    /// frame's proportions (roundness 0) or a circle (1).
    static func ellipseMask(extent: CGRect, inner: Double, outer: Double, roundness: Double) -> CIImage? {
        let halfWidth = extent.width / 2
        let halfHeight = extent.height / 2
        let diagonal = hypot(halfWidth, halfHeight)
        let axisX = halfWidth * 2.squareRoot() * (1 - roundness) + diagonal * roundness
        let axisY = halfHeight * 2.squareRoot() * (1 - roundness) + diagonal * roundness
        // A unit gradient, stretched into the ellipse.
        let unit = 1000.0
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = Float(inner * unit)
        gradient.radius1 = Float(outer * unit)
        gradient.color0 = CIColor(red: 0, green: 0, blue: 0)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1)
        return gradient.outputImage?.transformed(by: CGAffineTransform(translationX: extent.midX, y: extent.midY)
            .scaledBy(x: axisX / unit, y: axisY / unit))
    }

    /// Black inside, white outside: a rounded rectangle following the frame.
    static func rectangleMask(extent: CGRect, inner: Double, outer: Double) -> CIImage? {
        // Along each axis the ellipse through the corners crosses the edge's
        // midpoint at 1/√2: scale so both shapes start falling off at the same place.
        let reach = 2.squareRoot()
        let center = CGPoint(x: extent.midX, y: extent.midY)
        var inside: CIImage?
        for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            let half = dx != 0 ? extent.width / 2 : extent.height / 2
            let gradient = CIFilter.smoothLinearGradient()
            gradient.point0 = CGPoint(x: center.x + dx * half * inner * reach, y: center.y + dy * half * inner * reach)
            gradient.point1 = CGPoint(x: center.x + dx * half * outer * reach, y: center.y + dy * half * outer * reach)
            gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
            guard let side = gradient.outputImage else { return nil }
            if let current = inside {
                let multiply = CIFilter.multiplyCompositing()
                multiply.inputImage = side
                multiply.backgroundImage = current
                inside = multiply.outputImage
            } else {
                inside = side
            }
        }
        let invert = CIFilter.colorInvert()
        invert.inputImage = inside
        return invert.outputImage
    }

    /// Grain in the perceptual encoding: random noise grown to the grain size,
    /// softened by low roughness, weighted by tone and added with a linear-light
    /// blend (base + 2 × grain − 1, so mid grey adds nothing).
    static func grain(_ image: CIImage, _ settings: Grain, extent: CGRect) -> CIImage {
        let longest = max(extent.width, extent.height)
        // The generator's alpha is random too: make it opaque before any color math.
        guard longest > 0, let random = CIFilter.randomGenerator().outputImage?.settingAlphaOne(in: .infinite)
        else { return image }
        // Size 1 is about 1/2400 of the long edge: fine grain on a 35 mm frame.
        let cell = settings.size * longest / 2400
        // Grain smaller than a pixel averages out: render it at a pixel, weaker.
        let pixelCell = max(cell, 1)
        let roughness = settings.roughness / 100
        let amplitude = settings.strength / 100 * 0.15 * min(cell, 1) * (1 + (1 - roughness) * 1.5)

        func octave(_ size: Double, offset: Double) -> CIImage {
            random.transformed(by: CGAffineTransform(translationX: extent.minX + offset, y: extent.minY + offset)
                .scaledBy(x: size, y: size))
        }
        // Rough grain is fine and crisp; smooth grain mixes in larger, softer clumps.
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = octave(pixelCell, offset: 0)
        mix.targetImage = octave(pixelCell * 2.5, offset: 517)
        mix.time = Float((1 - roughness) * 0.5)
        guard var noise = mix.outputImage else { return image }
        if roughness < 1 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = noise
            blur.radius = Float(pixelCell * 0.6 * (1 - roughness))
            noise = blur.outputImage ?? noise
        }

        // Centered on 0.5, monochrome mixed with independent channels.
        let color = CGFloat(settings.color / 100)
        let a = CGFloat(amplitude)
        let shape = CIFilter.colorMatrix()
        shape.inputImage = noise
        shape.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        shape.gVector = CIVector(x: a * (1 - color), y: a * color, z: 0, w: 0)
        shape.bVector = CIVector(x: a * (1 - color), y: 0, z: a * color, w: 0)
        shape.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        shape.biasVector = CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 1)
        let grey = CIFilter.colorMatrix()
        grey.inputImage = noise
        grey.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.biasVector = CIVector(x: 0.5, y: 0.5, z: 0.5, w: 1)

        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image
        guard let perceptual = encode.outputImage else { return image }
        // How much grain each tone gets.
        let luminance = CIFilter.colorMatrix()
        luminance.inputImage = perceptual
        let row = CIVector(x: 0.2627, y: 0.6780, z: 0.0593, w: 0)
        luminance.rVector = row
        luminance.gVector = row
        luminance.bVector = row
        luminance.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let weights = CIFilter.colorCurves()
        weights.inputImage = luminance.outputImage
        weights.curvesData = grainWeights(settings).withUnsafeBytes { Data($0) }
        weights.curvesDomain = CIVector(x: 0, y: 1)
        weights.colorSpace = RenderEngine.workingColorSpace
        let weighted = CIFilter.blendWithMask()
        weighted.inputImage = shape.outputImage
        weighted.backgroundImage = grey.outputImage
        weighted.maskImage = weights.outputImage
        let blend = CIFilter.linearLightBlendMode()
        blend.inputImage = weighted.outputImage?.cropped(to: extent)
        blend.backgroundImage = perceptual
        let decode = CIFilter.sRGBToneCurveToLinear()
        decode.inputImage = blend.outputImage
        return decode.outputImage?.settingAlphaOne(in: extent).cropped(to: extent) ?? image
    }

    /// Grain weight (0 … 1) over perceptual luminance, from the three tonal amounts.
    static func grainWeights(_ settings: Grain) -> [Float] {
        let count = 256
        var table = [Float](repeating: 0, count: count * 3)
        for i in 0..<count {
            let luma = Double(i) / Double(count - 1)
            let shadows = 1 - ToneTable.smoothstep(0.15, 0.45, luma)
            let highlights = ToneTable.smoothstep(0.55, 0.85, luma)
            let midtones = max(0, 1 - shadows - highlights)
            let value = Float((shadows * settings.shadows + midtones * settings.midtones
                + highlights * settings.highlights) / 100)
            table[i * 3] = value
            table[i * 3 + 1] = value
            table[i * 3 + 2] = value
        }
        return table
    }

    /// Unsharp mask in the perceptual encoding. Below 100, Detail limits how far a
    /// pixel may overshoot the range of its neighborhood (the halos at strong
    /// edges) without touching texture inside that range; Masking limits it to edges.
    static func sharpen(_ image: CIImage, _ settings: Sharpen, scale: Double, extent: CGRect) -> CIImage {
        // Sharpening for full-resolution pixels has no visible effect on small renditions.
        guard scale >= 0.2 else { return image }
        let radius = sharpeningRadius(settings.radius, scale: scale)
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image.clampedToExtent()
        guard let base = encode.outputImage else { return image }
        let mask = CIFilter.unsharpMask()
        mask.inputImage = base
        mask.radius = Float(radius)
        mask.intensity = Float(settings.amount / 100)
        guard var sharpened = mask.outputImage else { return image }

        if settings.detail < 100 {
            let margin = CGFloat(haloMargin(detail: settings.detail / 100))
            let low = CIFilter.morphologyMinimum()
            low.inputImage = base
            low.radius = Float(max(1, radius))
            let high = CIFilter.morphologyMaximum()
            high.inputImage = base
            high.radius = Float(max(1, radius))
            let floor = CIFilter.maximumCompositing()
            floor.inputImage = sharpened
            floor.backgroundImage = shifted(low.outputImage, by: -margin)
            let ceiling = CIFilter.minimumCompositing()
            ceiling.inputImage = floor.outputImage
            ceiling.backgroundImage = shifted(high.outputImage, by: margin)
            sharpened = ceiling.outputImage ?? sharpened
        }

        if settings.masking > 0, let edgeMask = edgeMask(base, masking: settings.masking / 100, radius: radius) {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = sharpened
            blend.backgroundImage = base
            blend.maskImage = edgeMask
            sharpened = blend.outputImage ?? sharpened
        }
        let decode = CIFilter.sRGBToneCurveToLinear()
        decode.inputImage = sharpened
        return decode.outputImage?.cropped(to: extent) ?? image
    }

    /// The blur radius in rendered pixels for `radius` full-resolution pixels. A
    /// reduced rendition is already softened by its resampling, which a radius
    /// scaled down with it would not reach: the two add like Gaussians.
    static func sharpeningRadius(_ radius: Double, scale: Double) -> Double {
        guard scale < 1 else { return radius }
        let resampling = 0.5 * (1 - scale)
        return max((radius * scale * radius * scale + resampling * resampling).squareRoot(), 0.25)
    }

    /// How far past its neighborhood's range Detail (0 … 1) lets a pixel go, in
    /// the perceptual encoding.
    static func haloMargin(detail: Double) -> Double {
        0.01 + 0.25 * pow(detail, 1.5)
    }

    /// `image` with `offset` added to its color components.
    static func shifted(_ image: CIImage?, by offset: CGFloat) -> CIImage? {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.biasVector = CIVector(x: offset, y: offset, z: offset, w: 0)
        return filter.outputImage
    }

    /// White where the image (perceptually encoded) has edges stronger than the threshold `masking` sets.
    static func edgeMask(_ image: CIImage, masking: Double, radius: Double) -> CIImage? {
        let edges = CIFilter.edges()
        edges.inputImage = image
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
    /// What the RAW decoder should apply for these adjustments (modules that
    /// are turned off leave the decoder's defaults).
    public var decodeSettings: RAWDecodeSettings {
        effective.rawDecodeSettings
    }

    private var rawDecodeSettings: RAWDecodeSettings {
        var settings = RAWDecodeSettings()
        // The crop's rectangle and the masks are in the frame of the whole sensor.
        settings.fullFrame = !crop.isIdentity || !local.renderedMasks.isEmpty
        if whiteBalance.preset != .asShot {
            settings.temperature = whiteBalance.temperature.map(Float.init)
            settings.tint = whiteBalance.tint.map(Float.init)
        }
        settings.boostAmount = decode.look.boostAmount
        // Keep what the sensor recorded above white, for recovery to bring back.
        if tone.highlights < 0 || exposure.ev < 0 {
            settings.extendedDynamicRange = 1
        }
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
