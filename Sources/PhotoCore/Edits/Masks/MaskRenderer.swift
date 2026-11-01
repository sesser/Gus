import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// A mask's alpha as a lazy Core Image graph over the output frame (grey,
/// 0 … 1), from stock filters and the CPU brush (docs/PHASE6_PLAN.md,
/// "Shapes" and "Kernels").
///
/// Gradients and brushes are made in the mask frame (the image before turns,
/// straightening and crop, `maskFrame` in pixels) and sent through the same
/// `Crop.apply` as the photo, so they stay on the same pixels. Ranges select
/// on `selection`, the image entering the mask step, in the output frame.
struct MaskRenderer {
    var maskFrame: CGRect
    var crop: Crop
    var selection: CIImage

    var outputExtent: CGRect { selection.extent }

    /// The combined and scaled alpha of `mask`.
    func alpha(_ mask: Mask) -> CIImage {
        Self.combine(mask.components.map { (shape($0.shape), $0.operation, $0.invert) }, amount: mask.amount,
                     extent: outputExtent)
    }

    /// Components (alpha c, operation, invert) combined in order: Add
    /// a ← max(a, c), Subtract a ← a · (1 − c), Intersect a ← a · c, c first
    /// inverted to 1 − c when asked. The first component starts from its
    /// operation's identity, 0 for Add and 1 for Subtract and Intersect. The
    /// result is scaled by `amount` / 100 and clamped to 0 … 1.
    static func combine(_ components: [(alpha: CIImage, operation: MaskOperation, invert: Bool)], amount: Double,
                        extent: CGRect) -> CIImage {
        func constant(_ value: Double) -> CIImage {
            CIImage(color: grey(value)).cropped(to: extent)
        }
        var alpha: CIImage?
        for component in components {
            let c = component.invert ? inverted(component.alpha) : component.alpha
            let a = alpha ?? constant(component.operation == .add ? 0 : 1)
            switch component.operation {
            case .add: alpha = alpha == nil ? c : maximum(a, c)
            case .subtract: alpha = multiply(a, inverted(c))
            case .intersect: alpha = multiply(a, c)
            }
        }
        var result = alpha ?? constant(0)
        if amount < 100 {
            result = scaled(result, by: amount / 100)
        }
        return clamped(result).cropped(to: extent)
    }

    func shape(_ shape: MaskShape) -> CIImage {
        switch shape {
        case .linear(let gradient): framed(linear(gradient))
        case .radial(let gradient): framed(radial(gradient))
        case .brush(let brush): framed(BrushRasterizer.image(brush, extent: maskFrame) ?? constant(0, over: maskFrame))
        case .luminanceRange(let range): luminance(range)
        case .colorRange(let range): color(range)
        }
    }

    // MARK: Mask frame

    /// A point of the mask frame in Core Image coordinates (y up).
    func position(_ point: MaskPoint) -> CGPoint {
        CGPoint(x: maskFrame.minX + point.x * maskFrame.width, y: maskFrame.maxY - point.y * maskFrame.height)
    }

    var longEdge: Double { Double(max(maskFrame.width, maskFrame.height)) }

    /// A mask-frame image in the output frame.
    func framed(_ image: CIImage) -> CIImage {
        crop.apply(to: image.cropped(to: maskFrame))
    }

    /// c = 1 − smoothstep(½ − f/2, ½ + f/2, t), t running 0 → 1 from start to
    /// end; a hard step at the middle when the feather is 0.
    func linear(_ gradient: LinearGradient) -> CIImage {
        let a = position(gradient.start), b = position(gradient.end)
        let d = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        guard hypot(d.dx, d.dy) > 1e-9 else { return constant(0, over: maskFrame) }
        let f = gradient.feather / 100
        func at(_ t: Double) -> CGPoint { CGPoint(x: a.x + d.dx * t, y: a.y + d.dy * t) }
        if f > 0 {
            // `CISmoothLinearGradient` is smoothstep between its points (checked by the reference).
            let filter = CIFilter.smoothLinearGradient()
            filter.point0 = at(0.5 - f / 2)
            filter.point1 = at(0.5 + f / 2)
            filter.color0 = Self.grey(1)
            filter.color1 = Self.grey(0)
            return filter.outputImage ?? constant(0, over: maskFrame)
        }
        let ramp = CIFilter.linearGradient()
        ramp.point0 = a
        ramp.point1 = b
        ramp.color0 = Self.grey(0)
        ramp.color1 = Self.grey(1)
        return Self.inverted(Self.threshold(ramp.outputImage, at: 0.5))
    }

