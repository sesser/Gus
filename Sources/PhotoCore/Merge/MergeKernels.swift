import CoreImage
import Foundation

/// The Core Image kernels of an HDR merge (issue #150), written in Metal and
/// compiled from source at run time, each in a library of its own, as
/// `LensKernels` are (Core Image ran one kernel of a library for another).
///
/// The math is `MergeMath`'s and `MergeToneMap`'s; the CPU reference in the
/// tests (`Tests/PhotoCoreTests/Reference/MergeReference.swift`) follows the
/// kernels to float rounding.
enum MergeKernels {
    enum Failure: Error, Equatable {
        case compileFailed(String)
        case missingKernel(String)
    }

    static func kernel(_ name: String) throws -> CIKernel {
        guard let kernel = try compiled.get()[name] else { throw Failure.missingKernel(name) }
        return kernel
    }

    static func colorKernel(_ name: String) throws -> CIColorKernel {
        guard let kernel = try compiled.get()[name] as? CIColorKernel else { throw Failure.missingKernel(name) }
        return kernel
    }

    private static let compiled: Result<[String: CIKernel], Failure> = {
        do {
            let kernels = try sources.keys.sorted().flatMap { try CIKernel.kernels(withMetalString: header + sources[$0]!) }
            return .success(Dictionary(kernels.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }))
        } catch {
            return .failure(.compileFailed(String(describing: error)))
        }
    }()

    /// Compiles now rather than on first use; says how many kernels it gave.
    @discardableResult
    static func compile() throws -> Int {
        try compiled.get().count
    }

    static let header = """
        #include <metal_stdlib>
        #include <CoreImage/CoreImage.h>
        using namespace metal;

        constant float3 lumaWeights = float3(0.2627, 0.6780, 0.0593);
        constant float tapShare = 0.015625;

        /// The broad hat (MergeMath): 1 - (2z - 1)^12 inside (0, 1), else 0; flat at 1 on
        /// the upper half when `openTop`, on the lower half when `openBottom`.
        float mergeHat(float z, float openTop, float openBottom) {
            if (openTop > 0.5f && z >= 0.5f) { return 1.0f; }
            if (openBottom > 0.5f && z <= 0.5f) { return 1.0f; }
            if (z <= 0.0f || z >= 1.0f) { return 0.0f; }
            float t = 2.0f * z - 1.0f;
            float t2 = t * t;
            float t4 = t2 * t2;
            return 1.0f - t4 * t4 * t4;
        }

        """

    static let sources: [String: String] = [
        // One frame added to the running sums at each pixel of the
        // reference: the frame is sampled where the inverse homography (rows
        // h0, h1, h2) puts the pixel, between its four nearest pixel centers
        // (by hand, so the result doesn't depend on the GPU's filtering), and
        // its exposure-normalized color times its weight goes in rgb, the
        // weight in alpha. The weight looks at the brightest of the samples
        // that count (`MergeMath.tapShare` of the mix or more): a pixel next
        // to a clipped one is taken for clipped, since between them the
        // frame's value means nothing.
        // A pixel whose four samples are not all inside the frame adds
        // nothing (MergeMath).
        "mergeAccumulate": """
        [[stitchable]] float4 mergeAccumulate(coreimage::sampler sum, coreimage::sampler frame,
                                              coreimage::sampler ghost, float3 h0, float3 h1, float3 h2,
                                              float2 size, float gain, float clip, float exposure,
                                              float floorWeight, float openTop, float openBottom,
                                              coreimage::destination dest) {
            float2 d = dest.coord();
            float4 total = sum.sample(sum.transform(d));
            float3 hd = float3(d, 1.0f);
            float3 q = float3(dot(h0, hd), dot(h1, hd), dot(h2, hd));
            float2 p = q.xy / q.z;
            if (p.x < 0.5f || p.y < 0.5f || p.x > size.x - 0.5f || p.y > size.y - 0.5f) { return total; }
            float2 b = p - 0.5f;
            float2 f = floor(b);
            float2 t = b - f;
            float4 c00 = frame.sample(frame.transform(f + float2(0.5f, 0.5f)));
            float4 c10 = frame.sample(frame.transform(f + float2(1.5f, 0.5f)));
            float4 c01 = frame.sample(frame.transform(f + float2(0.5f, 1.5f)));
            float4 c11 = frame.sample(frame.transform(f + float2(1.5f, 1.5f)));
            float3 rgb = mix(mix(c00.rgb, c10.rgb, t.x), mix(c01.rgb, c11.rgb, t.x), t.y);
            float m = max(max(c00.r, c00.g), c00.b);
            if (t.x >= tapShare) { m = max(m, max(max(c10.r, c10.g), c10.b)); }
            if (t.y >= tapShare) { m = max(m, max(max(c01.r, c01.g), c01.b)); }
            if (t.x >= tapShare && t.y >= tapShare) { m = max(m, max(max(c11.r, c11.g), c11.b)); }
            float g = clamp(ghost.sample(ghost.transform(d)).r, 0.0f, 1.0f);
            float w = mergeHat(m / clip, openTop, openBottom) * exposure * (1.0f - g);
            w = max(w, floorWeight);
            return float4(total.rgb + w * gain * rgb, total.a + w);
        }
        """,
        // The sums to radiance: MergeMath.resolve.
        "mergeResolve": """
        [[stitchable]] float4 mergeResolve(coreimage::sample_t sum) {
            if (sum.a <= 0.0f) { return float4(0.0f, 0.0f, 0.0f, 1.0f); }
            return float4(sum.rgb / sum.a, 1.0f);
        }
        """,
        // Radiance to a picture (MergeToneMap).
        "mergeToneMap": """
        [[stitchable]] float4 mergeToneMap(coreimage::sample_t radiance, coreimage::sample_t guide,
                                           float compression, float top, float detail, float floorLuminance,
                                           float knee) {
            float3 e = max(radiance.rgb, 0.0f);
            float l = dot(e, lumaWeights);
            if (l <= 0.0f) { return float4(0.0f, 0.0f, 0.0f, 1.0f); }
            float logL = log(max(l, floorLuminance));
            float base = guide.r * logL + guide.g;
            float ld = exp(compression * (base - top) + (logL - base) * detail);
            if (ld > knee) { ld = knee + (1.0f - knee) * (1.0f - exp(-(ld - knee) / (1.0f - knee))); }
            float3 rgb = e * (ld / l);
            float m = max(max(rgb.r, rgb.g), rgb.b);
            if (m > 1.0f) {
                rgb = ld >= 1.0f ? float3(1.0f) : ld + (rgb - ld) * ((1.0f - ld) / (m - ld));
            }
            return float4(rgb, 1.0f);
        }
        """,
    ]
}
