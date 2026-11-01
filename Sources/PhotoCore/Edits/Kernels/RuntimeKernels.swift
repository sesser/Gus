import CoreImage
import Foundation
import Metal
import Synchronization

/// Spike (docs/PHASE5_PLAN.md, "Custom GPU kernels"): Core Image kernels of
/// our own without a Metal build step. Each is a `CIImageProcessorKernel`
/// whose Metal compute function is compiled from source at run time
/// (`MTLDevice.makeLibrary(source:options:)`, part of Metal.framework, so the
/// Command Line Tools are enough), with the library and pipeline states cached
/// per device. Core Image hands the kernel Metal textures and a command buffer
/// and asks it for the region of input each output tile needs, so
/// neighborhood operations get their halo.
///
/// Proof of concept only: `AdjustmentRenderer` does not use these.
public enum RuntimeKernels {
    public enum Failure: Error, Equatable {
        /// The context is not Metal-backed (no texture or command buffer).
        case noMetal
        case compileFailed(String)
    }

    /// True when there is a Metal device to run on.
    public static var isSupported: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Multiplies color (not alpha) by 2^`ev`, in the working space's linear light.
    public static func exposureGain(_ image: CIImage, ev: Double) throws -> CIImage {
        try GainKernel.apply(withExtent: image.extent, inputs: [image], arguments: ["gain": Float(pow(2, ev))])
    }

    /// A Gaussian blur of standard deviation `sigma` pixels, as a horizontal
    /// then a vertical pass of `2 × radius + 1` taps (`radius = ceil(3σ)`).
    /// Edges repeat the outermost pixels; the result has the input's extent.
    public static func gaussianBlur(_ image: CIImage, sigma: Double) throws -> CIImage {
        let weights = gaussianWeights(sigma: sigma)
        guard weights.count > 1 else { return image }
        let extent = image.extent
        var result = image.clampedToExtent()
        for vertical in [false, true] {
            // The horizontal pass also covers the rows the vertical one reads beyond the extent.
            let passExtent = vertical ? extent : extent.insetBy(dx: 0, dy: -CGFloat(weights.count / 2))
            result = try BlurPassKernel.apply(withExtent: passExtent, inputs: [result],
                                              arguments: ["weights": weights, "vertical": vertical])
        }
        return result.cropped(to: extent)
    }

    /// Normalized taps of a Gaussian, `ceil(3σ)` either side of the center.
    public static func gaussianWeights(sigma: Double) -> [Float] {
        guard sigma > 0 else { return [1] }
        let radius = Int((3 * sigma).rounded(.up))
        let raw = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = raw.reduce(0, +)
        return raw.map { Float($0 / sum) }
    }

    // MARK: Metal

    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void exposureGain(texture2d<float, access::read> source [[texture(0)]],
                                 texture2d<float, access::write> destination [[texture(1)]],
                                 constant float &gain [[buffer(0)]],
                                 constant int2 &offset [[buffer(1)]],
                                 uint2 position [[thread_position_in_grid]]) {
            if (position.x >= destination.get_width() || position.y >= destination.get_height()) return;
            float4 color = source.read(uint2(int2(position) + offset));
            destination.write(float4(color.rgb * gain, color.a), position);
        }