    /// c = 1 − smoothstep(1 − f, 1, r), r the elliptical distance (1 on the
    /// ellipse); [r ≤ 1] when the feather is 0.
    ///
    /// r = √(u² + v²) from the coordinates along the ellipse's axes, each a
    /// `CILinearGradient` across the frame, in pointwise arithmetic. A
    /// `CIRadialGradient` squeezed and turned by a transform lost precision
    /// (9 × 10⁻⁴ off the reference); unscaled it was exact.
    func radial(_ gradient: RadialGradient) -> CIImage {
        let center = position(gradient.center)
        let angle = gradient.rotation * .pi / 180
        // The axes turned clockwise in the mask frame (y down), in Core Image's y-up coordinates.
        let axisX = CGVector(dx: cos(angle), dy: -sin(angle))
        let axisY = CGVector(dx: -sin(angle), dy: -cos(angle))
        // Reaches past any pixel of the frame from any center the ranges allow.
        let reach = 6 * longEdge
        func coordinate(_ axis: CGVector, radius: Double) -> CIImage {
            let ramp = CIFilter.linearGradient()
            ramp.point0 = CGPoint(x: center.x - axis.dx * reach, y: center.y - axis.dy * reach)
            ramp.point1 = CGPoint(x: center.x + axis.dx * reach, y: center.y + axis.dy * reach)
            ramp.color0 = Self.grey(0)
            ramp.color1 = Self.grey(1)
            // g = ½ at the center: u = (reach / radius) · (2g − 1), clamped to ±2,
            // past which the mask is 0 anyway, so squares stay small.
            let scale = reach / radius
            return Self.clamped(Self.affine(ramp.outputImage?.cropped(to: maskFrame), scale: 2 * scale, offset: -scale),
                                minimum: -2, maximum: 2)
        }
        let u = coordinate(axisX, radius: gradient.radiusX * longEdge)
        let v = coordinate(axisY, radius: gradient.radiusY * longEdge)
        let root = CIFilter.gammaAdjust()
        root.inputImage = Self.clamped(Self.sum(Self.multiply(u, u), Self.multiply(v, v)), maximum: 8)
        root.power = 0.5
        let r = root.outputImage
        let f = gradient.feather / 100
        guard f > 0 else { return Self.inverted(Self.threshold(r, at: 1)) }
        return Self.inverted(Self.smoothstep(r, from: 1 - f, to: 1))
    }

    // MARK: Ranges

    /// Perceptual luminance (Rec. 2020 Y through the sRGB curve) of `selection`.
    var perceptualLuminance: CIImage? {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = selection
        let row = CIVector(x: 0.2627, y: 0.6780, z: 0.0593, w: 0)
        matrix.rVector = row
        matrix.gVector = row
        matrix.bVector = row
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = Self.clamped(matrix.outputImage)
        return encode.outputImage?.cropped(to: outputExtent)
    }

    /// smoothstep(lower − s, lower, y) · (1 − smoothstep(upper, upper + s, y));
    /// with s = 0, [lower ≤ y ≤ upper].
    func luminance(_ range: LuminanceRange) -> CIImage {
        let y = perceptualLuminance
        let s = range.smoothness
        let low: CIImage, high: CIImage
        if s > 0 {
            low = Self.smoothstep(y, from: range.lower - s, to: range.lower)
            high = Self.inverted(Self.smoothstep(y, from: range.upper, to: range.upper + s))
        } else {
            // At exactly the bound either way: half-float values decide.
            low = Self.threshold(Self.shifted(y, by: Self.below), at: range.lower)
            high = Self.inverted(Self.threshold(y, at: range.upper))
        }
        return Self.multiply(low, high).cropped(to: outputExtent)
    }

    /// Just under one half-float step of a value near 1, so that a threshold
    /// (which keeps values above it) keeps the bound itself.
    static let below = 0x1p-12

