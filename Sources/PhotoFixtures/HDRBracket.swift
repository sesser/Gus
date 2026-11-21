import CoreGraphics
import Foundation
import ImageIO
import simd
import PhotoCore
import UniformTypeIdentifiers

/// A synthetic scene with a known range of light, photographed as a bracket
/// (issue #150): each frame is the scene's radiance times its exposure,
/// clipped at white, optionally moved (a shift and a rotation about the
/// center, as a hand-held camera moves) and with an object that is only in
/// one frame. The frames are sampled from the scene itself at their own
/// positions, so where each frame's pixels come from is known exactly
/// (`homographyToReference`).
///
/// The scene, in linear Rec. 2020 relative to the 0 EV frame's white (1):
/// a dim interior wall (0.004 to 0.03) with a row of shadow steps (0.0010 to
/// 0.0022), mid-tone shapes (0.05 to 0.6), and a window (1.2 to 3.6) with
/// highlight steps (1.6 to 3.4) and mullions. At -2, 0 and +2 EV no single
/// frame holds both rows of steps within 8 bits: the -2 EV frame crushes the
/// shadow steps to one code, the others clip the highlight steps.
public enum HDRBracket {
    /// One frame of a bracket.
    public struct Frame: Sendable {
        /// Exposure relative to the reference (0 EV), in stops.
        public var ev: Double
        /// Shift in pixels (x right, y down) and rotation in degrees
        /// (clockwise on screen) of what the frame sees, about the center.
        public var shift: SIMD2<Double>
        public var rotationDegrees: Double
        /// Draws the moving object into this frame.
        public var hasMovingObject: Bool

        public init(ev: Double, shift: SIMD2<Double> = .zero, rotationDegrees: Double = 0,
                    hasMovingObject: Bool = false) {
            self.ev = ev
            self.shift = shift
            self.rotationDegrees = rotationDegrees
            self.hasMovingObject = hasMovingObject
        }
    }

    /// The shadow and highlight steps' radiances, left to right.
    public static let shadowSteps: [Double] = [0.0010, 0.0013, 0.0017, 0.0022]
    public static let highlightSteps: [Double] = [1.6, 2.0, 2.6, 3.4]
    /// Darkest and brightest radiance in the scene.
    public static let radianceRange: ClosedRange<Double> = 0.0010...3.6

    /// Where the steps are, as unit rectangles of the frame (x, y from the top left).
    public static func shadowStepRect(_ index: Int) -> CGRect {
        CGRect(x: 0.06 + Double(index) * 0.07, y: 0.72, width: 0.06, height: 0.14)
    }

    public static func highlightStepRect(_ index: Int) -> CGRect {
        CGRect(x: 0.60 + Double(index) * 0.07, y: 0.36, width: 0.06, height: 0.12)
    }

    /// The moving object: a disc at this unit center and radius (of the width).
    public static let movingObjectCenter = SIMD2(0.30, 0.40)
    public static let movingObjectRadius = 0.07
    public static let movingObjectRadiance = SIMD3(0.45, 0.12, 0.08)

