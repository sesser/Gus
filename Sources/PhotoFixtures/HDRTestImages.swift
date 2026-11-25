import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// HEIC and JPEG files with HDR content, written by Core Image (issue #277).
///
/// Every file's SDR picture is `SyntheticImages.makeImage` for `seed` (so
/// each seed gives a file of its own), and its HDR picture is that picture's
/// light times `gain` everywhere, mid-tones and shadows included, as an
/// iPhone's gain map lifts much of the picture and not only what is above
/// SDR white (the owner's `IMG_0546.HEIC`: the HDR rendition's median
/// luminance is 1.65 times the SDR one's).
public enum HDRTestImages {
    public enum Container: Sendable { case heic, jpeg }

    public enum Transfer: Sendable {
        case pq, hlg

        var colorSpace: CGColorSpace {
            CGColorSpace(name: self == .pq ? CGColorSpace.displayP3_PQ : CGColorSpace.displayP3_HLG)!
        }
    }

    /// An SDR image with a gain map whose HDR rendition is the lifted picture.
    /// `gain` is linear (2 is one stop), at least 1. Throws when Core Image
    /// can't encode it.
    public static func writeGainMap(to url: URL, width: Int, height: Int, seed: UInt64, gain: Double,
                                    container: Container = .heic) throws {
        let (sdr, lifted) = try pictures(width: width, height: height, seed: seed, gain: gain)
        let options: [CIImageRepresentationOption: Any] = [.hdrImage: lifted]
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let data: Data? = switch container {
        case .heic: context.heifRepresentation(of: sdr, format: .RGBA8, colorSpace: space, options: options)
        case .jpeg: context.jpegRepresentation(of: sdr, colorSpace: space, options: options)
        }
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    /// An SDR image with a gain map that brightens one part of the picture
    /// more than the rest (issue #282): its HDR picture is the SDR one's
    /// light times `bright` in the left half of the stored image's top third
    /// and times `dim` elsewhere. Written with EXIF `orientation` (1 to 8), so
    /// a gain map applied without turning it as the photo is turned lands on
    /// the wrong picture content.
    public static func writePatternedGainMap(to url: URL, width: Int, height: Int, seed: UInt64,
                                             orientation: Int32 = 1, bright: Double = 4, dim: Double = 1.5,
                                             container: Container = .heic) throws {
        let (sdr, _) = try pictures(width: width, height: height, seed: seed, gain: 1)
        // Core Image's y axis points up: the stored image's top third is at the top of the extent.
        let region = CGRect(x: 0, y: Double(height) * 2 / 3, width: Double(width) / 2, height: Double(height) / 3)
        let lifted = scaled(sdr, by: bright).cropped(to: region).composited(over: scaled(sdr, by: dim))
            .cropped(to: sdr.extent)
        let tagged = sdr.settingProperties([kCGImagePropertyOrientation as String: orientation])
        let options: [CIImageRepresentationOption: Any] = [.hdrImage: lifted]
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let data: Data? = switch container {
        case .heic: context.heifRepresentation(of: tagged, format: .RGBA8, colorSpace: space, options: options)
        case .jpeg: context.jpegRepresentation(of: tagged, colorSpace: space, options: options)
        }
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    /// A 10-bit HEIC whose own encoding is HDR (PQ or HLG Display P3): the
    /// lifted picture itself, with a gain map toward the SDR picture when
    /// `gainMap` (Core Image writes one only when the encoder supports it).
    public static func writeHDREncoded(to url: URL, width: Int, height: Int, seed: UInt64, gain: Double,
                                       transfer: Transfer, gainMap: Bool = false) throws {
        let (sdr, lifted) = try pictures(width: width, height: height, seed: seed, gain: gain)
        let options: [CIImageRepresentationOption: Any] = gainMap ? [.hdrImage: lifted] : [:]
        let base = gainMap ? sdr : lifted
        let data = try context.heif10Representation(of: base, colorSpace: transfer.colorSpace, options: options)
        try data.write(to: url)
    }

    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
        .workingFormat: CIFormat.RGBAh,
    ])

    private static func pictures(width: Int, height: Int, seed: UInt64, gain: Double) throws -> (sdr: CIImage, lifted: CIImage) {
        guard let pattern = SyntheticImages.makeImage(width: width, height: height, seed: seed) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let sdr = CIImage(cgImage: pattern)
        // Scaled in linear light: the HDR picture is `gain` times the SDR one's light.
        return (sdr, scaled(sdr, by: gain))
    }

    /// `image`'s light times `gain` (the context works in linear light).
    private static func scaled(_ image: CIImage, by gain: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        ])
    }
}
