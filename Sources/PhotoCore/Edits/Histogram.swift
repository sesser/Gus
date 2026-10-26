import CoreGraphics
import Foundation

/// 256-bin counts per channel of a rendered (display-encoded) image.
public struct Histogram: Sendable, Hashable {
    public static let binCount = 256

    public var red: [UInt32]
    public var green: [UInt32]
    public var blue: [UInt32]
    public var luminance: [UInt32]

    public init(red: [UInt32], green: [UInt32], blue: [UInt32], luminance: [UInt32]) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
    }

    /// Counts the pixels of `image`, reduced so its long edge is at most
    /// `sampleSize` (drawn into an 8-bit Display P3 bitmap).
    public init?(image: CGImage, sampleSize: Int = 256) {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Double(sampleSize) / Double(longest))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: RenderEngine.outputColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var red = [UInt32](repeating: 0, count: Self.binCount)
        var green = red
        var blue = red
        var luminance = red
        for i in 0..<(width * height) {
            let r = Int(pixels[i * 4])
            let g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2])
            red[r] += 1
            green[g] += 1
            blue[b] += 1
            luminance[(r * 54 + g * 183 + b * 19) >> 8] += 1
        }
        self.init(red: red, green: green, blue: blue, luminance: luminance)
    }
}
