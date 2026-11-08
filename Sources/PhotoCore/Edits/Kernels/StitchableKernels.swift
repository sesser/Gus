import CoreImage
import Foundation
import Metal

/// Spike, the "Option B" of docs/archive/PHASE5_PLAN.md ("Custom GPU kernels"):
/// Core Image kernels written in Metal and compiled from source at run time
/// with `CIKernel.kernels(withMetalString:)` (macOS 12+, not deprecated), so
/// there is still no Metal build step. Unlike `RuntimeKernels`' processor
/// kernels these are ordinary Core Image kernels: Core Image can fuse them
/// with neighboring filters into one pass instead of giving each its own
/// intermediate texture. They run in the context's working format (`RGBAh`
/// in `RenderEngine`), not in 32-bit float.
///
/// Same operations as `RuntimeKernels`, for a like-for-like comparison.
/// Proof of concept only: `AdjustmentRenderer` does not use these.
public enum StitchableKernels {
    public enum Failure: Error, Equatable {
        case compileFailed(String)
        case missingKernel(String)
    }

    /// True when kernels from Metal source can run here: they need a Metal
    /// device that supports dynamic libraries (`CIKernel.h`).
    public static var isSupported: Bool { MTLCreateSystemDefaultDevice()?.supportsDynamicLibraries == true }

    /// Multiplies color (not alpha) by 2^`ev`, in the working space's linear light.
    public static func exposureGain(_ image: CIImage, ev: Double) throws -> CIImage {
        guard let kernel = try kernel("exposureGain") as? CIColorKernel else {
            throw Failure.missingKernel("exposureGain")
        }
        guard let output = kernel.apply(extent: image.extent, arguments: [image, Float(pow(2, ev))]) else {
            throw Failure.missingKernel("exposureGain")
        }
        return output
    }

    /// A Gaussian blur of standard deviation `sigma` pixels, as a horizontal
    /// then a vertical pass of `2 × radius + 1` taps (`radius = ceil(3σ)`),
    /// the same taps as `RuntimeKernels.gaussianBlur`. The kernel computes and
    /// normalizes the weights itself. Edges repeat the outermost pixels; the
    /// result has the input's extent.
    public static func gaussianBlur(_ image: CIImage, sigma: Double) throws -> CIImage {
        guard sigma > 0 else { return image }
        let kernel = try kernel("blurPass")
        let radius = (3 * sigma).rounded(.up)
        let extent = image.extent
        var result = image.clampedToExtent()
        for vertical in [false, true] {
            let axis = vertical ? CIVector(x: 0, y: 1) : CIVector(x: 1, y: 0)
            // The horizontal pass also covers the rows the vertical one reads beyond the extent.
            let passExtent = vertical ? extent : extent.insetBy(dx: 0, dy: -radius)
            let output = kernel.apply(extent: passExtent, roiCallback: { _, rect in
                vertical ? rect.insetBy(dx: 0, dy: -radius) : rect.insetBy(dx: -radius, dy: 0)
            }, arguments: [result, Float(sigma), Float(radius), axis])
            guard let output else { throw Failure.missingKernel("blurPass") }
            result = output
        }
        return result.cropped(to: extent)
    }

    // MARK: Metal

    static let source = """
        #include <metal_stdlib>
        #include <CoreImage/CoreImage.h>
        using namespace metal;

        extern "C" {
        namespace coreimage {

        [[stitchable]] float4 exposureGain(sample_t color, float gain) {
            return float4(color.rgb * gain, color.a);
        }

        [[stitchable]] float4 blurPass(sampler source, float sigma, float radius, float2 axis,
                                       destination dest) {
            float2 center = dest.coord();
            float4 sum = 0;
            float total = 0;
            for (float i = -radius; i <= radius; i += 1) {
                float weight = exp(-(i * i) / (2 * sigma * sigma));
                sum += source.sample(source.transform(center + axis * i)) * weight;
                total += weight;
            }
            return sum / total;
        }

        }
        }
        """

    /// Compiles the Metal source now rather than on first use, and says how
    /// many kernels it gave.
    @discardableResult
    public static func compile() throws -> Int {
        try compiled.get().count
    }

    static func kernel(_ name: String) throws -> CIKernel {
        guard let kernel = try compiled.get()[name] else { throw Failure.missingKernel(name) }
        return kernel
    }

    /// Compiled once, on first use (Swift runs a static initializer exactly once).
    private static let compiled: Result<[String: CIKernel], Failure> = {
        do {
            let kernels = try CIKernel.kernels(withMetalString: source)
            return .success(Dictionary(kernels.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }))
        } catch {
            return .failure(.compileFailed(String(describing: error)))
        }
    }()
}
