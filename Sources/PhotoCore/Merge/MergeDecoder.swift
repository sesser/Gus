import CoreImage
import Foundation
import ImageIO

/// Decodes one frame of an HDR merge into linear light in the working space
/// (extended linear Rec. 2020), oriented, at full resolution or at a reduced
/// size for the measurements made before the merge.
///
/// The frame is decoded as shot (PRD A2): no saved edits, and nothing the
/// decoder would add to make one photo look good on its own, since that
/// would break the proportion between a pixel's value and the light that
/// reached it, which is what the merge relies on.
///
/// - **Raws the system decoder reads** (`SystemRAWDecoder.reads`): the
///   decoder as for a photo without edits (`RAWDecodeSettings.none`, which
///   pins its version), with its boost (the global tone curve), shadow bias
///   and local tone mapping off and no baseline exposure, so its output is
///   linear in the sensor's values; extended range is on so that highlights reconstructed
///   above white are not cut at 1.
/// - **Raws only LibRaw decodes**: LibRaw's linear camera RGB through the
///   color step for the camera's own white balance, without the step's tone
///   curve (`CameraColorTransform.toneCurve` nil), so it stays linear.
/// - **Everything else** (JPEG, HEIC, TIFF, PNG): Core Image's decode, which
///   undoes the file's encoding curve (its color profile's transfer
///   function) into linear light. A camera's own tone curve on top of that
///   is not undone (status.md, "Spike 4").
public enum MergeDecoder {
    public enum Failure: Error, Equatable, Sendable {
        case undecodable(URL)
        /// The image is larger than `MergeLimits.maximumPixels`.
        case tooLarge(URL)
    }

    /// Refuses a size over `MergeLimits.maximumPixels` before anything is
    /// rendered at it (security review M1).
    static func check(_ size: CGSize, _ url: URL) throws {
        let pixels = Double(size.width) * Double(size.height)
        guard pixels.isFinite, pixels <= Double(MergeLimits.maximumPixels) else { throw Failure.tooLarge(url) }
    }

    /// Which decoder gives a frame its pixels.
    public enum Source: String, Sendable, Hashable {
        case systemRAW
        case libRaw
        case imageIO
    }

    /// The decoder `url` gets: the same test `PreviewGenerator.decode` makes.
    public static func source(of url: URL) -> Source {
        guard SupportedFormats.isRaw(pathExtension: url.pathExtension) else { return .imageIO }
        return SystemRAWDecoder.reads(url) ? .systemRAW : .libRaw
    }

    /// The frame in linear light at its origin, no larger than `longEdge`
    /// (nil: full resolution). A lazy graph: nothing is decoded until it is
    /// rendered, except a LibRaw decode, which decodes here. A task cancelled
    /// during a LibRaw decode throws `CancellationError`.
    public static func linearImage(_ url: URL, source: Source, longEdge: Int?) throws -> CIImage {
        let image: CIImage
        switch source {
        case .systemRAW:
            guard let raw = CIRAWFilter(imageURL: url) else { throw Failure.undecodable(url) }
            RAWDecodeSettings.none.apply(to: raw)
            raw.boostAmount = 0
            raw.boostShadowAmount = 0
            raw.baselineExposure = 0
            raw.shadowBias = 0
            if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
            raw.extendedDynamicRangeAmount = 1
            let native = raw.nativeSize
            try check(native, url)
            if let longEdge, native.width > 0, native.height > 0 {
                let scale = Double(longEdge) / Double(max(native.width, native.height))
                if scale < 1 { raw.scaleFactor = Float(min(1, scale * 1.25)) }
            }
            guard let output = RAWDecodeGraph.output(of: raw), !output.extent.isEmpty else {
                throw Failure.undecodable(url)
            }
            image = output
        case .libRaw:
            let output: LibRawDecoder.Output
            do {
                output = try LibRawDecoder.decode(url, longEdge: longEdge)
            } catch let cancelled as CancellationError {
                throw cancelled
            } catch LibRawDecoder.Failure.tooLarge {
                throw Failure.tooLarge(url)
            } catch {
                throw Failure.undecodable(url)
            }
            guard !output.linear.extent.isEmpty else { throw Failure.undecodable(url) }
            // LibRaw refuses a sensor over the same size before it unpacks.
            try check(output.linear.extent.size, url)
            var transform = output.step.transform(temperature: nil, tint: nil)
            transform.toneCurve = nil
            image = transform.apply(to: output.linear)
        case .imageIO:
            guard let decoded = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
                  !decoded.extent.isEmpty, !decoded.extent.isInfinite
            else { throw Failure.undecodable(url) }
            // The extent is the header's: nothing is decoded yet.
            try check(decoded.extent.size, url)
            image = decoded
        }
        var placed = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if let longEdge {
            placed = placed.scaledToFit(longEdge: longEdge)
        }
        return placed
    }

    /// The exposure in stops the system's RAW decoder gives `url` by default
    /// (the camera's baseline exposure, which the linear decode leaves out),
    /// so a merged DNG can open as bright as its reference does; 0 for files
    /// the system decoder doesn't read.
    public static func defaultExposure(of url: URL, source: Source) -> Double {
        guard source == .systemRAW, let raw = CIRAWFilter(imageURL: url) else { return 0 }
        RAWDecodeSettings.none.apply(to: raw)
        let value = Double(raw.baselineExposure)
        return value.isFinite ? value : 0
    }
}