    /// Radiance of the scene at unit coordinates (x right, y down; 0 to 1 over
    /// the reference frame), linear Rec. 2020.
    public static func radiance(u: Double, v: Double, aspect: Double) -> SIMD3<Double> {
        // Shadow steps.
        for (index, value) in shadowSteps.enumerated() where shadowStepRect(index).contains(CGPoint(x: u, y: v)) {
            return SIMD3(repeating: value)
        }
        for (index, value) in highlightSteps.enumerated() where highlightStepRect(index).contains(CGPoint(x: u, y: v)) {
            return SIMD3(value, value, value * 0.96)
        }
        // The window, with mullions.
        if u > 0.55, u < 0.92, v > 0.10, v < 0.56 {
            let mullionX = abs(u - 0.735) < 0.008
            let mullionY = abs(v - 0.30) < 0.008
            if mullionX || mullionY { return SIMD3(0.05, 0.045, 0.04) }
            let sky = 1.2 + 2.4 * (1 - (v - 0.10) / 0.46)
            let cloud = 0.25 * sin(u * 37 + 2 * sin(v * 23)) * sin(v * 29 + u * 11)
            return SIMD3(sky * (0.80 + cloud * 0.3), sky * (0.90 + cloud * 0.3), sky + cloud)
        }
        // Mid-tone shapes: a table, a vase, a frame on the wall.
        let dx = (u - 0.30) * aspect, dy = v - 0.62
        if dx * dx + dy * dy < 0.012 {
            return SIMD3(0.35, 0.30, 0.18) * (1 + 0.15 * sin(u * 120))
        }
        if u > 0.08, u < 0.45, v > 0.12, v < 0.30 {
            let inner = u > 0.10 && u < 0.43 && v > 0.14 && v < 0.28
            return inner ? SIMD3(0.12, 0.20, 0.30) * (1 + 0.3 * sin(u * 80) * sin(v * 60)) : SIMD3(0.55, 0.50, 0.40)
        }
        if v > 0.88 {
            // Floorboards.
            let board = Int(u * 14) % 2 == 0 ? 0.06 : 0.09
            return SIMD3(board, board * 0.8, board * 0.6) * (1 + 0.2 * sin(u * 300 + v * 40))
        }
        // The wall: dim, with a fine texture and a slow gradient.
        let texture = 1 + 0.35 * sin(u * 173 + 3 * sin(v * 41)) * sin(v * 151 + u * 7)
        let wall = (0.004 + 0.026 * u * (1 - v)) * texture
        return SIMD3(wall, wall * 0.95, wall * 0.85)
    }

