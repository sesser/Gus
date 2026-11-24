import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// HEIC and JPEG files with an HDR gain map, written by Core Image (issue #277).
///
/// The HDR rendition is the SDR one times `gain` everywhere, mid-tones and
/// shadows included, as an iPhone's gain map lifts much of the picture and
/// not only what is above SDR white (the owner's `IMG_0546.HEIC`: the HDR
/// rendition's median luminance is 1.65 times the SDR one's). The SDR
/// rendition is `SyntheticImages.makeImage` for `seed`, so each seed gives
/// a file of its own.
public enum GainMapImages {
    public enum Container: Sendable { case heic, jpeg }

    /// Writes the file, or throws when Core Image can't encode it (no HEIC
    /// encoder). `gain` is linear (2 is one stop), at least 1.
    public static func write(to url: URL, width: Int, height: Int, seed: UInt64, gain: Double,
                             container: Container = .heic) throws {
        guard let pattern = SyntheticImages.makeImage(width: width, height: height, seed: seed) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAh])
        let sdr = CIImage(cgImage: pattern)
        // Scaled in linear light: the HDR rendition is `gain` times the SDR one's light.
        let lifted = sdr.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        ])
        let options: [CIImageRepresentationOption: Any] = [.hdrImage: lifted]
        let data: Data? = switch container {
        case .heic: context.heifRepresentation(of: sdr, format: .RGBA8, colorSpace: space, options: options)
        case .jpeg: context.jpegRepresentation(of: sdr, colorSpace: space, options: options)
        }
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
