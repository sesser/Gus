import CoreImage
import Foundation

/// A small image held as 32-bit floats, four per pixel (red, green, blue,
/// alpha), rows from the top: what the merge measures on before it renders
/// at full resolution (alignment, exposure, ghosts, tone statistics). Values
/// are linear light in the working space.
public struct MergeBitmap: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// `width * height * 4` values.
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var count: Int { width * height }

    @inline(__always)
    public func rgb(_ index: Int) -> SIMD3<Float> {
        SIMD3(pixels[index * 4], pixels[index * 4 + 1], pixels[index * 4 + 2])
    }

    @inline(__always)
    public func rgb(x: Int, y: Int) -> SIMD3<Float> { rgb(y * width + x) }

    /// Luminance of a linear Rec. 2020 color.
    @inline(__always)
    public static func luminance(_ rgb: SIMD3<Float>) -> Float {
        rgb.x * 0.2627 + rgb.y * 0.6780 + rgb.z * 0.0593
    }

    /// Renders `image` (its extent, or `bounds`) into floats in the working
    /// space, untouched by any color conversion. Outside the image is transparent.
    public static func render(_ image: CIImage, context: CIContext, bounds: CGRect? = nil) -> MergeBitmap? {
        let extent = (bounds ?? image.extent).integral
        guard !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return nil }
        let width = Int(extent.width), height = Int(extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 16, bounds: extent,
                           format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
        }
        return MergeBitmap(width: width, height: height, pixels: pixels)
    }

    /// The bitmap as a Core Image image in the working space, at the origin
    /// (rows from the top become Core Image's rows from the bottom).
    public func ciImage() -> CIImage {
        let data = pixels.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                       format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
    }
}

/// A one-channel float plane, rows from the top: masks and maps the merge
/// measures at a reduced size.
public struct MergePlane: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height)
        self.width = width
        self.height = height
        self.values = values
    }

    public init(width: Int, height: Int, fill: Float = 0) {
        self.init(width: width, height: height, values: [Float](repeating: fill, count: width * height))
    }

    @inline(__always)
    public subscript(x: Int, y: Int) -> Float {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }

    /// The plane as a gray Core Image image (the value in red, green and
    /// blue, alpha 1) at the origin, untouched by color conversion.
    public func ciImage() -> CIImage {
        var rgba = [Float](repeating: 1, count: width * height * 4)
        for index in 0..<(width * height) {
            let value = values[index]
            rgba[index * 4] = value
            rgba[index * 4 + 1] = value
            rgba[index * 4 + 2] = value
        }
        let data = rgba.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                       format: .RGBAf, colorSpace: nil)
    }

    /// Box mean over a square of side `2 * radius + 1`, edges clamped
    /// (summed-area table, so any radius costs the same).
    public func boxMean(radius: Int) -> MergePlane {
        guard radius > 0 else { return self }
        let w = width, h = height
        var table = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row = 0.0
            for x in 0..<w {
                row += Double(values[y * w + x])
                table[(y + 1) * (w + 1) + x + 1] = table[y * (w + 1) + x + 1] + row
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - radius), y1 = min(h - 1, y + radius)
            for x in 0..<w {
                let x0 = max(0, x - radius), x1 = min(w - 1, x + radius)
                let sum = table[(y1 + 1) * (w + 1) + x1 + 1] - table[y0 * (w + 1) + x1 + 1]
                    - table[(y1 + 1) * (w + 1) + x0] + table[y0 * (w + 1) + x0]
                out[y * w + x] = Float(sum / Double((y1 - y0 + 1) * (x1 - x0 + 1)))
            }
        }
        return MergePlane(width: w, height: h, values: out)
    }

    /// Each value the largest within a square of side `2 * radius + 1`.
    public func dilated(radius: Int) -> MergePlane {
        guard radius > 0 else { return self }
        let w = width, h = height
        var horizontal = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var m: Float = -.infinity
                for k in max(0, x - radius)...min(w - 1, x + radius) { m = max(m, values[y * w + k]) }
                horizontal[y * w + x] = m
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var m: Float = -.infinity
                for k in max(0, y - radius)...min(h - 1, y + radius) { m = max(m, horizontal[k * w + x]) }
                out[y * w + x] = m
            }
        }
        return MergePlane(width: w, height: h, values: out)
    }
}
