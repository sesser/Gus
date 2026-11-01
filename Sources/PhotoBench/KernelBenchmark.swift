import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import PhotoCore
import PhotoFixtures

/// The custom-kernel spike (`RuntimeKernels`) against the stock filters they
/// mirror, on a 24-megapixel image at preview size and at full size. The
/// source is uploaded once; each render goes to a GPU texture and is waited
/// for, so the times are GPU work plus Core Image's planning, not uploads or
/// read-backs. The first call of each kernel includes compiling it.
enum KernelBenchmark {
    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let (width, height) = arguments.size("size", default: (6000, 4000))
        let runs = arguments.int("runs", default: 7)
        let sigma = Double(arguments.int("sigma", default: 4))
        guard let device = MTLCreateSystemDefaultDevice() else { throw BenchError("no Metal device") }
        let engine = RenderEngine(device: device, contextCount: 1, name: "kernel-bench")

        print("Scene: \(width) × \(height), σ = \(sigma), \(runs) runs, \(device.name)")
        let source = try upload(TestScene.hazyLandscape.image(width: width, height: height), device: device)
        // The preview pipeline decodes at a reduced size, so kernels see a small image.
        let previewHeight = Int((Double(height) * 2560 / Double(max(width, height))).rounded())
        let preview = try upload(TestScene.hazyLandscape.image(width: width >= height ? 2560 : previewHeight,
                                                               height: width >= height ? previewHeight : 2560),
                                 device: device)

        // How long compiling the Metal source and both pipelines takes, alone.
        let compileStart = ContinuousClock.now
        try RuntimeKernels.compile(on: device)
        let compile = ContinuousClock.now - compileStart
        print("Runtime compile of the Metal source and two pipelines: \(format(compile))")

        let cases: [(String, (CIImage) throws -> CIImage)] = [
            ("source only", { $0 }),
            ("gain, runtime kernel", { try RuntimeKernels.exposureGain($0, ev: 0.5) }),
            ("gain, CIExposureAdjust", { image in
                let filter = CIFilter.exposureAdjust()
                filter.inputImage = image
                filter.ev = 0.5
                return filter.outputImage!
            }),
            ("blur, runtime kernel", { try RuntimeKernels.gaussianBlur($0, sigma: sigma) }),
            ("blur, CIGaussianBlur", { image in
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = image.clampedToExtent()
                filter.radius = Float(sigma)
                return filter.outputImage!.cropped(to: image.extent)
            }),
        ]
        var report: [String: any Sendable] = ["compileSeconds": seconds(compile), "width": width, "height": height,
                                              "sigma": sigma, "device": device.name]
        for (sizeName, input) in [("preview", preview), ("full", source)] {
            print("\n\(sizeName.capitalized) size: \(Int(input.extent.width)) × \(Int(input.extent.height))")
            for (name, make) in cases {
                let image = try make(input)
                var times: [Duration] = []
                for _ in 0..<(runs + 1) {
                    times.append(try render(image, engine: engine, device: device))
                }
                let first = times.removeFirst()
                let median = times.sorted()[times.count / 2]
                print("  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) first \(format(first)), "
                      + "then median \(format(median))")
                report["\(sizeName).\(name)"] = ["firstSeconds": seconds(first), "medianSeconds": seconds(median)]
            }
        }
        return report
    }

    /// The scene as a GPU texture in the working space (32-bit float).
    static func upload(_ scene: LinearImage, device: any MTLDevice) throws -> CIImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: scene.width,
                                                                  height: scene.height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw BenchError("no texture") }
        scene.pixels.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, scene.width, scene.height), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: scene.width * 16)
        }
        // Texture rows run top down; Core Image's y runs up.
        guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: RenderEngine.workingColorSpace]) else {
            throw BenchError("no image from texture")
        }
        return image.oriented(.downMirrored)
    }

    /// Renders into a new half-float texture and waits for the GPU.
    static func render(_ image: CIImage, engine: RenderEngine, device: any MTLDevice) throws -> Duration {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw BenchError("no texture") }
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: nil)
        let start = ContinuousClock.now
        try engine.withContext { context in
            _ = try context.startTask(toRender: image.transformed(by: CGAffineTransform(
                translationX: -image.extent.minX, y: -image.extent.minY)), to: destination).waitUntilCompleted()
        }
        return ContinuousClock.now - start
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func format(_ duration: Duration) -> String {
        String(format: "%.1f ms", seconds(duration) * 1000)
    }
}
