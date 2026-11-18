import CoreImage
import Foundation

/// Renders spots over the image entering the spot step: the decoded image in
/// the mask frame, after the Lens heading's steps (`AdjustmentRenderer.upstream`).
///
/// Each spot, in placement order, reads the image as the spots before it
/// left it, and writes only the square around its circle:
///
/// - **Clone**: the source circle copied over the spot, at a whole-pixel
///   offset so the copied texture keeps its sharpness.
/// - **Heal**: the copy plus a membrane, the harmonic function on the circle
///   whose boundary values are the difference between the spot's
///   surroundings and the source's (Pérez, Gangnet and Blake, "Poisson Image
///   Editing", SIGGRAPH 2003: the guided interpolation with the source's
///   gradients is the source plus a harmonic correction; Farbman et al.,
///   "Coordinates for Instant Image Cloning", SIGGRAPH 2009: the correction
///   interpolated from boundary differences alone). On a disc the harmonic
///   function with given boundary values is Poisson's integral, whose kernel
///   (R² − r²) / |p − b|² normalized over `boundarySamples` points reduces
///   to weights 1 / |p − b|² (status.md, "Algorithm").
///
/// Both then fade into the image over the feather (smoothstep from the core,
/// R · (1 − feather), to the edge) and are scaled by the opacity. Boundary
/// differences are averaged over a 3 × 3 pixel window just outside the
/// circle, so one noisy pixel does not tint the fill. Every sample is taken
/// at a pixel center or interpolated by hand, so the CPU reference
/// (`Tests/PhotoCoreTests/Reference/SpotReference.swift`) follows the GPU to
/// rounding.
public enum SpotRenderer {
    /// Points on the circle the membrane is interpolated from.
    public static let boundarySamples = 64

    /// `spots` over `image` (the mask frame: its extent is the frame).
    /// Unchanged when there are none, or when the kernels could not be
    /// compiled (the Lens heading's rule, `LensKernels`).
    public static func apply(_ spots: [Spot], to image: CIImage) -> CIImage {
        let extent = image.extent
        guard !spots.isEmpty, !extent.isInfinite, !extent.isEmpty,
              let boundaryKernel = try? SpotKernels.kernel("spotBoundary"),
              let applyKernel = try? SpotKernels.kernel("spotApply") else { return image }
        var result = image
        for spot in spots where spot.opacity > 0 {
            let placed = Placement(spot, extent: extent)
            guard placed.radius > 0 else { continue }
            let rect = placed.rect.intersection(extent)
            guard !rect.isNull, !rect.isEmpty else { continue }
            let input = result.clampedToExtent()
            let count = boundarySamples
            let ring = placed.radius + 1
            let center = placed.center, offset = placed.offset
            var arguments: [Any] = [input]
            var boundary: CIImage?
            if spot.mode == .heal {
                // Both rings, with the 3 × 3 window and the interpolation's neighbors.
                let reach = ring + 3
                let around = CGRect(x: center.x - reach, y: center.y - reach, width: 2 * reach, height: 2 * reach)
                let roi = around.union(around.offsetBy(dx: offset.dx, dy: offset.dy))
                boundary = boundaryKernel.apply(
                    extent: CGRect(x: 0, y: 0, width: count, height: 1),
                    roiCallback: { _, _ in roi },
                    arguments: [input, CIVector(x: center.x, y: center.y), Float(ring),
                                CIVector(x: offset.dx, y: offset.dy), Float(count)])
                guard let boundary else { continue }
                arguments.append(boundary)
            } else {
                // Unused by a clone; a one-pixel stand-in keeps one kernel.
                arguments.append(CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
            }
            arguments += [CIVector(x: center.x, y: center.y), Float(placed.radius), Float(placed.inner),
                          CIVector(x: offset.dx, y: offset.dy), Float(count), Float(spot.opacity / 100),
                          Float(spot.mode == .heal ? 1 : 0)]
            let samples = CGFloat(count)
            // Applied a pixel wider than it is kept: Core Image drops a crop to
            // an image's own extent, and a general kernel's output was then
            // composited over the whole frame (status.md, "Crop to the kernel's extent").
            guard let fixed = applyKernel.apply(extent: rect.insetBy(dx: -1, dy: -1), roiCallback: { index, area in
                index == 0 ? area.union(area.offsetBy(dx: offset.dx, dy: offset.dy))
                           : CGRect(x: 0, y: 0, width: samples, height: 1)
            }, arguments: arguments) else { continue }
            result = fixed.cropped(to: rect).composited(over: result).cropped(to: extent)
        }
        return result
    }

    /// A spot in Core Image's coordinates (y up) over a frame `extent`.
    public struct Placement: Sendable {
        public var center: CGPoint
        public var radius: Double
        /// Where the feather starts: full effect inside it.
        public var inner: Double
        /// From the spot to its source, in whole pixels.
        public var offset: CGVector
        /// The square the spot writes.
        public var rect: CGRect

        public init(_ spot: Spot, extent: CGRect) {
            let width = Double(extent.width), height = Double(extent.height)
            radius = spot.size * max(width, height)
            inner = radius * (1 - spot.feather / 100)
            center = CGPoint(x: Double(extent.minX) + spot.center.x * width, y: Double(extent.maxY) - spot.center.y * height)
            offset = CGVector(dx: ((spot.source.x - spot.center.x) * width).rounded(),
                              dy: -((spot.source.y - spot.center.y) * height).rounded())
            let reach = radius + 1
            rect = CGRect(x: Double(center.x) - reach, y: Double(center.y) - reach, width: 2 * reach, height: 2 * reach)
                .integral
        }
    }
}

/// The spot kernels, in Metal compiled from source at run time as the Lens
/// heading's are (`LensKernels`): each in a library of its own.
enum SpotKernels {
    enum Failure: Error, Equatable {
        case compileFailed(String)
        case missingKernel(String)
    }

