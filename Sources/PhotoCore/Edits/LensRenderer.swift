import CoreImage

/// The Lens heading's steps (docs/features/chromatic-aberration), applied to
/// the decoded image before anything else, the crop included: color
/// alignment, centered on the lens's axis (R9), then fringe removal, which
/// then sees the photo's own colors whatever is changed after it (design
/// §14 OQ2). Both leave the image untouched when off (R11).
extension AdjustmentRenderer {
    /// The edge rule's window (OQ1), in full-resolution pixels: a pixel is near
    /// a high-contrast edge when the luminance within this many pixels of it
    /// spans enough of the range. Wide enough to reach across the soft rim of
    /// an out-of-focus highlight; scaled with the render (`edgeRadius`), so
    /// every size counts the same pixels (R13).
    public static let fringeEdgeWindow = 12.0
    /// The perceptual luminance range (0 … 1) at which the edge rule starts,
    /// and where it is full: a high-contrast edge spans 0.4 of the range (a
    /// dark branch, 0.25, against a bright sky, 0.85, spans 0.6).
    public static let fringeEdgeContrast: ClosedRange<Double> = 0.2...0.4

    /// The image entering the rest of the pipeline: `input` (the decoded
    /// image, before the crop) aligned, then with its fringes grayed.
    /// `adjustments` are the effective ones.
    static func lens(_ adjustments: Adjustments, _ input: CIImage, context: RenderContext) -> CIImage {
        var image = input
        if !adjustments.colorAlignment.isIdentity {
            image = align(image, adjustments.colorAlignment)
        }
        if !adjustments.colorFringes.isIdentity {
            image = removeFringes(image, adjustments.colorFringes, scale: context.scale)
        }
        return image
    }

    // MARK: Color alignment

