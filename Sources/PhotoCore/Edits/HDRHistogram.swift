import CoreImage
import Foundation

/// The histogram of a gain-map photo's whole HDR version (issue #282, R10,
/// design §7): the same on every display, so it is counted from the HDR
/// version at the file's full brightening, never the picture fitted to a
/// display.
///
/// 255 bins of equal width: the first 153 hold 0 to SDR white on the
/// display-encoded scale today's histogram uses (the sRGB curve of Display
/// P3), the last 102 hold SDR white to 3 stops above it (1× to 8×), linear
/// in stops. Exactly SDR white falls in the last SDR bin; anything past 3
/// stops in the last bin. The axis is fixed, never fitted to the file, the
/// edit or the display. Channels are counted from linear Display P3
/// relative to SDR white; luminance with Display P3's weights.
public struct HDRHistogram: Sendable, Hashable {
    public static let sdrBins = 153
    public static let hdrBins = 102
    public static let binCount = sdrBins + hdrBins
    /// Stops above SDR white the HDR part covers.
    public static let stops: Float = 3

    public var red: [UInt32]
    public var green: [UInt32]
    public var blue: [UInt32]
    public var luminance: [UInt32]
    /// The share of pixels whose luminance is above SDR white, 0 to 1.
    public var shareAboveWhite: Double

    public init(red: [UInt32], green: [UInt32], blue: [UInt32], luminance: [UInt32], shareAboveWhite: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
        self.shareAboveWhite = shareAboveWhite
    }

    /// The bin of a linear value relative to SDR white.
    public static func bin(_ value: Float) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        if value <= 1 {
            return min(sdrBins - 1, Int(encoded(value) * Float(sdrBins)))
        }
        let stopsAbove = log2(value)
        return sdrBins + min(hdrBins - 1, Int(stopsAbove / stops * Float(hdrBins)))
    }

    /// The sRGB transfer function (Display P3's), for the SDR part.
    static func encoded(_ linear: Float) -> Float {
        linear <= 0.003_130_8 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    /// Counts linear Display P3 pixels (RGBA float, alpha ignored).
    public init(linearPixels pixels: UnsafeBufferPointer<Float>, count: Int) {
        var red = [UInt32](repeating: 0, count: Self.binCount)
        var green = red, blue = red, luminance = red
        var above = 0
        for index in 0..<count {
            let r = pixels[index * 4], g = pixels[index * 4 + 1], b = pixels[index * 4 + 2]
            red[Self.bin(r)] += 1
            green[Self.bin(g)] += 1
            blue[Self.bin(b)] += 1
            let weighted: Float = 0.2290 * r + 0.6917 * g
            let y = weighted + 0.0793 * b
            luminance[Self.bin(y)] += 1
            if y > 1 { above += 1 }
        }
        self.init(red: red, green: green, blue: blue, luminance: luminance,
                  shareAboveWhite: count > 0 ? Double(above) / Double(count) : 0)
    }

    /// Counts `image` (in the working space), reduced so its long edge is at
    /// most `sampleSize`, rendered to linear Display P3 floats by `engine`.
    public init?(image: CIImage, engine: RenderEngine, sampleSize: Int = 256) {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        let reduced = image.scaledToFit(longEdge: sampleSize)
        let bounds = reduced.extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let rendered: Bool = engine.withContext { context in
            pixels.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return false }
                context.render(reduced, toBitmap: base, rowBytes: width * 16, bounds: bounds, format: .RGBAf,
                               colorSpace: RenderEngine.hdrColorSpace)
                return true
            }
        }
        guard rendered else { return nil }
        self = pixels.withUnsafeBufferPointer { HDRHistogram(linearPixels: $0, count: width * height) }
    }
}