    /// The frame as linear Rec. 2020 values, clipped at 1 (white), `width` by
    /// `height`, two by two samples a pixel. `noise` is the standard deviation
    /// of a Gaussian added to each value (0: none), drawn from `seed`.
    public static func image(_ frame: Frame, width: Int, height: Int, noise: Double = 0, seed: UInt64 = 1) -> LinearImage {
        let gain = pow(2, frame.ev)
        let aspect = Double(width) / Double(height)
        let center = SIMD2(Double(width) / 2, Double(height) / 2)
        let angle = frame.rotationDegrees * .pi / 180
        let (c, s) = (cos(angle), sin(angle))
        var random = SplitMix64(seed: seed)
        func gaussian() -> Double {
            let u = (Double(random.next() >> 11) + 0.5) / Double(1 << 53)
            let v = Double(random.next() >> 11) / Double(1 << 53)
            return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        }
        let objectCenter = movingObjectCenter * SIMD2(Double(width), Double(height))
        let objectRadius = movingObjectRadius * Double(width)
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var sum = SIMD3<Double>.zero
                for sy in 0..<2 {
                    for sx in 0..<2 {
                        let p = SIMD2(Double(x) + (Double(sx) + 0.5) / 2, Double(y) + (Double(sy) + 0.5) / 2)
                        let q = scenepoint(p, center: center, cos: c, sin: s, shift: frame.shift)
                        var value = radiance(u: q.x / Double(width), v: q.y / Double(height), aspect: aspect)
                        if frame.hasMovingObject, simd_distance(q, objectCenter) < objectRadius {
                            value = movingObjectRadiance
                        }
                        sum += value
                    }
                }
                var value = sum / 4 * gain
                if noise > 0 {
                    value += SIMD3(gaussian(), gaussian(), gaussian()) * noise
                }
                let i = (y * width + x) * 4
                pixels[i] = Float(min(max(value.x, 0), 1))
                pixels[i + 1] = Float(min(max(value.y, 0), 1))
                pixels[i + 2] = Float(min(max(value.z, 0), 1))
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// The scene radiance itself, unclipped, at the reference frame's pixels.
    public static func radianceImage(width: Int, height: Int) -> LinearImage {
        let aspect = Double(width) / Double(height)
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var sum = SIMD3<Double>.zero
                for sy in 0..<2 {
                    for sx in 0..<2 {
                        sum += radiance(u: (Double(x) + (Double(sx) + 0.5) / 2) / Double(width),
                                        v: (Double(y) + (Double(sy) + 0.5) / 2) / Double(height), aspect: aspect)
                    }
                }
                let i = (y * width + x) * 4
                pixels[i] = Float(sum.x / 4)
                pixels[i + 1] = Float(sum.y / 4)
                pixels[i + 2] = Float(sum.z / 4)
            }
        }
        return LinearImage(width: width, height: height, pixels: pixels)
    }

    /// The scene point a frame's pixel `p` (pixels, y down) sees.
    static func scenepoint(_ p: SIMD2<Double>, center: SIMD2<Double>, cos c: Double, sin s: Double,
                           shift: SIMD2<Double>) -> SIMD2<Double> {
        let d = p - center
        return center + SIMD2(c * d.x - s * d.y, s * d.x + c * d.y) + shift
    }

    /// Where a frame's pixel position (pixels, y down) lies in the reference
    /// frame: the movement the merge has to undo.
    public static func positionInReference(_ p: SIMD2<Double>, frame: Frame, width: Int, height: Int) -> SIMD2<Double> {
        let angle = frame.rotationDegrees * .pi / 180
        return scenepoint(p, center: SIMD2(Double(width) / 2, Double(height) / 2), cos: cos(angle), sin: sin(angle),
                          shift: frame.shift)
    }

    /// The color tags of a camera whose RGB is linear Rec. 2020 (XYZ D65 to Rec. 2020).
    public static let rec2020Color = SyntheticDNG.Color(matrix1: [
        1.7166512, -0.3556708, -0.2533663,
        -0.6666844, 1.6164812, 0.0157685,
        0.0176399, -0.0427706, 0.9421031,
    ])

    /// Base shutter time of the 0 EV frame, in seconds.
    public static let baseExposureTime = 1.0 / 60

    /// Writes a frame as a linear raw DNG (16 bits, white 65535) with its
    /// exposure in EXIF: ExposureTime from `ev`, and ExposureBiasValue `ev`
    /// unless `writesBias` is false. `date` is "yyyy:MM:dd HH:mm:ss".
    public static func writeDNG(_ image: LinearImage, frame: Frame, to url: URL, date: String,
                                writesBias: Bool = true) throws {
        let width = image.width & ~1, height = image.height & ~1
        var mosaic = Data(count: width * height * 6)
        mosaic.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width {
                    let pixel = image[x, y]
                    for c in 0..<3 {
                        samples[(y * width + x) * 3 + c] = UInt16((Double(pixel[c]) * 65535).rounded()).littleEndian
                    }
                }
            }
        }
        var options = SyntheticDNG.Options(width: width, height: height, seed: 1, dateTimeOriginal: date,
                                           iso: 200, color: rec2020Color, linearRaw: true)
        options.exposureTime = baseExposureTime * pow(2, frame.ev)
        options.exposureBias = writesBias ? frame.ev : nil
        options.fNumber = 8
        options.make = "Synthetic"
        options.model = "Bracket Camera"
        try SyntheticDNG.write(to: url, options: options, mosaic: mosaic)
    }

    /// Writes a frame as a JPEG (sRGB) with its exposure in EXIF.
    public static func writeJPEG(_ image: LinearImage, frame: Frame, to url: URL, date: String,
                                 writesBias: Bool = true, quality: Double = 0.95) throws {
        guard let cgImage = image.cgImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var exif = SyntheticImages.Exif(dateTimeOriginal: date, model: "Bracket Camera")
        exif.exposureTime = baseExposureTime * pow(2, frame.ev)
        exif.exposureBias = writesBias ? frame.ev : nil
        exif.fNumber = 8
        exif.iso = 200
        try SyntheticImages.write(cgImage, to: url, type: .jpeg, exif: exif, quality: quality)
    }
}
