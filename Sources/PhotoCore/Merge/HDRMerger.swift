import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Merges a bracket of photos of one scene into one image of its light, and
/// tone maps it (issue #150). The file-free core: frames in, Core Image
/// graphs out. `HDRMergeJob` reads the files, writes the result and
/// catalogues it.
///
/// Steps, each on the frames' reduced copies (`MergeLimits.measureLongEdge`)
/// except the last:
/// 1. **Align** every frame onto the reference (`MergeAlignment`).
/// 2. **Exposure and clipping** of each frame against the reference (`MergeExposure`).
/// 3. **Ghosts**: where a frame disagrees with the reference (`MergeGhosts`).
/// 4. **Tone statistics** of the merged light on the copy (`MergeToneMap.plan`).
/// 5. At full resolution, the frames are moved, weighted and summed in one
///    Core Image graph (`radiance`), and tone mapped (`toneMapped`); nothing is
///    rendered until the caller renders it, in tiles Core Image chooses.
public struct HDRMerger: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// The frame at this index doesn't line up with the reference.
        case misaligned(frame: Int)
        /// The frame at this index has another size than the reference.
        case sizeMismatch(frame: Int)
        case kernelsUnavailable
        case renderFailed
        /// The frames' pixels would take more memory than the merge may use.
        case overBudget
    }

    /// The measurements a merge renders from.
    public struct Plan: Sendable {
        public var reference: Int
        /// Each frame's exposure, clipping level and movement onto the
        /// reference, measured on the reduced copy (`measureSize`).
        public var frames: [MergeFramePlan]
        /// Ghost masks on the reduced copy, one per frame.
        public var ghosts: [MergePlane]
        public var toneMap: MergeToneMap
        /// The merged light's brightest channel value (its 99.99th
        /// percentile on the copy), relative to the reference's exposure.
        public var brightest: Double
        /// The reduced copy's size.
        public var measureSize: CGSize
    }

    /// A context of its own: the merge's sums need more than half-float
    /// precision (a 9-frame sum of weights), and its intermediate renders are
    /// read once.
    public let context: CIContext

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "merge")

    public init(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: RenderEngine.workingColorSpace,
            .workingFormat: CIFormat.RGBAf,
            .cacheIntermediates: false,
            .name: "hdr-merge",
        ]
        context = device.map { CIContext(mtlDevice: $0, options: options) } ?? CIContext(options: options)
    }

    // MARK: Frames

    /// A frame's reduced copy for measuring, rendered now: the decoder and
    /// its buffers are let go before the next frame is decoded.
    public func measuringCopy(of url: URL, source: MergeDecoder.Source) throws -> MergeBitmap {
        // The decoder's objects are autoreleased: drained here, not when the task ends.
        try autoreleasepool {
            let image = try MergeDecoder.linearImage(url, source: source, longEdge: MergeLimits.measureLongEdge)
            guard let bitmap = MergeBitmap.render(image, context: context) else { throw Failure.renderFailed }
            return bitmap
        }
    }

    /// A frame at full resolution, rendered now into half floats (8 bytes a
    /// pixel) and given back as an image over those pixels: the merge then
    /// holds the frames' pixels and nothing of their decoders, whose own
    /// buffers are several times larger (status.md, "Spike 3").
    /// Throws `overBudget` before allocating when its pixels would take more
    /// than `budget` bytes (security review M1).
    public func fullFrame(of url: URL, source: MergeDecoder.Source, budget: Int = .max) throws -> CIImage {
        try autoreleasepool {
            let image = try MergeDecoder.linearImage(url, source: source, longEdge: nil)
            let extent = image.extent.integral
            guard MergeLimits.heldBytes(pixels: Int(extent.width) * Int(extent.height), frames: 1) <= budget else {
                throw Failure.overBudget
            }
            return try held(image)
        }
    }

    /// `image` rendered into half floats in memory, as an image over them.
    public func held(_ image: CIImage) throws -> CIImage {
        let extent = image.extent.integral
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { throw Failure.renderFailed }
        let width = Int(extent.width), height = Int(extent.height)
        var data = Data(count: width * height * 8)
        data.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 8, bounds: extent, format: .RGBAh,
                           colorSpace: RenderEngine.workingColorSpace)
        }
        return CIImage(bitmapData: data, bytesPerRow: width * 8, size: CGSize(width: width, height: height),
                       format: .RGBAh, colorSpace: RenderEngine.workingColorSpace)
    }

    // MARK: Measuring

    /// Measures a merge from the frames' reduced copies (linear, all of one
    /// size). `metadataExposures` are the files' exposure values, for when
    /// the pixels can't tell.
    /// `aligned` is told how many frames are lined up so far.
    public func plan(measuring bitmaps: [MergeBitmap], reference: Int, metadataExposures: [Double?],
                     aligned report: (_ done: Int) -> Void = { _ in }) throws -> Plan {
        try MergeKernels.compile()
        let copies = bitmaps.map { $0.ciImage() }
        let ref = bitmaps[reference]
        for (index, bitmap) in bitmaps.enumerated() where bitmap.width != ref.width || bitmap.height != ref.height {
            throw Failure.sizeMismatch(frame: index)
        }
        let homographies: [MergeAlignment.Homography]
        do {
            homographies = try MergeAlignment.align(bitmaps, reference: reference, progress: report)
        } catch MergeAlignment.Failure.misaligned(let frame) {
            throw Failure.misaligned(frame: frame)
        }
        try Task.checkCancellation()
        let measureSize = CGSize(width: ref.width, height: ref.height)
        let extent = CGRect(origin: .zero, size: measureSize)
        let aligned = try zip(copies, homographies).map { image, homography -> MergeBitmap in
            guard let bitmap = MergeBitmap.render(Self.warp(image, by: homography, to: extent), context: context,
                                                  bounds: extent) else {
                throw Failure.renderFailed
            }
            return bitmap
        }
        let clips = MergeExposure.clipLevels(aligned)
        let exposures = MergeExposure.exposures(aligned, clips: clips, reference: reference, metadata: metadataExposures)
        let plans = (0..<copies.count).map { index in
            MergeFramePlan(exposure: exposures[index], clip: clips[index], homography: homographies[index])
        }
        let ghosts = MergeGhosts.masks(aligned, plans: plans, reference: reference)
        try Task.checkCancellation()

        // The merged light on the copy, through the same kernels as at full size.
        let merged = try radiance(frames: copies, plans: plans, ghosts: ghosts.map { $0.ciImage() },
                                  reference: reference, extent: extent)
        guard let mergedBitmap = MergeBitmap.render(merged, context: context) else { throw Failure.renderFailed }
        let toneMap = MergeToneMap.plan(for: mergedBitmap)
        var maxima = (0..<mergedBitmap.count).map { index -> Float in
            let rgb = mergedBitmap.rgb(index)
            return max(rgb.x, rgb.y, rgb.z)
        }
        maxima.sort()
        let brightest = Double(maxima.isEmpty ? 1 : maxima[min(maxima.count - 1, Int(Double(maxima.count) * 0.9999))])

        Self.log.info("Merge plan: exposures \(exposures.map { String(format: "%.3f", $0) }.joined(separator: " "), privacy: .public), clips \(clips.map { String(format: "%.3f", $0) }.joined(separator: " "), privacy: .public)")
        return Plan(reference: reference, frames: plans, ghosts: ghosts, toneMap: toneMap, brightest: brightest,
                    measureSize: measureSize)
    }

    // MARK: Graphs

    /// The merged light at full resolution: `frames` are the full-size linear
    /// decodes, in the plan's order, all of the reference's size, which is
    /// the result's. The movements measured on the copy are scaled to it.
    public func radiance(_ plan: Plan, frames: [CIImage]) throws -> CIImage {
        let size = frames[plan.reference].extent.integral.size
        let extent = CGRect(origin: .zero, size: size)
        for (index, frame) in frames.enumerated() where frame.extent.integral.size != size {
            throw Failure.sizeMismatch(frame: index)
        }
        let factor = Double(size.width) / Double(plan.measureSize.width)
        var scaled = plan.frames
        for index in scaled.indices { scaled[index].homography = scaled[index].homography.scaled(by: factor) }
        let masks = plan.ghosts.map { Self.enlarged($0.ciImage(), to: extent) }
        return try radiance(frames: frames, plans: scaled, ghosts: masks, reference: plan.reference, extent: extent)
    }

    /// The merged light, tone mapped: linear Rec. 2020 within 0 to 1.
    public func toneMapped(_ plan: Plan, radiance: CIImage) throws -> CIImage {
        let extent = radiance.extent
        let guide = Self.guideImage(plan.toneMap, to: extent)
        return try Self.toneMap(radiance, guide: guide, plan: plan.toneMap, extent: extent)
    }

    static func toneMap(_ radiance: CIImage, guide: CIImage, plan: MergeToneMap, extent: CGRect) throws -> CIImage {
        let kernel = try MergeKernels.colorKernel("mergeToneMap")
        guard let mapped = kernel.apply(extent: extent, arguments: [
            radiance, guide, Float(plan.compression), Float(plan.top), Float(plan.detail), MergeToneMap.floorLuminance,
            MergeToneMap.knee,
        ]) else { throw Failure.renderFailed }
        return mapped
    }

    /// The guided filter's coefficients as an image (a in red, b in green), enlarged to `extent`.
    static func guideImage(_ plan: MergeToneMap, to extent: CGRect) -> CIImage {
        var rgba = [Float](repeating: 1, count: plan.guideA.values.count * 4)
        for index in plan.guideA.values.indices {
            rgba[index * 4] = plan.guideA.values[index]
            rgba[index * 4 + 1] = plan.guideB.values[index]
            rgba[index * 4 + 2] = 0
        }
        let data = rgba.withUnsafeBytes { Data($0) }
        let image = CIImage(bitmapData: data, bytesPerRow: plan.guideA.width * 16,
                            size: CGSize(width: plan.guideA.width, height: plan.guideA.height), format: .RGBAf,
                            colorSpace: nil)
        return enlarged(image, to: extent)
    }

    /// A reduced-size map enlarged to cover `extent` (bilinear, edges clamped).
    static func enlarged(_ image: CIImage, to extent: CGRect) -> CIImage {
        let size = image.extent.size
        guard size != extent.size else { return image }
        let transform = CGAffineTransform(scaleX: extent.width / size.width, y: extent.height / size.height)
        return image.clampedToExtent().samplingLinear().transformed(by: transform).cropped(to: extent)
    }

    private func radiance(frames: [CIImage], plans: [MergeFramePlan], ghosts: [CIImage], reference: Int,
                          extent: CGRect) throws -> CIImage {
        let accumulate = try MergeKernels.kernel("mergeAccumulate")
        let resolve = try MergeKernels.colorKernel("mergeResolve")
        var sum = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let darkest = plans.indices.min { plans[$0].exposure < plans[$1].exposure }
        let brightest = plans.indices.max { plans[$0].exposure < plans[$1].exposure }
        for (index, frame) in frames.enumerated() {
            let plan = plans[index]
            let homography = plan.homography
            let inverse = homography.inverse.matrix
            // Rows of the inverse (simd matrices are column-major).
            let rows = (0..<3).map { row in CIVector(x: inverse[0][row], y: inverse[1][row], z: inverse[2][row]) }
            let size = frame.extent.size
            let source = frame.clampedToExtent()
            guard let next = accumulate.apply(extent: extent, roiCallback: { input, rect in
                guard input == 1 else { return rect }
                return Self.sourceRect(of: rect, inverse: homography.inverse).intersection(
                    CGRect(origin: .zero, size: size).insetBy(dx: -2, dy: -2))
            }, arguments: [
                sum, source, ghosts[index].clampedToExtent(), rows[0], rows[1], rows[2],
                CIVector(x: size.width, y: size.height), Float(1 / plan.exposure), Float(plan.clip),
                Float(plan.exposure), index == reference ? MergeMath.referenceFloorWeight : Float(0),
                Float(index == darkest ? 1 : 0), Float(index == brightest ? 1 : 0),
            ]) else { throw Failure.renderFailed }
            sum = next
        }
        guard let result = resolve.apply(extent: extent, arguments: [sum]) else { throw Failure.renderFailed }
        return result
    }

    /// The part of a frame the pixels of `rect` read: its corners through the
    /// inverse homography, grown by two pixels for the four samples around each.
    static func sourceRect(of rect: CGRect, inverse: MergeAlignment.Homography) -> CGRect {
        let corners = [(rect.minX, rect.minY), (rect.maxX, rect.minY), (rect.minX, rect.maxY), (rect.maxX, rect.maxY)]
            .map { inverse.apply(SIMD2(Double($0.0), Double($0.1))) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -2, dy: -2).integral
    }

    /// `image` moved by `homography` onto `extent` (transparent where it doesn't reach).
    static func warp(_ image: CIImage, by homography: MergeAlignment.Homography, to extent: CGRect) -> CIImage {
        guard homography != .identity else { return image.cropped(to: extent) }
        let size = image.extent.size
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = image
        func point(_ x: Double, _ y: Double) -> CGPoint {
            let p = homography.apply(SIMD2(x, y))
            return CGPoint(x: p.x, y: p.y)
        }
        filter.bottomLeft = point(0, 0)
        filter.bottomRight = point(Double(size.width), 0)
        filter.topLeft = point(0, Double(size.height))
        filter.topRight = point(Double(size.width), Double(size.height))
        return (filter.outputImage ?? image).cropped(to: extent)
    }
}
