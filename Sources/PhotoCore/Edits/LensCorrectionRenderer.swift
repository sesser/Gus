import CoreImage

/// The Distortion and Lens Vignetting steps (issue #87): the gain first, on
/// the recorded image (the tables describe the light where it was recorded,
/// and the gain comes before Exposure and the tone sliders, R5), then the
/// warp. Both in one resampling each, with kernels compiled at run time
/// (`LensKernels`), sampling by hand so the CPU reference
/// (`Tests/PhotoCoreTests/Reference/LensCorrectionReference.swift`) can follow.
extension AdjustmentRenderer {
    /// The Distortion and Lens Vignetting kernels can run on this Mac (R11):
    /// when false, those groups apply nothing and say so.
    public static var lensCorrectionKernelsAvailable: Bool { LensKernels.isAvailable }

    /// Entries of the radial lookup tables. Between two entries the kernels
    /// interpolate linearly; for the manual models that is exact to 10⁻⁸ of
    /// the radius.
    static let lensTableCount = 1024

    /// `input` with the plan of `adjustments` (the effective ones) for the
    /// file `context` describes; `input` itself when nothing applies or the
    /// kernels can't run (the Adjust tab says so, `LensCorrectionStatus`).
    static func lensCorrected(_ adjustments: Adjustments, _ input: CIImage, context: RenderContext) -> CIImage {
        let plan = LensCorrectionPlan(adjustments, lens: context.lens)
        guard !plan.isIdentity, LensKernels.isAvailable else { return input }
        let frame = lensFrame(of: input.extent, context: context)
        var image = input
        if let gain = plan.gain { image = applyGain(image, gain, frame: frame) ?? image }
        if let warp = plan.warp { image = applyWarp(image, warp, frame: frame) ?? image }
        return image
    }

    /// The frame the corrections' radii are measured in: the camera's frame
    /// (for a raw decoded whole for its crop or masks) about the middle of
    /// the decode, or the decode itself. A crop never changes it.
    static func lensFrame(of extent: CGRect, context: RenderContext) -> CGRect {
        guard let camera = context.cameraFrame, camera.width > 0, camera.height > 0 else { return extent }
        let width = extent.width * camera.width, height = extent.height * camera.height
        return CGRect(x: extent.midX - width / 2, y: extent.midY - height / 2, width: width, height: height)
    }

    /// One row of `count` 32-bit floats in red (offsets from 1, so a context
    /// that keeps the table in half floats still has them to about 3 · 10⁻⁵).
    static func lensTable(_ count: Int, _ value: (Int) -> Double) -> CIImage {
        var values = [Float](repeating: 0, count: count * 4)
        for index in 0..<count {
            values[index * 4] = Float(value(index) - 1)
            values[index * 4 + 3] = 1
        }
        return CIImage(bitmapData: values.withUnsafeBytes { Data($0) }, bytesPerRow: count * 16,
                       size: CGSize(width: count, height: 1), format: .RGBAf, colorSpace: nil)
    }

    /// The farthest a point of `extent` is from `center`, in pixels.
    static func reach(of extent: CGRect, from center: SIMD2<Double>) -> Double {
        [SIMD2(Double(extent.minX), Double(extent.minY)), SIMD2(Double(extent.maxX), Double(extent.minY)),
         SIMD2(Double(extent.minX), Double(extent.maxY)), SIMD2(Double(extent.maxX), Double(extent.maxY))]
            .map { (($0 - center) * ($0 - center)).sum().squareRoot() }.max() ?? 1
    }

    static func applyGain(_ image: CIImage, _ gain: LensGain, frame: CGRect) -> CIImage? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty, let kernel = try? LensKernels.kernel("lensGain") else { return nil }
        let radius = gain.geometry.radius(of: frame)
        let center = gain.geometry.center(of: frame)
        let reach = max(reach(of: extent, from: center) / radius, 1e-6)
        let count = lensTableCount, last = Double(count - 1)
        let table = lensTable(count) { gain.model.gain(Double($0) / last * reach) }
        let tableExtent = table.extent
        return kernel.apply(extent: extent, roiCallback: { index, rect in index == 0 ? rect : tableExtent },
                            arguments: [image, table, CIVector(x: center.x, y: center.y),
                                        CIVector(x: 1 / radius, y: last / reach, z: last)])?.cropped(to: extent)
    }

    static func applyWarp(_ image: CIImage, _ warp: LensWarp, frame: CGRect) -> CIImage? {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty, let kernel = try? LensKernels.kernel("lensWarp") else { return nil }
        let scale = warp.scale(in: frame)
        let radius = warp.geometry.radius(of: frame)
        let center = warp.geometry.center(of: frame)
        let reach = max(reach(of: extent, from: center) / (radius * scale), 1e-6)
        let count = lensTableCount, last = Double(count - 1)
        let table = lensTable(count) { warp.radial.ratio(Double($0) / last * reach) }
        let tableExtent = table.extent
        let m = warp.geometry.toSensor
        // Where a rectangle of the output reads from: its edge's sources (the
        // warp keeps inside inside), plus the interpolation's neighbors.
        let roi: CIKernelROICallback = { index, rect in
            guard index == 0 else { return tableExtent }
            guard !rect.isInfinite, !rect.isNull else { return extent.insetBy(dx: -2, dy: -2) }
            var box = CGRect.null
            for point in LensWarp.edgePoints(of: rect, count: 8) {
                let source = warp.source(of: CGPoint(x: point.x, y: point.y), in: frame, scale: scale)
                box = box.union(CGRect(x: source.x, y: source.y, width: 0, height: 0))
            }
            return box.insetBy(dx: -2, dy: -2).intersection(extent.insetBy(dx: -2, dy: -2))
        }
        // The area a render reads depends on the warp, and the callback that
        // says so is not in the graph's digest: a context would read the area an
        // earlier render of the same input with another warp needed, and repeat
        // its edge (observed in `LensCorrectionTests`; the RAW decoder's fault,
        // `RAWDecodeGraph`). A clamp keyed on the warp gives each warp's input a
        // digest of its own, and the same warp the same one.
        var hasher = Hasher()
        hasher.combine(warp)
        hasher.combine(scale)
        hasher.combine(frame.origin.x); hasher.combine(frame.origin.y)
        hasher.combine(frame.width); hasher.combine(frame.height)
        let key = RAWDecodeGraph.Key(serial: UInt64(bitPattern: Int64(hasher.finalize())) & ((1 << 44) - 1))
        let input = RAWDecodeGraph.keyed(image, with: key).clampedToExtent()
        return kernel.apply(extent: extent, roiCallback: roi,
                            arguments: [input, table, CIVector(x: center.x, y: center.y),
                                        CIVector(x: m.0, y: m.1, z: m.2, w: m.3),
                                        CIVector(x: 1 / (radius * scale), y: radius, z: last / reach, w: last),
                                        CIVector(x: warp.tangential.x, y: warp.tangential.y),
                                        CIVector(x: extent.minX, y: extent.minY, z: extent.maxX, w: extent.maxY)])?
            .cropped(to: extent)
    }
}
