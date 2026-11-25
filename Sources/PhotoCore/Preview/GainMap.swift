import CoreImage
import Foundation
import ImageIO

/// The gain map of a gain-map photo (issue #282): data in a HEIC or JPEG
/// (Ultra HDR included) saying how much brighter each part of the picture
/// is in the file's HDR version.
///
/// A photo is edited in its SDR version, as every other photo is, and the
/// HDR version is that edited picture brightened point by point by the gain
/// map, as the last step of the render ("gain last",
/// `docs/features/gain-map-hdr/spike.md`). So every adjustment works the
/// same in both versions, and nothing that renders SDR (previews, exports,
/// `photocli`) changes.
///
/// Only files whose HDR comes from a gain map alone: not raws (their gain
/// maps are out of scope), not videos, and not HLG or PQ encoded images,
/// which keep their own HDR rendition (`PreviewGenerator.hdrImage`, R16).
public struct GainMap: @unchecked Sendable {
    // @unchecked: CIImage is an immutable recipe, safe to share.

    /// The gain map, turned as the file's decode is (EXIF orientation),
    /// with its origin at zero and the file's gain map metadata.
    public let image: CIImage
    /// How many times brighter than SDR white the file's HDR version goes:
    /// its alternate headroom, above 1.
    public let headroom: Float

    /// Whether `url` is a gain-map photo, from its header: a non-raw,
    /// non-video file with a gain map (ISO 21496-1 or Apple's) and no HLG or
    /// PQ encoding. Nothing is decoded.
    public static func exists(_ url: URL) -> Bool {
        guard let source = eligibleSource(url) else { return false }
        return hasGainMap(source)
    }

    /// The file's gain map, or nil when it is not a gain-map photo or its
    /// gain map brightens nothing. Reads the file's header and its gain
    /// map's description; the gain map's pixels are decoded lazily, by the
    /// render that uses them.
    public static func load(_ url: URL) -> GainMap? {
        guard let source = eligibleSource(url), hasGainMap(source),
              let map = CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true]),
              !map.extent.isEmpty, !map.extent.isInfinite,
              // The HDR decode's headroom is the file's alternate headroom (its
              // metadata only: the expanded picture is not rendered here).
              let expanded = CIImage(contentsOf: url, options: [.expandToHDR: true])
        else { return nil }
        let headroom = expanded.contentHeadroom
        guard headroom > 1 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        return GainMap(image: oriented(map, exifOrientation: orientation), headroom: headroom)
    }

    /// Core Image returns the auxiliary image as stored, not turned as the
    /// photo is (spike, trap 1): turned here, so the gain map lands on the
    /// picture content it describes. The metadata stays with it.
    static func oriented(_ map: CIImage, exifOrientation: Int32) -> CIImage {
        var image = map
        if exifOrientation != 1, (1...8).contains(exifOrientation) {
            image = image.oriented(forExifOrientation: exifOrientation)
        }
        let extent = image.extent
        if extent.origin != .zero {
            image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        }
        return image.settingProperties(map.properties)
    }

    /// The gain map stretched over `extent` (a decode of the photo, of any
    /// size: the gain map is usually half the photo's size), then turned,
    /// straightened and cropped by `crop` as the decode is.
    ///
    /// First stage of #282: the Lens heading's Distortion and spots, which
    /// also move picture content, are not followed yet (R19).
    public func placed(over extent: CGRect, crop: Crop) -> CIImage {
        let size = image.extent.size
        guard size.width > 0, size.height > 0, !extent.isEmpty, !extent.isInfinite else { return image }
        let fit = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / size.width, y: extent.height / size.height)
        // Clamped first, so the stretch's edge pixels don't blend with transparency.
        let stretched = image.clampedToExtent().transformed(by: fit).cropped(to: extent)
        return crop.apply(to: stretched).settingProperties(image.properties)
    }

    /// The HDR version of `rendered`, the photo's edited SDR version in the
    /// working space, for a display that can show `displayHeadroom` times
    /// SDR white now: the SDR picture as it is shown (clipped to SDR white in
    /// Display P3), brightened by `placed` (from `placed(over:crop:)` with
    /// the same decode and crop) by the gain map's own rule for the display
    /// (`GainMapHeadroom.weighting`), and limited to what the display can
    /// show. Returns the image with that limit, the headroom to tag it with
    /// (`GainMapHeadroom.tag`).
    ///
    /// Fitting by the gain map's rule reduces the brightening, mid-tones
    /// included, where the file goes brighter than the display (owner's
    /// ruling Q2). Limiting to the display, not to the file's headroom, keeps
    /// each point's brightening when an edit makes the SDR picture brighter
    /// than the file's (R7), and keeps every value within the tag, so what
    /// the screen does with a pixel depends only on that pixel and the
    /// display (design §6.3).
    public func hdr(_ rendered: CIImage, placed: CIImage, displayHeadroom: Float) -> (image: CIImage, headroom: Float) {
        let limit = GainMapHeadroom.tag(display: displayHeadroom)
        let sdr = Self.clamped(rendered, maximum: 1)
        let brightened = sdr.applyingGainMap(placed, headroom: GainMapHeadroom.weighting(file: headroom,
                                                                                         display: displayHeadroom))
        return (Self.clamped(brightened, maximum: limit).cropped(to: rendered.extent), limit)
    }

    /// Each color component of `image` (in the working space) between 0
    /// and `maximum` in extended linear Display P3, the space HDR pictures
    /// are shown in; alpha unchanged.
    static func clamped(_ image: CIImage, maximum: Float) -> CIImage {
        let space = RenderEngine.hdrColorSpace
        let value = CGFloat(maximum)
        let shown = image.matchedFromWorkingSpace(to: space) ?? image
        let clamped = shown.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: value, y: value, z: value, w: 1),
        ])
        return clamped.matchedToWorkingSpace(from: space) ?? clamped
    }

    /// The file's image source, when the file may be a gain-map photo at
    /// all: not a raw, not a video, not HLG or PQ encoded.
    private static func eligibleSource(_ url: URL) -> CGImageSource? {
        guard !SupportedFormats.isRaw(pathExtension: url.pathExtension),
              FileKind(pathExtension: url.pathExtension) != .video,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              !PreviewGenerator.hasHDREncoding(source)
        else { return nil }
        return source
    }

    private static func hasGainMap(_ source: CGImageSource) -> Bool {
        [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap].contains {
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil
        }
    }
}