    static func kernel(_ name: String) throws -> CIKernel {
        guard let kernel = try compiled.get()[name] else { throw Failure.missingKernel(name) }
        return kernel
    }

    /// Compiled once, on first use.
    private static let compiled: Result<[String: CIKernel], Failure> = {
        do {
            let kernels = try kernelSources.keys.sorted().flatMap {
                try CIKernel.kernels(withMetalString: source(of: $0))
            }
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

    static func source(of kernel: String) -> String {
        header + """
            extern "C" {
            namespace coreimage {

            \(kernelSources[kernel] ?? "")

            }
            }
            """
    }

    static let header = """
        #include <metal_stdlib>
        #include <CoreImage/CoreImage.h>
        using namespace metal;

        /// The image at `point`, interpolated by hand between the four nearest pixel centers.
        float4 spotBilinear(coreimage::sampler source, float2 point) {
            float2 p = point - 0.5f;
            float2 f = floor(p);
            float2 t = p - f;
            float4 a = source.sample(source.transform(f + float2(0.5f, 0.5f)));
            float4 b = source.sample(source.transform(f + float2(1.5f, 0.5f)));
            float4 c = source.sample(source.transform(f + float2(0.5f, 1.5f)));
            float4 d = source.sample(source.transform(f + float2(1.5f, 1.5f)));
            return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
        }

        /// Point `i` of `count` on the circle of `radius` around `center`.
        float2 spotRingPoint(float2 center, float radius, float i, float count) {
            float angle = 6.283185307179586f * (i + 0.5f) / count;
            return center + radius * float2(cos(angle), sin(angle));
        }
        """

    static let kernelSources: [String: String] = [
        // One pixel per boundary point: the surroundings minus the source's,
        // averaged over a 3 × 3 window one pixel apart.
        "spotBoundary": """
        [[stitchable]] float4 spotBoundary(sampler image, float2 center, float ring, float2 offset, float count,
                                           destination dest) {
            float2 b = spotRingPoint(center, ring, floor(dest.coord().x), count);
            float3 sum = float3(0);
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    float2 p = b + float2(dx, dy);
                    sum += spotBilinear(image, p).rgb - spotBilinear(image, p + offset).rgb;
                }
            }
            return float4(sum / 9.0f, 1);
        }
        """,
        "spotApply": """
        [[stitchable]] float4 spotApply(sampler image, sampler boundary, float2 center, float radius, float inner,
                                        float2 offset, float count, float opacity, float heal, destination dest) {
            float2 p = dest.coord();
            float4 base = image.sample(image.transform(p));
            float r = distance(p, center);
            float t = clamp((radius - r) / max(radius - inner, 1.0f), 0.0f, 1.0f);
            float alpha = t * t * (3 - 2 * t) * opacity;
            if (alpha <= 0) { return base; }
            float3 fill = image.sample(image.transform(p + offset)).rgb;
            if (heal > 0.5f) {
                float3 sum = float3(0);
                float weights = 0;
                for (int i = 0; i < int(count); i++) {
                    float2 b = spotRingPoint(center, radius + 1, float(i), count);
                    float2 d = p - b;
                    float w = 1.0f / max(dot(d, d), 1e-4f);
                    sum += w * boundary.sample(boundary.transform(float2(float(i) + 0.5f, 0.5f))).rgb;
                    weights += w;
                }
                fill += sum / weights;
            }
            return float4(mix(base.rgb, fill, alpha), base.a);
        }
        """,
    ]
}