        kernel void blurPass(texture2d<float, access::read> source [[texture(0)]],
                             texture2d<float, access::write> destination [[texture(1)]],
                             constant float *weights [[buffer(0)]],
                             constant int &radius [[buffer(1)]],
                             constant int2 &offset [[buffer(2)]],
                             constant int2 &axis [[buffer(3)]],
                             uint2 position [[thread_position_in_grid]]) {
            if (position.x >= destination.get_width() || position.y >= destination.get_height()) return;
            int2 center = int2(position) + offset;
            float4 sum = 0;
            for (int i = -radius; i <= radius; i++) {
                sum += source.read(uint2(center + axis * i)) * weights[i + radius];
            }
            destination.write(sum, position);
        }
        """

    private struct DeviceKernels {
        var library: MTLLibrary
        var pipelines: [String: MTLComputePipelineState] = [:]
    }

    /// Compiled libraries and pipelines per device (`registryID`).
    private static let cache = Mutex<[UInt64: DeviceKernels]>([:])

    /// Compiles the Metal source and every pipeline for `device` now rather
    /// than on first use.
    public static func compile(on device: any MTLDevice) throws {
        for function in ["exposureGain", "blurPass"] {
            _ = try pipeline(function, device: device)
        }
    }

    /// The compute pipeline for `function` on `device`, compiled on first use.
    static func pipeline(_ function: String, device: any MTLDevice) throws -> any MTLComputePipelineState {
        try cache.withLock { cache in
            var kernels: DeviceKernels
            if let cached = cache[device.registryID] {
                kernels = cached
            } else {
                do {
                    kernels = DeviceKernels(library: try device.makeLibrary(source: source, options: nil))
                } catch {
                    throw Failure.compileFailed(String(describing: error))
                }
            }
            if let pipeline = kernels.pipelines[function] { return pipeline }
            guard let entry = kernels.library.makeFunction(name: function) else { throw Failure.compileFailed(function) }
            let pipeline = try device.makeComputePipelineState(function: entry)
            kernels.pipelines[function] = pipeline
            cache[device.registryID] = kernels
            return pipeline
        }
    }

    /// Encodes `function` over the output, with the input's texture and the
    /// pixel offset from an output position to its input position.
    static func dispatch(_ function: String, input: any CIImageProcessorInput, output: any CIImageProcessorOutput,
                         setArguments: (any MTLComputeCommandEncoder) -> Void) throws {
        guard let source = input.metalTexture, let destination = output.metalTexture,
              let commandBuffer = output.metalCommandBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { throw Failure.noMetal }
        let pipeline = try pipeline(function, device: commandBuffer.device)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        setArguments(encoder)
        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreadgroups(
            MTLSize(width: (destination.width + width - 1) / width, height: (destination.height + height - 1) / height,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        encoder.endEncoding()
    }

    /// Texture rows run top down: the output's top-left pixel lies this far
    /// right and down from the input texture's top-left pixel.
    static func offset(input: any CIImageProcessorInput, output: any CIImageProcessorOutput) -> SIMD2<Int32> {
        SIMD2(Int32((output.region.minX - input.region.minX).rounded()),
              Int32((input.region.maxY - output.region.maxY).rounded()))
    }
}

/// Pointwise: each output pixel reads the same input pixel.
final class GainKernel: CIImageProcessorKernel {
    override class var outputFormat: CIFormat { .RGBAf }

    override class func formatForInput(at input: Int32) -> CIFormat { .RGBAf }

    override class func process(with inputs: [any CIImageProcessorInput]?, arguments: [String: Any]?,
                                output: any CIImageProcessorOutput) throws {
        guard let input = inputs?.first else { throw RuntimeKernels.Failure.noMetal }
        var gain = arguments?["gain"] as? Float ?? 1
        var offset = RuntimeKernels.offset(input: input, output: output)
        try RuntimeKernels.dispatch("exposureGain", input: input, output: output) { encoder in
            encoder.setBytes(&gain, length: MemoryLayout<Float>.size, index: 0)
            encoder.setBytes(&offset, length: MemoryLayout<SIMD2<Int32>>.size, index: 1)
        }
    }
}

/// One pass of a separable blur: needs `radius` extra pixels along its axis.
final class BlurPassKernel: CIImageProcessorKernel {
    override class var outputFormat: CIFormat { .RGBAf }

    override class func formatForInput(at input: Int32) -> CIFormat { .RGBAf }

    override class func roi(forInput input: Int32, arguments: [String: Any]?, outputRect: CGRect) -> CGRect {
        let radius = CGFloat(((arguments?["weights"] as? [Float])?.count ?? 1) / 2)
        return arguments?["vertical"] as? Bool == true ? outputRect.insetBy(dx: 0, dy: -radius)
            : outputRect.insetBy(dx: -radius, dy: 0)
    }

    override class func process(with inputs: [any CIImageProcessorInput]?, arguments: [String: Any]?,
                                output: any CIImageProcessorOutput) throws {
        guard let input = inputs?.first, let weights = arguments?["weights"] as? [Float] else {
            throw RuntimeKernels.Failure.noMetal
        }
        // Texture rows run top down, so the vertical axis is +y either way.
        var axis = arguments?["vertical"] as? Bool == true ? SIMD2<Int32>(0, 1) : SIMD2<Int32>(1, 0)
        var radius = Int32(weights.count / 2)
        var offset = RuntimeKernels.offset(input: input, output: output)
        try RuntimeKernels.dispatch("blurPass", input: input, output: output) { encoder in
            weights.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setBytes(&radius, length: MemoryLayout<Int32>.size, index: 1)
            encoder.setBytes(&offset, length: MemoryLayout<SIMD2<Int32>>.size, index: 2)
            encoder.setBytes(&axis, length: MemoryLayout<SIMD2<Int32>>.size, index: 3)
        }
    }
}
