// CIGaussianBlur over values above 1.0 gives a different result when its
// input is part of the same Core Image graph than when the same pixels are
// first rendered to a half-float image.
//
// Run: swift repro.swift
// Needs only Core Image and Metal. Prints the largest difference between the
// two renders and, at that pixel, a CPU Gaussian of the same input.

import CoreImage
import Foundation
import Metal

let width = 640
let height = 480
let sigma: Float = 7.68
let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
let context = CIContext(mtlDevice: device, options: [
    .workingColorSpace: space,
    .workingFormat: CIFormat.RGBAh,
    .cacheIntermediates: false,
])

// A smooth field from 0.1 to 0.5 with a bright soft disc reaching 2.0, as
// float RGBA in extended linear Rec. 2020.
var pixels = [Float](repeating: 1, count: width * height * 4)
for y in 0..<height {
    for x in 0..<width {
        let dx = Float(x - 200), dy = Float(y - 240)
        let disc = max(0, 1 - (dx * dx + dy * dy).squareRoot() / 90)
        let value = 0.1 + 0.4 * Float(x) / Float(width) + 1.9 * disc * disc * (3 - 2 * disc)
        let i = (y * width + x) * 4
        pixels[i] = value
        pixels[i + 1] = value * 0.9
        pixels[i + 2] = value * 0.8
    }
}
let source = CIImage(bitmapData: pixels.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
                     size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
let extent = source.extent

// The input as part of the graph: +0.5 EV, so the brightest value is about 2.8.
let inGraph = source.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.5])
// The same pixels rendered to half float first.
let rendered = context.createCGImage(inGraph, from: extent, format: .RGBAh, colorSpace: space)!
let preRendered = CIImage(cgImage: rendered)

func render(_ image: CIImage) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    out.withUnsafeMutableBytes {
        context.render(image, toBitmap: $0.baseAddress!, rowBytes: width * 16, bounds: extent, format: .RGBAf,
                       colorSpace: space)
    }
    return out
}

func largestDifference(_ a: [Float], _ b: [Float]) -> (difference: Float, index: Int) {
    var worst: Float = 0, at = 0
    for i in a.indices where i % 4 != 3 {
        let d = abs(a[i] - b[i])
        if d > worst { (worst, at) = (d, i) }
    }
    return (worst, at)
}

/// A Gaussian of `image` (float RGBA) at one sample, edges repeated.
func cpuGaussian(_ image: [Float], at index: Int) -> Float {
    let p = index / 4, channel = index % 4
    let cx = p % width, cy = p / width
    let reach = Int((sigma * 4).rounded(.up))
    var sum: Float = 0, weights: Float = 0
    for dy in -reach...reach {
        for dx in -reach...reach {
            let w = exp(-Float(dx * dx + dy * dy) / (2 * sigma * sigma))
            let x = min(max(cx + dx, 0), width - 1), y = min(max(cy + dy, 0), height - 1)
            sum += w * image[(y * width + x) * 4 + channel]
            weights += w
        }
    }
    return sum / weights
}

let version = ProcessInfo.processInfo.operatingSystemVersionString
print("macOS \(version), \(device.name)")

let inputs = (render(inGraph), render(preRendered))
let input = largestDifference(inputs.0, inputs.1)
let brightest = inputs.0.max() ?? 0
// Half float keeps 10 bits after the leading one: steps of 2^(exponent - 10).
let step = Float(sign: .plus, exponent: brightest.exponent - 10, significand: 1)
print("inputs: largest difference \(input.difference), brightest value \(brightest) "
      + "(one half-float step there: \(step))")

/// The perceptual encoding applied before the blur, as a clarity control does.
func encoded(_ image: CIImage) -> CIImage {
    image.clampedToExtent().applyingFilter("CILinearToSRGBToneCurve")
}

let variants: [(name: String, filter: (CIImage) -> CIImage, cpuInput: [Float]?)] = [
    ("CIGaussianBlur", { $0.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: extent) },
     inputs.1),
    ("CILinearToSRGBToneCurve then CIGaussianBlur",
     { encoded($0).applyingGaussianBlur(sigma: Double(sigma)).cropped(to: extent) }, nil),
    ("CILinearToSRGBToneCurve then CIUnsharpMask",
     { encoded($0).applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: sigma, kCIInputIntensityKey: 0.18])
         .cropped(to: extent) }, nil),
]

var reproduced = false
for variant in variants {
    let outputs = (render(variant.filter(inGraph)), render(variant.filter(preRendered)))
    let output = largestDifference(outputs.0, outputs.1)
    let p = output.index / 4
    print("\(variant.name) (sigma \(sigma)): largest difference \(output.difference) at (\(p % width), \(p / width)) "
          + "channel \(output.index % 4)")
    print("  input in the graph:  \(outputs.0[output.index])")
    print("  input pre-rendered:  \(outputs.1[output.index])")
    if let cpuInput = variant.cpuInput {
        print("  CPU Gaussian:        \(cpuGaussian(cpuInput, at: output.index))")
    }
    // The inputs differ by at most one half-float step; a blur, a weighted
    // average, cannot enlarge that. 0.02 is ten times it.
    reproduced = reproduced || output.difference > 0.02
}
print(reproduced ? "REPRODUCED: a blur's result depends on whether its input was pre-rendered"
                 : "not reproduced: the blurs agree as closely as their inputs")
exit(reproduced ? 1 : 0)
