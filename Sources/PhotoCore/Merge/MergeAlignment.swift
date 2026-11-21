import CoreGraphics
import CoreImage
import Foundation
import Vision
import simd

/// Lines the frames of a merge up with its reference (PRD R9, A9), with
/// Vision's homographic image registration on reduced copies of the frames.
///
/// The frames differ in exposure, which a registration made on their pixel
/// values would take for a difference in content. Each frame is therefore
/// first turned into its luminance's ranks (histogram equalization): a
/// bracket of one scene gives nearly the same picture at every exposure, the
/// idea behind Ward's median threshold bitmaps (Ward 2003, "Fast, robust
/// image registration for compositing high dynamic range photographs from
/// hand-held exposures"), which take only the median rank. Vision is then
/// asked for the homography from each frame onto the reference.
///
/// A frame is refused (`Failure.misaligned`) when the homography is not a
/// small hand-held movement (`MergeLimits` bounds on shift, rotation, scale
/// and perspective) or when the frames still disagree after it (the
/// correlation of their ranks over the overlap is below
/// `MergeLimits.minimumAlignmentCorrelation`): a different scene.
public enum MergeAlignment {
    public enum Failure: Error, Equatable, Sendable {
        /// The frame at this index doesn't line up with the reference.
        case misaligned(frame: Int)
    }

    /// Maps a point of a frame (pixels, origin at the bottom left as Core
    /// Image has it) to the reference's: `p' = H p` in homogeneous
    /// coordinates. Identity for the reference itself.
    public struct Homography: Sendable, Equatable {
        public var matrix: simd_double3x3

        public static let identity = Homography(matrix: matrix_identity_double3x3)

        public init(matrix: simd_double3x3) {
            self.matrix = matrix
        }

        public func apply(_ point: SIMD2<Double>) -> SIMD2<Double> {
            let p = matrix * SIMD3(point.x, point.y, 1)
            return SIMD2(p.x / p.z, p.y / p.z)
        }

        /// The same movement on images `factor` times larger.
        public func scaled(by factor: Double) -> Homography {
            let s = simd_double3x3(diagonal: SIMD3(factor, factor, 1))
            let inverse = simd_double3x3(diagonal: SIMD3(1 / factor, 1 / factor, 1))
            return Homography(matrix: s * matrix * inverse)
        }

        public var inverse: Homography { Homography(matrix: matrix.inverse) }

        /// The rotation in degrees (from the upper 2 x 2 part), for limits and reports.
        public var rotationDegrees: Double {
            atan2(matrix[0][1] - matrix[1][0], matrix[0][0] + matrix[1][1]) * 180 / .pi
        }

        /// How far the center of a `size` image moves, in pixels.
        public func shift(of size: CGSize) -> Double {
            let center = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
            return simd_length(apply(center) - center)
        }

        /// The scale of the upper 2 x 2 part (square root of its determinant).
        public var scale: Double {
            sqrt(abs(matrix[0][0] * matrix[1][1] - matrix[1][0] * matrix[0][1]))
        }

        /// The perspective terms' effect across a `size` image: how far from 1
        /// the homogeneous coordinate gets at a corner.
        public func perspective(of size: CGSize) -> Double {
            let corner = matrix * SIMD3(Double(size.width), Double(size.height), 1)
            return abs(corner.z - 1)
        }
    }

    /// The homographies taking each frame onto `frames[reference]`, for frames
    /// given as reduced copies of one size. Throws `misaligned` naming the
    /// first frame that can't be lined up.
    public static func align(_ frames: [MergeBitmap], reference: Int) throws -> [Homography] {
        let ranks = frames.map(equalizedLuminance)
        guard let referenceImage = grayImage(ranks[reference]) else { throw Failure.misaligned(frame: reference) }
        var result: [Homography] = []
        for (index, plane) in ranks.enumerated() {
            try Task.checkCancellation()
            if index == reference {
                result.append(.identity)
                continue
            }
            guard let image = grayImage(plane),
                  let homography = register(image, onto: referenceImage, height: plane.height),
                  isHandHeld(homography, size: CGSize(width: plane.width, height: plane.height)),
                  correlation(plane, ranks[reference], homography: homography) >= MergeLimits.minimumAlignmentCorrelation
            else { throw Failure.misaligned(frame: index) }
            result.append(homography)
        }
        return result
    }

