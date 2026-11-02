// CIEdgePreserveUpsampleFilter's output at the image's edge depends on the
// region rendered: the same image rendered over its extent, and clamped to
// its extent and rendered 32 pixels wider on every side, differ at the
// corner on macOS 26. On macOS 15 and 27 they are identical.
//
// Run: swift repro.swift
// Needs only Core Image and Metal. Exits 1 when the two renders differ.

import CoreImage
import Foundation
import Metal

let width = 640
let height = 480
let margin = 32
let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
let context = CIContext(mtlDevice: device, options: [
    .workingColorSpace: space,
    .workingFormat: CIFormat.RGBAh,
])

// A grey ramp from 0.2 to 0.6 with fine stripes, as float RGBA.
var pixels = [Float](repeating: 1, count: width * height * 4)
for y in 0..<height {
    for x in 0..<width {
        let value = 0.2 + 0.4 * Float(x) / Float(width) + 0.05 * sin(Float(x) * 0.7) * sin(Float(y) * 0.5)
        let i = (y * width + x) * 4
        pixels[i] = value
        pixels[i + 1] = value
        pixels[i + 2] = value
    }
}
let guide = CIImage(bitmapData: pixels.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
                    size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
let extent = guide.extent

// The guide reduced to 256 pixels wide, then upsampled along the guide's edges.
let small = guide.applyingFilter("CILanczosScaleTransform", parameters: [
    kCIInputScaleKey: 256.0 / Double(width), kCIInputAspectRatioKey: 1,
])
let upsampled = guide.applyingFilter("CIEdgePreserveUpsampleFilter", parameters: [
    "inputSmallImage": small, "inputSpatialSigma": 3, "inputLumaSigma": 0.12,
])

func render(_ image: CIImage, _ bounds: CGRect) -> [Float] {
    let w = Int(bounds.width), h = Int(bounds.height)
    var out = [Float](repeating: 0, count: w * h * 4)
    out.withUnsafeMutableBytes {
        context.render(image, toBitmap: $0.baseAddress!, rowBytes: w * 16, bounds: bounds, format: .RGBAf,
                       colorSpace: space)
    }
    return out
}

// A: the filter's output over its own extent.
let alone = render(upsampled, extent)
// B: the same output clamped to that extent and rendered wider, as a blur or
// any filter that reads past the edge asks for it; only the part inside the
// extent is compared.
let wide = extent.insetBy(dx: -CGFloat(margin), dy: -CGFloat(margin))
let widened = render(upsampled.clampedToExtent().cropped(to: wide), wide)
let wideWidth = width + 2 * margin

var worst: Float = 0
var worstAt = (x: 0, y: 0)
for y in 0..<height {
    for x in 0..<width {
        for channel in 0..<3 {
            let a = alone[(y * width + x) * 4 + channel]
            let b = widened[((y + margin) * wideWidth + x + margin) * 4 + channel]
            if abs(a - b) > worst { (worst, worstAt) = (abs(a - b), (x, y)) }
        }
    }
}

print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(device.name)")
print("Largest difference inside the extent: \(worst) at column \(worstAt.x), row \(worstAt.y) from the top")
if worst > 0 {
    let i = (worstAt.y * width + worstAt.x) * 4
    let j = ((worstAt.y + margin) * wideWidth + worstAt.x + margin) * 4
    print("  rendered over its extent: \(alone[i])")
    print("  clamped, rendered wider:  \(widened[j])")
}
// Both renders compute the same pixels from the same inputs in the same
// context, so they should be identical (as on macOS 15 and 27).
print(worst > 0 ? "REPRODUCED" : "not reproduced")
exit(worst > 0 ? 1 : 0)
