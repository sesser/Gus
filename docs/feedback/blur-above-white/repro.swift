// Exploratory (to be trimmed): which Core Image graph over values above 1.0
// renders differently depending on how the render is split?
//
// Run: swift repro.swift
// Needs only Core Image and Metal.

import CoreImage
import Foundation
import Metal

let width = 640
let height = 480
let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
let context = CIContext(mtlDevice: device, options: [
    .workingColorSpace: space,
    .workingFormat: CIFormat.RGBAh,
    .cacheIntermediates: false,
])

// Smooth shading from 0.2 to 1.0 with fine stripes, and bright soft discs
// reaching about 3.0 in the middle and at the bottom-left corner, as float
// RGBA in extended linear Rec. 2020 (rows top to bottom).
var pixels = [Float](repeating: 1, count: width * height * 4)
for y in 0..<height {
    for x in 0..<width {
        func disc(_ cx: Float, _ cy: Float, _ radius: Float) -> Float {
            let dx = Float(x) - cx, dy = Float(y) - cy
            let t = max(0, 1 - (dx * dx + dy * dy).squareRoot() / radius)
            return t * t * (3 - 2 * t)
        }
        let stripes = 0.1 * sin(Float(x) * 0.7) * sin(Float(y) * 0.5)
        let value = 0.2 + 0.8 * Float(x) / Float(width) + stripes
            + 2.4 * disc(200, 240, 90) + 2.4 * disc(40, 460, 120)
        let i = (y * width + x) * 4
        pixels[i] = value
        pixels[i + 1] = value * 0.9
        pixels[i + 2] = value * 0.8
    }
}
let source = CIImage(bitmapData: pixels.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
                     size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
let extent = source.extent

func render(_ image: CIImage, _ bounds: CGRect = extent) -> [Float] {
    let w = Int(bounds.width), h = Int(bounds.height)
    var out = [Float](repeating: 0, count: w * h * 4)
    out.withUnsafeMutableBytes {
        context.render(image, toBitmap: $0.baseAddress!, rowBytes: w * 16, bounds: bounds, format: .RGBAf,
                       colorSpace: space)
    }
    return out
}

/// `image` rendered as four tiles (a 2 × 2 split) and put back together.
func renderTiled(_ image: CIImage) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    let halfW = width / 2, halfH = height / 2
    for ty in 0..<2 {
        for tx in 0..<2 {
            // Core Image's y goes up; bitmap rows go down.
            let bounds = CGRect(x: tx * halfW, y: (1 - ty) * halfH, width: halfW, height: halfH)
            let tile = render(image, bounds)
            for row in 0..<halfH {
                for column in 0..<halfW {
                    let from = (row * halfW + column) * 4
                    let to = ((ty * halfH + row) * width + tx * halfW + column) * 4
                    out.replaceSubrange(to..<(to + 4), with: tile[from..<(from + 4)])
                }
            }
        }
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

func describe(_ name: String, _ a: [Float], _ b: [Float]) -> Float {
    let (difference, index) = largestDifference(a, b)
    let p = index / 4
    print("  \(name): largest difference \(difference) at (\(p % width), \(p / width)): \(a[index]) against \(b[index])")
    return difference
}

/// The same pixels rendered to half float first.
func preRendered(_ image: CIImage) -> CIImage {
    CIImage(cgImage: context.createCGImage(image, from: extent, format: .RGBAh, colorSpace: space)!)
}

func encoded(_ image: CIImage) -> CIImage {
    image.clampedToExtent().applyingFilter("CILinearToSRGBToneCurve")
}

func unsharp(_ image: CIImage) -> CIImage {
    encoded(image).applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 7.68, kCIInputIntensityKey: 0.18])
        .cropped(to: extent)
}

func guide(_ image: CIImage) -> CIImage {
    image
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2627, y: 0.6780, z: 0.0593, w: 0),
            "inputGVector": CIVector(x: 0.2627, y: 0.6780, z: 0.0593, w: 0),
            "inputBVector": CIVector(x: 0.2627, y: 0.6780, z: 0.0593, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.25])
        .cropped(to: extent)
}

func reduced(_ guide: CIImage) -> CIImage {
    guide.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 256.0 / 640, kCIInputAspectRatioKey: 1])
}

func upsampled(_ guide: CIImage, _ small: CIImage) -> CIImage {
    guide.applyingFilter("CIEdgePreserveUpsampleFilter", parameters: [
        "inputSmallImage": small, "inputSpatialSigma": 3, "inputLumaSigma": 0.12,
    ])
}

/// `image` rendered over its extent, against the same image clamped to its
/// extent and rendered 32 pixels wider on every side (inner part compared).
func alongsideMargin(_ image: CIImage) -> [Float] {
    let wide = extent.insetBy(dx: -32, dy: -32)
    let all = render(image.clampedToExtent().cropped(to: wide), wide)
    var out = [Float](repeating: 0, count: width * height * 4)
    let wideWidth = Int(wide.width)
    for row in 0..<height {
        let from = ((row + 32) * wideWidth + 32) * 4
        out.replaceSubrange((row * width * 4)..<((row + 1) * width * 4), with: all[from..<(from + width * 4)])
    }
    return out
}

func blurred(_ image: CIImage) -> CIImage {
    image.clampedToExtent().applyingGaussianBlur(sigma: 7.68).cropped(to: extent)
}

print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(device.name)")
var worst: Float = 0
for (label, input) in [("bright (to 4.2)", source.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.5])),
                       ("SDR (to 0.85)", source.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -2.3]))] {
    let g = guide(input)
    let graphs: [(String, CIImage)] = [
        ("guide only", g),
        ("Lanczos small image", reduced(g)),
        ("upsample, both inputs lazy", upsampled(g, reduced(g))),
        ("upsample, small image pre-rendered", upsampled(g, CIImage(cgImage: context.createCGImage(reduced(g),
            from: reduced(g).extent.integral, format: .RGBAh, colorSpace: space)!).transformed(by:
            CGAffineTransform(translationX: reduced(g).extent.integral.minX, y: reduced(g).extent.integral.minY)))),
        ("upsample, guide pre-rendered", upsampled(preRendered(g), reduced(g))),
    ]
    print("\(label), brightest input \(render(input).max() ?? 0)")
    for (name, graph) in graphs {
        print(" \(name):")
        let whole = graph.extent == extent ? render(graph) : nil
        if let whole {
            worst = max(worst, describe("alone against clamped and rendered wider", whole, alongsideMargin(graph)))
            let half = preRendered(graph)
            _ = describe("input: lazy against pre-rendered", whole, render(half))
            worst = max(worst, describe("CIGaussianBlur: lazy against pre-rendered", render(blurred(graph)),
                                        render(blurred(half))))
            worst = max(worst, describe("CIUnsharpMask: lazy against pre-rendered", render(unsharp(graph)),
                                        render(unsharp(half))))
        }
    }
}
print(worst > 0.005 ? "REPRODUCED (largest \(worst))" : "not reproduced (largest \(worst))")