    /// Vision's homography from `floating` onto `reference`, in Core Image's
    /// coordinates: Vision's warp maps the floating image's pixels into the
    /// reference's in pixels with the origin at the bottom left, as Core
    /// Image has it (measured with the fixture's known movements, status.md
    /// "Spike 2").
    static func register(_ floating: CGImage, onto reference: CGImage, height: Int) -> Homography? {
        let request = VNHomographicImageRegistrationRequest(targetedCGImage: floating, options: [:])
        let handler = VNImageRequestHandler(cgImage: reference, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNImageHomographicAlignmentObservation else { return nil }
        let warp = observation.warpTransform
        // simd_float3x3 is column-major: columns[0] is the first column.
        let vision = simd_double3x3(columns: (
            SIMD3(Double(warp.columns.0.x), Double(warp.columns.0.y), Double(warp.columns.0.z)),
            SIMD3(Double(warp.columns.1.x), Double(warp.columns.1.y), Double(warp.columns.1.z)),
            SIMD3(Double(warp.columns.2.x), Double(warp.columns.2.y), Double(warp.columns.2.z))))
        var matrix = vision
        guard matrix[2][2] != 0, matrix.determinant.isFinite, matrix.determinant != 0 else { return nil }
        matrix = matrix * (1 / matrix[2][2])
        return Homography(matrix: matrix)
    }

    static func isHandHeld(_ homography: Homography, size: CGSize) -> Bool {
        let longEdge = Double(max(size.width, size.height))
        return homography.shift(of: size) <= MergeLimits.maximumShiftFraction * longEdge
            && abs(homography.rotationDegrees) <= MergeLimits.maximumRotationDegrees
            && abs(homography.scale - 1) <= MergeLimits.maximumScaleChange
            && homography.perspective(of: size) <= MergeLimits.maximumPerspective
    }

    /// Ranks of the luminance, 0 to 1: equal for frames of one scene at any exposure,
    /// except where a frame is clipped.
    static func equalizedLuminance(_ bitmap: MergeBitmap) -> MergePlane {
        let count = bitmap.count
        var luminance = [Float](repeating: 0, count: count)
        for index in 0..<count { luminance[index] = MergeBitmap.luminance(bitmap.rgb(index)) }
        let order = luminance.indices.sorted { luminance[$0] < luminance[$1] }
        var ranks = [Float](repeating: 0, count: count)
        // Equal values share their mean rank, so a clipped area stays one flat value.
        var start = 0
        while start < count {
            var end = start
            while end + 1 < count, luminance[order[end + 1]] == luminance[order[start]] { end += 1 }
            let rank = Float(start + end) / 2 / Float(max(1, count - 1))
            for k in start...end { ranks[order[k]] = rank }
            start = end + 1
        }
        return MergePlane(width: bitmap.width, height: bitmap.height, values: ranks)
    }

    static func grayImage(_ plane: MergePlane) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: plane.width * plane.height)
        for index in bytes.indices {
            bytes[index] = UInt8(clamping: Int((plane.values[index] * 255).rounded()))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: plane.width, height: plane.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: plane.width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Pearson correlation of the frame's ranks, moved by `homography`, with
    /// the reference's, over the pixels both cover (nearest pixel).
    static func correlation(_ frame: MergePlane, _ reference: MergePlane, homography: Homography) -> Double {
        let inverse = homography.inverse
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        let w = reference.width, h = reference.height
        for row in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                // Core Image coordinates of the pixel's center: rows from the bottom.
                let ci = SIMD2(Double(x) + 0.5, Double(h - 1 - row) + 0.5)
                let source = inverse.apply(ci)
                let fx = Int(source.x.rounded(.down)), fyCI = Int(source.y.rounded(.down))
                guard fx >= 0, fx < frame.width, fyCI >= 0, fyCI < frame.height else { continue }
                let a = Double(frame[fx, frame.height - 1 - fyCI])
                let b = Double(reference[x, row])
                n += 1; sx += a; sy += b; sxx += a * a; syy += b * b; sxy += a * b
            }
        }
        guard n > 16 else { return 0 }
        let cov = sxy / n - sx / n * sy / n
        let va = sxx / n - sx / n * sx / n, vb = syy / n - sy / n * sy / n
        guard va > 0, vb > 0 else { return 0 }
        return cov / sqrt(va * vb)
    }
}
