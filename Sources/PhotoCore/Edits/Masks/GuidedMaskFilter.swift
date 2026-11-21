import CoreImage
import Foundation
import Synchronization
import os

/// A stored detection result brought up to the render's size along the
/// photo's own edges (issue #88, R7): the guided filter of He, Sun and Tang
/// ("Guided Image Filtering", ECCV 2010; TPAMI 35(6), 2013), with the gray
/// guide `I` the luminance of the image entering the mask step and the input
/// `p` the result stretched bilinearly over the mask frame.
///
/// For every window ω_k of (2r+1)² pixels, with means μ_k of I and p̄_k of p:
///
///     a_k = cov_k(I, p) / (var_k(I) + ε),   b_k = p̄_k − a_k μ_k,
///     q_i = ā_i I_i + b̄_i,
///
/// ā and b̄ the means of a and b over the windows holding pixel i (eq. 8).
/// Windows repeat the edge pixels; q is clamped to 0 … 1. r is one mask pixel
/// in render pixels (rounded up), ε = 10⁻³ (`epsilon`), both pinned by the
/// CPU reference (`Tests/PhotoCoreTests/Reference/GuidedFilterReference.swift`)
/// and the goldens.
///
/// The context keeps intermediates in half float, where E[I²] − E[I]² loses
/// the variance to cancellation (status.md §7). So the variance and the
/// covariance are never formed that way: the first pass takes, along each
/// row of a window, the means and the moments *about those means*, in float
/// inside the kernel; the second combines the 2r+1 rows of equal count
/// exactly (the variance of the whole is the mean of the rows' variances
/// plus the variance of their means; the same for the covariance).
///
/// Four passes of stitchable kernels compiled from Metal source at run time,
/// one library each (as `LensKernels`). If they can't compile, the result is
/// stretched bilinearly instead, with a log notice.
enum GuidedMaskFilter {
    /// ε of the filter, in the guide's units (perceptual luminance, 0 … 1).
    static let epsilon = 1e-3
    /// The window radius never passes this (a 16k-pixel frame over a 512-pixel mask needs 32).
    static let maximumRadius = 64

    /// The window radius for a result of `rasterSize` over a mask frame of
    /// `frameSize` render pixels: one mask pixel, rounded up, at least 1.
    static func radius(rasterSize: CGSize, frameSize: CGSize) -> Int {
        let across = max(frameSize.width / max(rasterSize.width, 1), frameSize.height / max(rasterSize.height, 1))
        return min(max(Int(across.rounded(.up)), 1), maximumRadius)
    }

    /// The result as an image over `maskFrame` (render pixels), stretched
    /// bilinearly with pixel centers aligned and edges repeated; gray, 0 … 1.
    static func stretched(_ pixels: MaskRaster.Pixels, over maskFrame: CGRect) -> CIImage? {
        // As 32-bit floats: an `L8` image read in a kernel came back off by up
        // to a third of a level (64 read as 63.77), whatever the sampling.
        let values = pixels.levels.map { Float($0) / 255 }
        let raster = CIImage(bitmapData: values.withUnsafeBytes { Data($0) }, bytesPerRow: pixels.width * 4,
                             size: CGSize(width: pixels.width, height: pixels.height), format: .Rf, colorSpace: nil)
        guard let kernel = kernel("guidedStretch") else {
            // Core Image's own linear sampling: close, but its weights are not the reference's.
            return raster.clampedToExtent().samplingLinear()
                .transformed(by: CGAffineTransform(translationX: maskFrame.minX, y: maskFrame.minY)
                    .scaledBy(x: maskFrame.width / CGFloat(pixels.width), y: maskFrame.height / CGFloat(pixels.height)))
                .cropped(to: maskFrame)
        }
        let scale = CIVector(x: CGFloat(pixels.width) / maskFrame.width, y: CGFloat(pixels.height) / maskFrame.height)
        let origin = CIVector(x: maskFrame.minX, y: maskFrame.minY)
        let size = CIVector(x: CGFloat(pixels.width), y: CGFloat(pixels.height))
        // Read at pixel centers, nearest: linear filtering's 8-bit weights blended in a neighbor.
        return kernel.apply(extent: maskFrame, roiCallback: { _, _ in raster.extent },
                            arguments: [raster.clampedToExtent().samplingNearest(), scale, origin, size])
    }

