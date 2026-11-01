import CoreGraphics
import CoreImage
import Foundation
import PhotoCore

/// An image as float RGBA in the pipeline's working space (extended linear
/// Rec. 2020), rows top to bottom. What golden-image tests and CPU references
/// start from: these values reach the renderer unchanged.
public struct LinearImage: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// `width × height × 4` values: red, green, blue, alpha.
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The image in the working space. Core Image does not convert it, since
    /// it is tagged with the working color space itself.
    public var ciImage: CIImage {
        let data = pixels.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                       format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
    }

    /// The pixel at column `x` and row `y` (from the top).
    public subscript(x: Int, y: Int) -> SIMD4<Float> {
        let i = (y * width + x) * 4
        return SIMD4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }
}

/// Deterministic synthetic scenes for golden-image and reference tests.
///
/// Colors are chosen in the renderer's perceptual encoding (Rec. 2020
/// primaries with the sRGB transfer curve, `AdjustmentRenderer.perceptualSpace`),
/// so ramps are spaced the way tones are seen, then stored as linear values.
/// Anything random uses `SplitMix64` with a fixed seed. Golden tests use the
/// default size; other sizes (for example odd ones, to check tiling) draw the
/// same scene scaled.
public enum TestScene: String, CaseIterable, Sendable {
    /// Neutral steps from black to white over the top three quarters, and a
    /// linear ramp from 0 to 4 (two stops over white) in the bottom quarter.
    case grayRamp
    /// Every hue across the width; down the top half a saturated color from
    /// bright to darker, down the bottom half the saturation fades to grey.
    case hueRamp
    /// A 6 × 4 chart of fixed colors: neutrals, skin tones, foliage, sky,
    /// primaries and secondaries.
    case patchChart
    /// Sky, hills and a textured foreground seen through a veil that thins
    /// toward the bottom (the haze model I = J·t + A·(1 − t)).
    case hazyLandscape
    /// Step edges, a slanted edge, line pairs of 1, 2 and 3 pixels and a star
    /// of 24 sectors, dark grey on light grey.
    case edgeTarget

    public static let defaultWidth = 256
    public static let defaultHeight = 192

    public func image(width: Int = TestScene.defaultWidth, height: Int = TestScene.defaultHeight) -> LinearImage {
        switch self {
        case .grayRamp: Self.grayRamp(width, height)
        case .hueRamp: Self.hueRamp(width, height)
        case .patchChart: Self.patchChart(width, height)
        case .hazyLandscape: Self.hazyLandscape(width, height)
        case .edgeTarget: Self.edgeTarget(width, height)
        }
    }

    // MARK: Scenes

    private static func grayRamp(_ width: Int, _ height: Int) -> LinearImage {
        let split = height * 3 / 4
        return fill(width, height) { x, y in
            let t = width > 1 ? Double(x) / Double(width - 1) : 0
            if y < split {
                return SIMD3(repeating: decode(t))
            }
            return SIMD3(repeating: t * 4)
        }
    }

    private static func hueRamp(_ width: Int, _ height: Int) -> LinearImage {
        fill(width, height) { x, y in
            let hue = Double(x) / Double(width)
            let t = height > 1 ? Double(y) / Double(height - 1) : 0
            let (saturation, value) = t < 0.5 ? (0.9, 1 - t * 0.9) : (0.9 * (1 - (t - 0.5) * 2), 0.75)
            return decode(hsv(hue, saturation, value))
        }
    }

    /// Our own chart, in the perceptual encoding.
    static let patches: [SIMD3<Double>] = [
        // Neutrals.
        SIMD3(0.05, 0.05, 0.05), SIMD3(0.20, 0.20, 0.20), SIMD3(0.35, 0.35, 0.35),
        SIMD3(0.50, 0.50, 0.50), SIMD3(0.70, 0.70, 0.70), SIMD3(0.92, 0.92, 0.92),
        // Skin, foliage and sky.
        SIMD3(0.42, 0.30, 0.24), SIMD3(0.72, 0.56, 0.47), SIMD3(0.88, 0.74, 0.64),
        SIMD3(0.30, 0.38, 0.20), SIMD3(0.38, 0.52, 0.66), SIMD3(0.55, 0.70, 0.86),
        // Primaries and secondaries, strong.
        SIMD3(0.75, 0.12, 0.12), SIMD3(0.15, 0.62, 0.20), SIMD3(0.14, 0.22, 0.70),
        SIMD3(0.12, 0.65, 0.68), SIMD3(0.70, 0.18, 0.62), SIMD3(0.88, 0.80, 0.14),
        // Softer and in between.
        SIMD3(0.85, 0.50, 0.15), SIMD3(0.45, 0.30, 0.60), SIMD3(0.60, 0.75, 0.30),
        SIMD3(0.80, 0.45, 0.55), SIMD3(0.30, 0.55, 0.50), SIMD3(0.65, 0.58, 0.40),
    ]

