import CoreImage
import Foundation

/// The Core Image kernels of the Lens heading (docs/features/chromatic-aberration),
/// written in Metal and compiled from source at run time
/// (`CIKernel.kernels(withMetalString:)`, as `StitchableKernels`), so there is
/// still no Metal build step. They are ordinary Core Image kernels: the color
/// kernels fuse with their neighbors into one pass.
///
/// Every sample is taken at a pixel's center, and the alignment interpolates
/// by hand, so the result does not depend on the GPU's texture filtering and
/// the CPU references (`Tests/PhotoCoreTests/Reference/LensReference.swift`)
/// can follow it to half-float rounding.
enum LensKernels {
    enum Failure: Error, Equatable {
        case compileFailed(String)
        case missingKernel(String)
    }

    static func colorKernel(_ name: String) throws -> CIColorKernel {
        guard let kernel = try compiled.get()[name] as? CIColorKernel else { throw Failure.missingKernel(name) }
        return kernel
    }

    static func kernel(_ name: String) throws -> CIKernel {
        guard let kernel = try compiled.get()[name] else { throw Failure.missingKernel(name) }
        return kernel
    }

    /// Compiled once, on first use (about 300 ms after a build, `docs/PROFILING.md`).
    private static let compiled: Result<[String: CIKernel], Failure> = {
        do {
            let kernels = try kernelSources.keys.sorted().flatMap { try CIKernel.kernels(withMetalString: source(of: $0)) }
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

    private static func row(_ values: [Double]) -> String {
        "float3(" + values.map { String(format: "%.12f", $0) }.joined(separator: ", ") + ")"
    }

    /// What every kernel source starts with: constants and helpers.
    static let header: String = {
        let m = MaskRenderer.rec2020ToLMS, lab = MaskRenderer.lmsToLab
        return """
            #include <metal_stdlib>
            #include <CoreImage/CoreImage.h>
            using namespace metal;

            constant float3 lumaWeights = float3(0.2627, 0.6780, 0.0593);
            constant float3 lms0 = \(row(m[0]));
            constant float3 lms1 = \(row(m[1]));
            constant float3 lms2 = \(row(m[2]));
            constant float3 lab0 = \(row(lab[0]));
            constant float3 lab1 = \(row(lab[1]));
            constant float3 lab2 = \(row(lab[2]));

            float encodeSRGB(float v) {
                v = clamp(v, 0.0f, 1.0f);
                return v <= 0.0031308f ? v * 12.92f : 1.055f * powr(v, 1.0f / 2.4f) - 0.055f;
            }

            float signedCbrt(float v) {
                return v < 0 ? -powr(-v, 1.0f / 3.0f) : powr(v, 1.0f / 3.0f);
            }

            /// OkLab of a linear Rec. 2020 color clamped to 0 ... 1 (as ColorRange.okLab).
            float3 okLab(float3 rgb) {
                float3 c = clamp(rgb, 0.0f, 1.0f);
                float3 lms = float3(signedCbrt(dot(lms0, c)), signedCbrt(dot(lms1, c)), signedCbrt(dot(lms2, c)));
                return float3(dot(lab0, lms), dot(lab1, lms), dot(lab2, lms));
            }

            /// slot: cos and sin of the slot's hue, then half its reach and its reach,
            /// in degrees; a reach of 0 is an empty slot. Chroma gate: ColorFringes.chromaGate.
            float colorWeight(float2 ab, float4 slot) {
                if (slot.w <= 0) { return 0; }
                float chroma = length(ab);
                float cosine = chroma > 1e-8f ? dot(ab, slot.xy) / chroma : 0.0f;
                float distance = acos(clamp(cosine, -1.0f, 1.0f)) * 57.29577951308232f;
                return (1 - smoothstep(slot.z, slot.w, distance)) * smoothstep(0.002f, 0.01f, chroma);
            }

            float fringeWeight(float3 rgb, float edge, float4 slot1, float4 slot2) {
                float2 ab = okLab(rgb).yz;
                return edge * max(colorWeight(ab, slot1), colorWeight(ab, slot2));
            }

            /// The image at `point`, interpolated by hand between the four nearest pixel centers.
            float4 bilinear(coreimage::sampler source, float2 point) {
                float2 p = point - 0.5f;
                float2 f = floor(p);
                float2 t = p - f;
                float4 a = source.sample(source.transform(f + float2(0.5f, 0.5f)));
                float4 b = source.sample(source.transform(f + float2(1.5f, 0.5f)));
                float4 c = source.sample(source.transform(f + float2(0.5f, 1.5f)));
                float4 d = source.sample(source.transform(f + float2(1.5f, 1.5f)));
                return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
            }
            """
    }()

    /// Each kernel's own Metal source, compiled as a library of its own:
    /// Core Image ran one kernel for another of the same library (status.md,
    /// "Kernels of one library"), so no two share one.
    static let kernelSources: [String: String] = [
        "lensLuma": """
        [[stitchable]] float4 lensLuma(sample_t s) {
            float y = encodeSRGB(dot(s.rgb, lumaWeights));
            return float4(y, y, y, 1);
        }
        """,
        "lensRangePass": """
        [[stitchable]] float4 lensRangePass(sampler source, float radius, float2 axis, float first,
                                            destination dest) {
            float2 center = dest.coord();
            float high = -65504.0f;
            float low = 65504.0f;
            for (float i = -radius; i <= radius; i += 1) {
                float4 v = source.sample(source.transform(center + axis * i));
                high = max(high, v.r);
                low = min(low, first > 0.5f ? v.r : v.g);
            }
            return float4(high, low, 0, 1);
        }
        """,
        "lensEdge": """
        [[stitchable]] float4 lensEdge(sample_t s, float low, float high) {
            float e = smoothstep(low, high, s.r - s.g);
            return float4(e, e, e, 1);
        }
        """,
        "lensBlurPass": """
        [[stitchable]] float4 lensBlurPass(sampler source, float sigma, float radius, float2 axis,
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
        """,
        "fringeGray": """
        [[stitchable]] float4 fringeGray(sample_t s, sample_t edge, float4 slot1, float4 slot2) {
            float w = fringeWeight(s.rgb, edge.r, slot1, slot2);
            float y = dot(s.rgb, lumaWeights);
            return float4(mix(s.rgb, float3(y), w), s.a);
        }
        """,
        "lensAlign": """
        [[stitchable]] float4 lensAlign(sampler source, float2 center, float red, float blue, destination dest) {
            float2 p = dest.coord();
            float2 d = p - center;
            float4 g = source.sample(source.transform(p));
            float r = bilinear(source, center + d * (1 + red)).r;
            float b = bilinear(source, center + d * (1 + blue)).b;
            return float4(r, g.g, b, g.a);
        }
        """,
        "embeddedLens": """
        /// One entry of a row of the lookup table, between its two nearest entries.
        float4 lensTableValue(coreimage::sampler table, float position, float row) {
            float i = floor(position);
            float4 a = table.sample(table.transform(float2(i + 0.5f, row + 0.5f)));
            float4 b = table.sample(table.transform(float2(i + 1.5f, row + 0.5f)));
            return mix(a, b, position - i);
        }

        /// A camera's lens corrections (EmbeddedLensCorrection): each channel taken from
        /// its own place in the recorded image and divided by the light that reached it.
        /// scales: table entries per pixel of destination radius, per pixel of source
        /// radius, and the last entry's index.
        [[stitchable]] float4 embeddedLens(sampler source, sampler table, float2 sourceCenter, float2 outputCenter,
                                           float3 scales, destination dest) {
            float2 d = dest.coord() - outputCenter;
            float3 m = 1.0f + lensTableValue(table, min(length(d) * scales.x, scales.z), 0.0f).rgb;
            float3 radii = length(d) * m * scales.y;
            float r = bilinear(source, sourceCenter + d * m.r).r
                * (1.0f + lensTableValue(table, min(radii.r, scales.z), 1.0f).r);
            float g = bilinear(source, sourceCenter + d * m.g).g
                * (1.0f + lensTableValue(table, min(radii.g, scales.z), 1.0f).r);
            float b = bilinear(source, sourceCenter + d * m.b).b
                * (1.0f + lensTableValue(table, min(radii.b, scales.z), 1.0f).r);
            return float4(r, g, b, 1);
        }
        """,
        "fringeMap": """
            /// How much of its color the pixel loses, as a gray (the fringe map).
            [[stitchable]] float4 fringeMap(sample_t s, sample_t edge, float4 slot1, float4 slot2) {
                float w = fringeWeight(s.rgb, edge.r, slot1, slot2);
                return float4(w, w, w, 1);
            }
        """,
    ]

    static func source(of kernel: String) -> String {
        header + """
            extern "C" {
            namespace coreimage {

            \(kernelSources[kernel] ?? "")

            }
            }
            """
    }
}