    /// q over `guide`'s extent: `mask` (gray, in the same frame) filtered with
    /// `guide` (gray: its red channel is read) at window radius `radius`.
    static func filter(_ mask: CIImage, guide: CIImage, radius: Int, epsilon: Double = epsilon) -> CIImage? {
        let extent = guide.extent
        guard !extent.isInfinite, !extent.isEmpty,
              let rows = kernel("guidedRows"), let coefficients = kernel("guidedCoefficients"),
              let meanRows = kernel("guidedMeanRows"), let apply = kernel("guidedApply") else { return nil }
        let r = CGFloat(radius)
        // The guide and the mask may arrive turned or straightened (the crop),
        // so they keep linear sampling; the passes' own outputs are read nearest.
        let i = guide.clampedToExtent(), p = mask.clampedToExtent()
        guard let moments = rows.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: -r, dy: 0) },
                                       arguments: [i, p, Float(radius)]),
              let ab = coefficients.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: 0, dy: -r) },
                                          arguments: [moments.clampedToExtent().samplingNearest(), Float(radius),
                                                      Float(epsilon)]),
              let abRows = meanRows.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: -r, dy: 0) },
                                          arguments: [ab.clampedToExtent().samplingNearest(), Float(radius)]),
              let q = apply.apply(extent: extent, roiCallback: { index, rect in
                  index == 0 ? rect.insetBy(dx: 0, dy: -r) : rect
              }, arguments: [abRows.clampedToExtent().samplingNearest(), i, Float(radius)])
        else { return nil }
        return q
    }

    // MARK: Kernels

    static var isAvailable: Bool { (try? compiled.get()) != nil }

    private static func kernel(_ name: String) -> CIKernel? {
        switch compiled {
        case .success(let kernels): return kernels[name]
        case .failure: return nil
        }
    }

    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "masks")

    private static let compiled: Result<[String: CIKernel], LensKernels.Failure> = {
        do {
            let kernels = try sources.keys.sorted().flatMap { name in
                try CIKernel.kernels(withMetalString: source(name))
            }
            return .success(Dictionary(kernels.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }))
        } catch {
            log.error("Guided filter kernels did not compile; detection masks are stretched only: \(String(describing: error), privacy: .public)")
            return .failure(.compileFailed(String(describing: error)))
        }
    }()

    static func source(_ name: String) -> String {
        """
        #include <metal_stdlib>
        #include <CoreImage/CoreImage.h>
        using namespace metal;
        extern "C" {
        namespace coreimage {
        \(sources[name] ?? "")
        }
        }
        """
    }

    /// One library per kernel (see `LensKernels.kernelSources`). Every sample
    /// is taken at a pixel's center, so texture filtering never enters.
    static let sources: [String: String] = [
        // Bilinear between the four nearest result pixels: the result's pixel
        // at f = (x + ½) · w / W − ½ of the frame's pixel x, clamped to the result.
        "guidedStretch": """
        [[stitchable]] float4 guidedStretch(sampler raster, float2 scale, float2 origin, float2 size,
                                            destination dest) {
            float2 f = clamp((dest.coord() - origin) * scale - 0.5f, float2(0), size - 1);
            float2 f0 = floor(f);
            float2 t = f - f0;
            float2 f1 = min(f0 + 1, size - 1);
            float a = raster.sample(raster.transform(float2(f0.x, f0.y) + 0.5f)).r;
            float b = raster.sample(raster.transform(float2(f1.x, f0.y) + 0.5f)).r;
            float c = raster.sample(raster.transform(float2(f0.x, f1.y) + 0.5f)).r;
            float d = raster.sample(raster.transform(float2(f1.x, f1.y) + 0.5f)).r;
            float v = mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
            return float4(v, v, v, 1);
        }
        """,
        // Along a row of 2r+1: the means of I and p, then the covariance and the
        // variance about them. Out: (mean I, mean p, covariance, variance).
        "guidedRows": """
        [[stitchable]] float4 guidedRows(sampler guide, sampler mask, float radius, destination dest) {
            float2 c = dest.coord();
            float n = 2 * radius + 1;
            float sumI = 0, sumP = 0;
            for (float k = -radius; k <= radius; k += 1) {
                float2 at = c + float2(k, 0);
                sumI += guide.sample(guide.transform(at)).r;
                sumP += mask.sample(mask.transform(at)).r;
            }
            float mI = sumI / n, mP = sumP / n;
            float v = 0, cv = 0;
            for (float k = -radius; k <= radius; k += 1) {
                float2 at = c + float2(k, 0);
                float dI = guide.sample(guide.transform(at)).r - mI;
                float dP = mask.sample(mask.transform(at)).r - mP;
                v += dI * dI;
                cv += dI * dP;
            }
            return float4(mI, mP, cv / n, v / n);
        }
        """,
        // Down a column of 2r+1 rows: the window's moments from its rows', then
        // a = cov / (var + ε) and b = mean p − a · mean I. Out: (a, b, 0, 1).
        "guidedCoefficients": """
        [[stitchable]] float4 guidedCoefficients(sampler rows, float radius, float epsilon, destination dest) {
            float2 c = dest.coord();
            float n = 2 * radius + 1;
            float sumM = 0, sumP = 0, sumC = 0, sumV = 0;
            for (float k = -radius; k <= radius; k += 1) {
                float4 s = rows.sample(rows.transform(c + float2(0, k)));
                sumM += s.r;
                sumP += s.g;
                sumC += s.b;
                sumV += s.a;
            }
            float mI = sumM / n, mP = sumP / n;
            float between = 0, betweenC = 0;
            for (float k = -radius; k <= radius; k += 1) {
                float4 s = rows.sample(rows.transform(c + float2(0, k)));
                float d = s.r - mI;
                between += d * d;
                betweenC += d * (s.g - mP);
            }
            float variance = (sumV + between) / n;
            float covariance = (sumC + betweenC) / n;
            float a = covariance / (variance + epsilon);
            return float4(a, mP - a * mI, 0, 1);
        }
        """,
        // Along a row of 2r+1: the means of a and b.
        "guidedMeanRows": """
        [[stitchable]] float4 guidedMeanRows(sampler coefficients, float radius, destination dest) {
            float2 c = dest.coord();
            float2 sum = 0;
            for (float k = -radius; k <= radius; k += 1) {
                sum += coefficients.sample(coefficients.transform(c + float2(k, 0))).rg;
            }
            float2 m = sum / (2 * radius + 1);
            return float4(m, 0, 1);
        }
        """,
        // Down a column of 2r+1: the means of a and b, then q = ā I + b̄.
        "guidedApply": """
        [[stitchable]] float4 guidedApply(sampler coefficients, sampler guide, float radius, destination dest) {
            float2 c = dest.coord();
            float2 sum = 0;
            for (float k = -radius; k <= radius; k += 1) {
                sum += coefficients.sample(coefficients.transform(c + float2(0, k))).rg;
            }
            float2 m = sum / (2 * radius + 1);
            float i = guide.sample(guide.transform(c)).r;
            float q = clamp(m.x * i + m.y, 0.0f, 1.0f);
            return float4(q, q, q, 1);
        }
        """,
    ]
}