    private static func patchChart(_ width: Int, _ height: Int) -> LinearImage {
        let border = decode(SIMD3(repeating: 0.12))
        // A dark border two pixels wide around each patch (at the default size).
        let edge = max(1, 2 * width / defaultWidth)
        return fill(width, height) { x, y in
            let column = min(x * 6 / width, 5)
            let row = min(y * 4 / height, 3)
            let left = column * width / 6, right = (column + 1) * width / 6 - 1
            let top = row * height / 4, bottom = (row + 1) * height / 4 - 1
            if x - left < edge || right - x < edge || y - top < edge || bottom - y < edge {
                return border
            }
            return decode(patches[row * 6 + column])
        }
    }

    private static func hazyLandscape(_ width: Int, _ height: Int) -> LinearImage {
        // Fine texture for the foreground: fixed-seed noise on a coarse grid,
        // so every size shows the same pattern relative to the frame.
        var random = SplitMix64(seed: 0x5EED_0001)
        let grid = 64
        let noise = (0..<(grid * grid)).map { _ in Double(random.next() % 10_000) / 10_000 - 0.5 }
        let airlight = decode(SIMD3(0.82, 0.85, 0.88))
        return fill(width, height) { x, y in
            let u = Double(x) / Double(width)
            let v = Double(y) / Double(height)
            let horizon = 0.38 + 0.04 * sin(u * 9)
            let hills = 0.52 + 0.06 * sin(u * 5 + 1) + 0.03 * sin(u * 17)
            let clear: SIMD3<Double>
            let distance: Double
            if v < horizon {
                // Sky, darker blue at the top.
                clear = decode(SIMD3(0.35, 0.55, 0.85) * (0.75 + 0.25 * v / horizon))
                distance = 1
            } else if v < hills {
                clear = decode(SIMD3(0.28, 0.36, 0.30))
                distance = 0.8
            } else {
                let texture = noise[min(Int(v * Double(grid)), grid - 1) * grid + min(Int(u * Double(grid)), grid - 1)]
                clear = decode(SIMD3(0.30, 0.42, 0.16) * (1 + 0.35 * texture) * (1.1 - 0.4 * (v - hills)))
                distance = 0.55 - 0.45 * (v - hills) / (1 - hills)
            }
            // Transmission falls with distance.
            let transmission = exp(-1.6 * distance)
            return clear * transmission + airlight * (1 - transmission)
        }
    }

    private static func edgeTarget(_ width: Int, _ height: Int) -> LinearImage {
        let dark = decode(SIMD3(repeating: 0.15))
        let light = decode(SIMD3(repeating: 0.85))
        let scale = Double(width) / Double(defaultWidth)
        let slant = tan(5 * Double.pi / 180)
        return fill(width, height, supersample: 4) { u, v in
            // Coordinates in pixels of the default size.
            let x = u / scale
            let y = v / scale
            let top = Double(defaultHeight) * 0.5
            if y < top {
                if x < 64 {
                    // A vertical step edge over a horizontal one.
                    return y < 48 ? (x < 32 ? dark : light) : (y < 72 ? dark : light)
                }
                if x < 128 {
                    // A slanted edge, 5° from vertical.
                    return x - 96 < (y - 48) * slant ? dark : light
                }
                // Line pairs of 1, 2 and 3 pixels.
                let period = x < 170 ? 2.0 : (x < 212 ? 4.0 : 6.0)
                return (x - 128).truncatingRemainder(dividingBy: period) < period / 2 ? dark : light
            }
            // A star of 24 sectors.
            let dx = x - Double(defaultWidth) / 2
            let dy = y - (top + Double(defaultHeight) * 0.25)
            guard dx * dx + dy * dy < 44 * 44 else { return light }
            let angle = atan2(dy, dx) + Double.pi
            return Int(angle / (2 * Double.pi) * 24) % 2 == 0 ? dark : light
        }
    }

    // MARK: Helpers

    /// Builds an opaque image from linear colors. With `supersample` > 1,
    /// `color` gets continuous coordinates and each pixel averages a grid of samples.
    private static func fill(_ width: Int, _ height: Int, supersample: Int = 1,
                             color: (Double, Double) -> SIMD3<Double>) -> LinearImage {
        var pixels = [Float](repeating: 1, count: width * height * 4)
        let n = Double(supersample * supersample)
        for y in 0..<height {
            for x in 0..<width {
                var sum = SIMD3<Double>.zero
                if supersample == 1 {
                    sum = color(Double(x), Double(y))
                } else {
                    for sy in 0..<supersample {
                        for sx in 0..<supersample {
                            sum += color(Double(x) + (Double(sx) + 0.5) / Double(supersample),
                                         Double(y) + (Double(sy) + 0.5) / Double(supersample))
                        }
                    }
                    sum /= n
                }
                let i = (y * width + x) * 4
                pixels[i] = Float(sum.x)
                pixels[i + 1] = Float(sum.y)
                pixels[i + 2] = Float(sum.z)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    private static func fill(_ width: Int, _ height: Int, color: (Int, Int) -> SIMD3<Double>) -> LinearImage {
        fill(width, height, supersample: 1) { color(Int($0), Int($1)) }
    }

    /// The sRGB transfer curve, encoded to linear.
    public static func decode(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func decode(_ color: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(decode(color.x), decode(color.y), decode(color.z))
    }

    static func hsv(_ hue: Double, _ saturation: Double, _ value: Double) -> SIMD3<Double> {
        let h = hue * 6
        let c = value * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return SIMD3(r + m, g + m, b + m)
    }
}