    /// Red and blue scaled about the middle of `image` (the whole sensor for
    /// a raw, `RAWDecodeSettings.fullFrame`) by their stored magnifications.
    static func align(_ image: CIImage, _ alignment: ColorAlignment) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty, let kernel = try? LensKernels.kernel("lensAlign") else { return image }
        let center = CIVector(x: extent.midX, y: extent.midY)
        let reach = 1 + max(abs(alignment.redScale), abs(alignment.blueScale))
        let output = kernel.apply(extent: extent, roiCallback: { _, rect in
            // The rectangle scaled about the center, plus the interpolation's neighbors.
            CGRect(x: center.x + (rect.minX - center.x) * reach, y: center.y + (rect.minY - center.y) * reach,
                   width: rect.width * reach, height: rect.height * reach)
                .union(rect).insetBy(dx: -2, dy: -2)
        }, arguments: [image.clampedToExtent(), center, Float(alignment.redScale), Float(alignment.blueScale)])
        return output?.cropped(to: extent) ?? image
    }

    // MARK: Fringe removal

    /// The window's radius in pixels of a render at `scale`: whole pixels,
    /// at least one.
    static func edgeRadius(scale: Double) -> Int {
        max(1, Int((fringeEdgeWindow * scale).rounded()))
    }

    /// Near a high-contrast edge (0 … 1, grey) for each pixel of `image`: the
    /// range of perceptual luminance over a square window of `edgeRadius`,
    /// through a smoothstep over `fringeEdgeContrast`, softened by a Gaussian
    /// of a quarter of the radius, so the rule has no hard border.
    static func edgeWeight(_ image: CIImage, scale: Double) -> CIImage? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty,
              let luma = try? LensKernels.colorKernel("lensLuma"),
              let range = try? LensKernels.kernel("lensRangePass"),
              let edge = try? LensKernels.colorKernel("lensEdge"),
              let blur = try? LensKernels.kernel("lensBlurPass")
        else { return nil }
        let radius = CGFloat(edgeRadius(scale: scale))
        let sigma = radius / 4
        let blurRadius = (3 * sigma).rounded(.up)
        guard var image = luma.apply(extent: extent, arguments: [image.clampedToExtent()]) else { return nil }
        // The passes cover what the later ones read beyond the extent.
        let margin = radius + blurRadius
        for (index, axis) in [CIVector(x: 1, y: 0), CIVector(x: 0, y: 1)].enumerated() {
            let horizontal = index == 0
            let passExtent = extent.insetBy(dx: -blurRadius, dy: horizontal ? -margin : -blurRadius)
            guard let pass = range.apply(extent: passExtent, roiCallback: { _, rect in
                horizontal ? rect.insetBy(dx: -radius, dy: 0) : rect.insetBy(dx: 0, dy: -radius)
            }, arguments: [image.clampedToExtent(), Float(radius), axis, Float(horizontal ? 1 : 0)])
            else { return nil }
            image = pass
        }
        let contrast = fringeEdgeContrast
        guard var weight = edge.apply(extent: image.extent, arguments: [image, Float(contrast.lowerBound),
                                                                         Float(contrast.upperBound)])
        else { return nil }
        for (index, axis) in [CIVector(x: 1, y: 0), CIVector(x: 0, y: 1)].enumerated() {
            let horizontal = index == 0
            let passExtent = horizontal ? extent.insetBy(dx: 0, dy: -blurRadius) : extent
            guard let pass = blur.apply(extent: passExtent, roiCallback: { _, rect in
                horizontal ? rect.insetBy(dx: -blurRadius, dy: 0) : rect.insetBy(dx: 0, dy: -blurRadius)
            }, arguments: [weight, Float(sigma), Float(blurRadius), axis])
            else { return nil }
            weight = pass
        }
        return weight.cropped(to: extent)
    }

    /// A slot as the kernels take it: cos and sin of its hue, then half its
    /// reach and its reach in degrees (zeros for an empty slot).
    static func slotVector(_ slot: ColorFringes.Slot?) -> CIVector {
        guard let slot else { return CIVector(x: 0, y: 0, z: 0, w: 0) }
        let reach = ColorFringes.hueReach(tolerance: slot.tolerance)
        return CIVector(x: cos(slot.hue), y: sin(slot.hue), z: reach / 2, w: reach)
    }

    /// `image` with the colors of `fringes`' slots turned toward the gray of
    /// the same luminance near high-contrast edges (R2–R5).
    static func removeFringes(_ image: CIImage, _ fringes: ColorFringes, scale: Double) -> CIImage {
        fringeStep("fringeGray", image, fringes, scale: scale) ?? image
    }

    /// How much of its color each pixel of `image` loses to `fringes`, as a
    /// grey 0 … 1: the fringe map, by the same code as `removeFringes`.
    static func fringeWeight(_ image: CIImage, _ fringes: ColorFringes, scale: Double) -> CIImage {
        fringeStep("fringeMap", image, fringes, scale: scale)
            ?? constant(0).cropped(to: image.extent)
    }

    private static func fringeStep(_ name: String, _ image: CIImage, _ fringes: ColorFringes,
                                   scale: Double) -> CIImage? {
        let extent = image.extent
        guard !fringes.isIdentity, let edge = edgeWeight(image, scale: scale),
              let kernel = try? LensKernels.colorKernel(name) else { return nil }
        return kernel.apply(extent: extent, arguments: [image, edge, slotVector(fringes.slot1),
                                                        slotVector(fringes.slot2)])?.cropped(to: extent)
    }

    // MARK: Fringe map and picking

    /// The fringe map of `values` over a decoded image (grey, 0 … 1, in the
    /// frame on screen: turns, straightening and crop applied). It maps the
    /// stored slots, also while Color Fringes is turned off (design §6), over
    /// the image as the fringe step sees it (aligned as the photo renders).
    public func fringeMap(_ values: Adjustments, to input: CIImage, context: RenderContext) -> CIImage {
        let effective = values.effective
        let crop = Self.crop(effective, context: context)
        let weight = Self.fringeWeight(fringeInput(values, to: input), values.colorFringes, scale: context.scale)
        return crop.apply(to: weight)
    }

    /// The image the fringe step works on and a pick samples (design §14
    /// OQ2): the decoded image, aligned as `values` render, before any slot's
    /// graying and before every other adjustment, so a pick keeps matching
    /// the same fringe when later adjustments change. In the mask frame.
    public func fringeInput(_ values: Adjustments, to input: CIImage) -> CIImage {
        let alignment = values.effective.colorAlignment
        return alignment.isIdentity ? input : Self.align(input, alignment)
    }

    /// A small patch of `okLab`'s color with the adjustments that render
    /// after the fringe step (white balance through color grading, then the
    /// look-up table): how a pixel of that color looks in the photo now,
    /// for the slot's swatch (design §14 OQ2, point 3). In the working space.
    public func swatch(_ okLab: SIMD3<Double>, values: Adjustments, context: RenderContext) -> CIImage {
        var after = values.effective
        after.crop = Crop()
        after.colorAlignment = ColorAlignment()
        after.colorFringes = ColorFringes()
        after.local = LocalAdjustments()
        after.vignette = Vignette()
        after.sharpen = Sharpen()
        after.grain = Grain()
        after.noiseReduction = NoiseReduction()
        let rgb = FringeColorMath.linearRec2020(okLab: okLab)
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let patch = CIImage(color: CIColor(red: rgb.x, green: rgb.y, blue: rgb.z,
                                           colorSpace: RenderEngine.workingColorSpace)!).cropped(to: extent)
        guard !after.isDefault else { return patch }
        let graded = globalSteps(after, patch, extent: extent, context: context, estimates: nil)
        return beforeSharpening(after, graded, context: context).cropped(to: extent)
    }
}