/// How bright a gain-map photo's HDR version is rendered (issue #282, R6).
public enum GainMapHeadroom {
    /// The headroom the gain map is applied for (its weighting): the file's
    /// own, fitted to what the display can show now, never below SDR.
    public static func weighting(file: Float, display: Float) -> Float {
        max(1, min(file, display))
    }

    /// The headroom an HDR picture for a display is limited to and tagged
    /// with: the display's. One tag for every frame of a visit, whatever an
    /// edit does to the brightest pixel, and never above what the display
    /// can show, so Core Animation has nothing to tone map.
    public static func tag(display: Float) -> Float {
        max(1, display)
    }

    /// Re-render when the display's headroom moved more than this many
    /// stops from the one a picture was rendered for: well below what an eye
    /// sees in a step of the brightness keys, and above float noise in the
    /// screen's readings.
    public static let tolerance: Float = 0.02

    /// Whether a picture tagged `rendered` should be rendered again for a
    /// display whose headroom is `display` now.
    public static func needsRender(rendered: Float, display: Float) -> Bool {
        let wanted = tag(display: display)
        guard rendered > 0 else { return true }
        return abs(log2(wanted / rendered)) > tolerance
    }
}

/// Which version of a gain-map photo is on screen.
public enum ShownVersion: String, Sendable, Equatable {
    case sdr, hdr
}

/// The loupe's rule for one visit to a photo shown in HDR (issue #282, R8):
/// arriving may show the cached SDR preview first and change once to HDR;
/// once HDR is on screen, no SDR picture of the photo replaces it for the
/// rest of the visit. A map (sharpening, fringe) is neither version and
/// changes nothing. A visit ends when the photo, the person's HDR choice or
/// the conditions for HDR change (the loupe then begins another).
public struct GainMapVisit: Sendable, Equatable {
    public private(set) var versionID: Int64?
    /// The version on screen, nil before the first picture of the visit.
    public private(set) var shown: ShownVersion?
    /// Times the version on screen changed during the visit.
    public private(set) var changes = 0
    /// The headroom the HDR picture on screen was rendered for.
    public private(set) var renderedHeadroom: Float?

    public init() {}

    /// A new visit: another photo, or the same one after a change of the
    /// choice or of what the display allows.
    public mutating func begin(versionID: Int64?) {
        self = GainMapVisit()
        self.versionID = versionID
    }

    /// Whether a picture of `version` may go on screen now; records it when
    /// it may. `wantsHDR`: the visit shows this photo in HDR (a gain-map
    /// photo with the choice on, on a display and setting that allow it).
    /// `headroom` is an HDR picture's.
    public mutating func accept(_ version: ShownVersion, isMap: Bool = false, wantsHDR: Bool,
                                headroom: Float? = nil) -> Bool {
        if isMap { return true }
        if wantsHDR, version == .sdr, shown == .hdr { return false }
        if let shown, shown != version { changes += 1 }
        shown = version
        renderedHeadroom = version == .hdr ? headroom : nil
        return true
    }
}

/// The temporary switch of #282's first stage: every gain-map photo is
/// shown and edited in HDR, for the owner's early check by eye (design
/// §13), before the per-photo choice exists. Only a test launch can turn it
/// on (`LibraryLaunchGuard`'s definition: a bundle identifier other than the
/// release one, or a scripted launch). To be removed when the stored choice
/// replaces it (status.md).
public enum TemporaryGainMapHDR {
    public static func isOn(bundleIdentifier: String?, releaseIdentifier: String = AppBranding.bundleIdentifier,
                            options: LaunchOptions) -> Bool {
        guard options.gainMapHDR == "on" else { return false }
        let scripted = options.debugScript != nil || options.benchmarkScroll
        return bundleIdentifier != releaseIdentifier || scripted
    }
}