    /// Linear Rec. 2020 to the cone responses of OkLab (Ottosson's M1 after
    /// BT.2020's matrix to XYZ).
    static let rec2020ToLMS: [[Double]] = {
        let xyz: [[Double]] = [
            [0.636_958_048_301_291, 0.144_616_903_586_208, 0.168_880_975_164_172],
            [0.262_700_212_011_267, 0.677_998_071_518_871, 0.059_301_716_469_862],
            [0.000_000_000_000_000, 0.028_072_693_049_087, 1.060_985_057_710_791],
        ]
        let m1: [[Double]] = [
            [0.818_933_010_1, 0.361_866_742_4, -0.128_859_713_7],
            [0.032_984_543_6, 0.929_311_871_5, 0.036_145_638_7],
            [0.048_200_301_8, 0.264_366_269_1, 0.633_851_707_0],
        ]
        return (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + m1[r][$1] * xyz[$1][c] } } }
    }()

    static let lmsToLab: [[Double]] = [
        [0.210_454_255_3, 0.793_617_785_0, -0.004_072_046_8],
        [1.977_998_495_1, -2.428_592_205_0, 0.450_593_709_9],
        [0.025_904_037_1, 0.782_771_766_2, -0.808_675_766_0],
    ]

    /// The tolerance's distance, τ = 0.015 + 0.06 × tolerance / 100 (LightCraft's range).
    static func colorDistance(tolerance: Double) -> Double {
        0.015 + 0.06 * tolerance / 100
    }

    /// 1 − smoothstep(τ/2, τ, d), d the smallest weighted OkLab distance
    /// √(Δa² + Δb² + ¼ΔL²) to a sample. The weighting and τ's range follow
    /// LightCraft's (`crates/pipeline/src/masks.rs`, MIT or Apache-2.0; see
    /// THIRD_PARTY_NOTICES.md).
    func color(_ range: ColorRange) -> CIImage {
        guard !range.samples.isEmpty else { return constant(0) }
        let lms = Self.matrix(Self.clamped(selection), Self.rec2020ToLMS)
        let root = CIFilter.gammaAdjust()
        root.inputImage = Self.clamped(lms, maximum: 16)
        root.power = 1.0 / 3
        var nearest: CIImage?
        for sample in range.samples {
            let difference = Self.matrix(root.outputImage, Self.lmsToLab, bias: [-sample.x, -sample.y, -sample.z])
            let squares = Self.multiply(difference, difference)
            let sum = CIFilter.colorMatrix()
            sum.inputImage = squares
            let weights = CIVector(x: 0.25, y: 1, z: 1, w: 0)
            sum.rVector = weights
            sum.gVector = weights
            sum.bVector = weights
            sum.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            sum.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            let distance = CIFilter.gammaAdjust()
            distance.inputImage = Self.clamped(sum.outputImage, maximum: 16)
            distance.power = 0.5
            guard let d = distance.outputImage else { continue }
            nearest = nearest.map { Self.minimum($0, d) } ?? d
        }
        let tau = Self.colorDistance(tolerance: range.tolerance)
        return Self.inverted(Self.smoothstep(nearest, from: tau / 2, to: tau)).cropped(to: outputExtent)
    }

    // MARK: Helpers

    func constant(_ value: Double, over extent: CGRect? = nil) -> CIImage {
        CIImage(color: Self.grey(value)).cropped(to: extent ?? outputExtent)
    }

    /// A grey in the working space, so it reaches the graph unconverted (a
    /// plain `CIColor` is sRGB, and its 1 converts to 0.9999999).
    static func grey(_ value: Double) -> CIColor {
        CIColor(red: value, green: value, blue: value, colorSpace: RenderEngine.workingColorSpace)
            ?? CIColor(red: value, green: value, blue: value)
    }

    /// smoothstep(e₀, e₁, v) = t²(3 − 2t), t = clamp((v − e₀) / (e₁ − e₀), 0, 1),
    /// from pointwise arithmetic filters: exact in float, unlike a table, whose
    /// input Core Image rounds (a 4096-entry smoothstep table was off by 3.4 × 10⁻⁴).
    static func smoothstep(_ image: CIImage?, from e0: Double, to e1: Double) -> CIImage {
        let t = clamped(affine(image, scale: 1 / (e1 - e0), offset: -e0 / (e1 - e0)))
        return multiply(multiply(t, t), affine(t, scale: -2, offset: 3))
    }

    /// `profile` of the input's value over `domain` (values outside it clamp to
    /// its ends), as a 4096-entry table. Its error is the half-float rounding of
    /// its input times the profile's slope (the table itself interpolates).
    static func table(_ image: CIImage?, domain: ClosedRange<Double>, _ profile: (Double) -> Double) -> CIImage {
        let count = 4096
        var values = [Float](repeating: 0, count: count * 3)
        for i in 0..<count {
            let value = Float(profile(Double(i) / Double(count - 1)))
            values[i * 3] = value
            values[i * 3 + 1] = value
            values[i * 3 + 2] = value
        }
        let filter = CIFilter.colorCurves()
        filter.inputImage = image
        filter.curvesData = values.withUnsafeBytes { Data($0) }
        filter.curvesDomain = CIVector(x: domain.lowerBound, y: domain.upperBound)
        filter.colorSpace = RenderEngine.workingColorSpace
        return filter.outputImage ?? CIImage.empty()
    }

    /// 1 where the value is above `threshold`, else 0.
    static func threshold(_ image: CIImage?, at threshold: Double) -> CIImage {
        let filter = CIFilter.colorThreshold()
        filter.inputImage = image
        filter.threshold = Float(threshold)
        return filter.outputImage ?? CIImage.empty()
    }

    static func inverted(_ image: CIImage?) -> CIImage {
        affine(image, scale: -1, offset: 1)
    }

    static func scaled(_ image: CIImage?, by factor: Double) -> CIImage {
        affine(image, scale: factor, offset: 0)
    }

    static func shifted(_ image: CIImage?, by offset: Double) -> CIImage {
        affine(image, scale: 1, offset: offset)
    }

    /// scale · v + offset on color, alpha one.
    static func affine(_ image: CIImage?, scale: Double, offset: Double) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: offset, y: offset, z: offset, w: 1)
        return filter.outputImage?.cropped(to: image?.extent ?? .null) ?? CIImage.empty()
    }

    static func matrix(_ image: CIImage?, _ m: [[Double]], bias: [Double] = [0, 0, 0]) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: m[0][0], y: m[0][1], z: m[0][2], w: 0)
        filter.gVector = CIVector(x: m[1][0], y: m[1][1], z: m[1][2], w: 0)
        filter.bVector = CIVector(x: m[2][0], y: m[2][1], z: m[2][2], w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: bias[0], y: bias[1], z: bias[2], w: 1)
        return filter.outputImage?.cropped(to: image?.extent ?? .null) ?? CIImage.empty()
    }

    static func clamped(_ image: CIImage?, minimum: Double = 0, maximum: Double = 1) -> CIImage {
        let filter = CIFilter.colorClamp()
        filter.inputImage = image
        filter.minComponents = CIVector(x: minimum, y: minimum, z: minimum, w: 1)
        filter.maxComponents = CIVector(x: maximum, y: maximum, z: maximum, w: 1)
        return filter.outputImage?.cropped(to: image?.extent ?? .null) ?? CIImage.empty()
    }

    /// a + b on color. Addition compositing adds premultiplied values and
    /// alphas, so each term goes in doubled at half opacity: the sum is opaque.
    static func sum(_ a: CIImage, _ b: CIImage) -> CIImage {
        func half(_ image: CIImage) -> CIImage? {
            let filter = CIFilter.colorMatrix()
            filter.inputImage = image
            filter.rVector = CIVector(x: 2, y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: 2, z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: 2, w: 0)
            filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.5)
            return filter.outputImage
        }
        let filter = CIFilter.additionCompositing()
        filter.inputImage = half(a)
        filter.backgroundImage = half(b)
        return filter.outputImage?.cropped(to: a.extent.intersection(b.extent)) ?? a
    }

    static func maximum(_ a: CIImage, _ b: CIImage) -> CIImage {
        let filter = CIFilter.maximumCompositing()
        filter.inputImage = a
        filter.backgroundImage = b
        return filter.outputImage ?? a
    }

    static func minimum(_ a: CIImage, _ b: CIImage) -> CIImage {
        let filter = CIFilter.minimumCompositing()
        filter.inputImage = a
        filter.backgroundImage = b
        return filter.outputImage ?? a
    }

    static func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
        let filter = CIFilter.multiplyCompositing()
        filter.inputImage = a
        filter.backgroundImage = b
        return filter.outputImage ?? a
    }
}
