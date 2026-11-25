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
    /// The brightest any HDR version of this photo can be: SDR white
    /// brightened by the gain map's largest gain, wherever that is. An edit
    /// can only make the SDR picture reach SDR white, so no HDR picture of
    /// the photo goes above it. For an iPhone photo it is the file's
    /// headroom; a gain map can also hold larger gains for darker parts.
    public let ceiling: Float

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
        let image = oriented(map, exifOrientation: orientation)
        return GainMap(image: image, headroom: headroom, ceiling: max(headroom, ceiling(of: image, headroom: headroom)))
    }

    /// SDR white through the whole gain map at its full weight, the largest
    /// value found (one small GPU render of the gain map's size), at least 1.
    static func ceiling(of map: CIImage, headroom: Float) -> Float {
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: map.extent)
        let brightened = white.applyingGainMap(map, headroom: headroom)
        guard let maximum = CIFilter(name: "CIAreaMaximum", parameters: [
            kCIInputImageKey: brightened, kCIInputExtentKey: CIVector(cgRect: map.extent),
        ])?.outputImage else { return headroom }
        var pixel = [Float](repeating: 0, count: 4)
        ceilingContext.render(maximum, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                              format: .RGBAf, colorSpace: RenderEngine.hdrColorSpace)
        let largest = max(pixel[0], pixel[1], pixel[2])
        return largest.isFinite ? max(1, largest) : headroom
    }

    private static let ceilingContext = CIContext(options: [
        .workingColorSpace: RenderEngine.workingColorSpace, .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false, .name: "gain-map-ceiling",
    ])

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
    /// size: the gain map is usually half the photo's size), then taken
    /// through everything in `values` that moves picture content as the
    /// decode is: Distortion, spots, turns, straightening and crop (R19,
    /// `AdjustmentRenderer.gainMapGeometry`).
    public func placed(over extent: CGRect, values: Adjustments, context: RenderContext) -> CIImage {
        guard let stretched = stretched(over: extent) else { return image }
        return AdjustmentRenderer.gainMapGeometry(values, stretched, context: context).settingProperties(image.properties)
    }

    /// The gain map stretched over `extent`, then through `crop` only (tests).
    func placed(over extent: CGRect, crop: Crop) -> CIImage {
        guard let stretched = stretched(over: extent) else { return image }
        return crop.apply(to: stretched).settingProperties(image.properties)
    }

    private func stretched(over extent: CGRect) -> CIImage? {
        let size = image.extent.size
        guard size.width > 0, size.height > 0, !extent.isEmpty, !extent.isInfinite else { return nil }
        let fit = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / size.width, y: extent.height / size.height)
        // Clamped first, so the stretch's edge pixels don't blend with transparency.
        return image.clampedToExtent().transformed(by: fit).cropped(to: extent)
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
        let limit = GainMapHeadroom.tag(display: displayHeadroom, ceiling: ceiling)
        let sdr = Self.clamped(rendered, maximum: 1)
        let brightened = sdr.applyingGainMap(placed, headroom: GainMapHeadroom.weighting(file: headroom,
                                                                                         display: displayHeadroom))
        return (Self.clamped(brightened, maximum: limit).cropped(to: rendered.extent), limit)
    }

    /// The HDR version of `rendered` at the file's full brightening, for no
    /// display: what the HDR histogram counts (design §7, R10). Limited only
    /// by the photo's ceiling.
    public func fullHDR(_ rendered: CIImage, placed: CIImage) -> CIImage {
        hdr(rendered, placed: placed, displayHeadroom: max(headroom, ceiling)).image
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
    /// with: the display's, or the photo's ceiling (`GainMap.ceiling`) when
    /// the display can show more. One tag for every frame of a visit,
    /// whatever an edit does to the brightest pixel, and never above what
    /// the display can show, so Core Animation has nothing to tone map. The
    /// tag is also what the layer asks the display for.
    public static func tag(display: Float, ceiling: Float) -> Float {
        max(1, min(display, ceiling))
    }

    /// Re-render when the display's headroom moved more than this many
    /// stops from the one a picture was rendered for: well below what an eye
    /// sees in a step of the brightness keys, and above float noise in the
    /// screen's readings.
    public static let tolerance: Float = 0.02

    /// Whether a picture tagged `rendered` should be rendered again for a
    /// display whose headroom is `display` now (`ceiling`: the photo's).
    public static func needsRender(rendered: Float, display: Float, ceiling: Float) -> Bool {
        let wanted = tag(display: display, ceiling: ceiling)
        guard rendered > 0 else { return true }
        return abs(log2(wanted / rendered)) > tolerance
    }

    /// Whether two readings of a headroom differ by more than the tolerance.
    public static func differs(_ first: Float, _ second: Float) -> Bool {
        guard first > 0, second > 0 else { return first != second }
        return abs(log2(first / second)) > tolerance
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

/// What the loupe has learned of a display's headroom now (issue #282, R6),
/// from the screen's current-headroom readings while its layer asks for
/// extended range.
///
/// Measured on macOS 27.2.1 (status.md): the current reading ramps, over
/// about a second, to the smaller of what the layer asks for (its image's
/// tag, or `CALayer.contentsHeadroom`) and what the display can give at its
/// brightness (9.82 here), while the potential reading stays at the panel's
/// maximum (16). So the potential is not what the display can show now, and
/// a settled reading below the request is. The loupe asks for the photo's
/// ceiling (`GainMap.ceiling`): a reading that settles at it says only that
/// the display can show the whole photo. Readings during a ramp are not
/// taken: a reading counts once the request has held for `grace` seconds
/// and the value for `settle` seconds.
public struct DisplayHeadroomReading: Sendable, Equatable {
    /// What the display can give now, nil while not known to be less than
    /// a request (then it can show at least what was asked).
    public private(set) var estimate: Float?
    /// What the layer asks for now, nil when it asks for nothing.
    public private(set) var request: Float?
    private var last: Float?
    private var lastSince: Double = 0
    private var requestedSince: Double = 0

    public static let grace = 1.0
    public static let settle = 0.5

    public init() {}

    /// Forgets everything (the window moved to another screen).
    public mutating func reset() { self = DisplayHeadroomReading() }

    /// The layer asks for `request` from `time` (seconds; nil: it stopped
    /// asking). The estimate is kept; a new request waits out the grace.
    public mutating func setRequest(_ request: Float?, at time: Double) {
        guard let request else {
            self.request = nil
            return
        }
        if let current = self.request, !GainMapHeadroom.differs(current, request) { return }
        self.request = request
        requestedSince = time
        last = nil
    }

    /// Takes the screen's current reading at `time`; true when the headroom
    /// to fit to (`headroom(potential:)`) may have changed.
    ///
    /// `remembers`: the app is active, so a settled reading is remembered
    /// for the screen (design §18.1, 4). A reading taken while it is not is
    /// followed (R6) but not remembered, and is forgotten by `becameActive`.
    ///
    /// What a settled reading teaches (design §18.1, 3): one below the
    /// request is the screen's limit now and replaces what was remembered;
    /// one at the request says only that the screen allows at least that, so
    /// it erases a remembered limit only when that limit is lower (the screen
    /// now allows more), never one at or above the request.
    @discardableResult
    public mutating func read(_ current: Float, at time: Double, remembers: Bool = true) -> Bool {
        guard let request else { return false }
        guard let last, !GainMapHeadroom.differs(last, current) else {
            self.last = current
            self.lastSince = time
            return false
        }
        guard time - requestedSince >= Self.grace, time - lastSince >= Self.settle else { return false }
        let before = effective
        // Below the request: the display's limit now. At it: at least the request.
        let limit: Float? = current < request && GainMapHeadroom.differs(current, request) ? current : nil
        if remembers {
            inactive = nil
            if let limit {
                if estimate.map({ GainMapHeadroom.differs($0, limit) }) ?? true { estimate = limit }
            } else if let known = estimate, known < request, GainMapHeadroom.differs(known, request) {
                estimate = nil
            }
        } else {
            inactive = Inactive(limit: limit ?? estimate.flatMap { $0 < request ? nil : $0 })
        }
        return before != effective
    }

    /// The app became active: readings taken while it was not are forgotten,
    /// and the remembered value applies again (design §18.1, 4).
    public mutating func becameActive() {
        inactive = nil
    }

    /// A settled reading taken while the app was not active.
    private struct Inactive: Sendable, Equatable {
        var limit: Float?
    }
    private var inactive: Inactive?

    /// The limit to fit to, if one is known.
    private var effective: Float? {
        if let inactive { return inactive.limit }
        return estimate
    }

    /// The headroom to fit to: what the display is known to give, at most
    /// `potential`; the potential while nothing less is known.
    public func headroom(potential: Float) -> Float {
        min(potential, effective ?? potential)
    }

    /// What the screen allows now, if known (design §18.2): the settled
    /// limit, or nil while it is only known to allow at least what was asked.
    public var allowedNow: Float? { effective }
}

/// What each screen allows, remembered for as long as the app runs (issue
/// #282, R6, design §18.1, 2): owned outside the loupe, so it survives the
/// grid, a video, comparison, review and moving the window away and back,
/// and the single loupe and the comparison panes share it. Keyed by the
/// screen's display number.
public struct DisplayHeadroomMemory: Sendable {
    private var screens: [UInt32: DisplayHeadroomReading] = [:]

    public init() {}

    /// The screen's reading (a fresh one for a screen not seen yet).
    public subscript(screen: UInt32) -> DisplayHeadroomReading {
        get { screens[screen] ?? DisplayHeadroomReading() }
        set { screens[screen] = newValue }
    }

    /// The app became active: readings taken while it was not are dropped
    /// on every screen (design §18.1, 4).
    public mutating func becameActive() {
        for screen in screens.keys { screens[screen]?.becameActive() }
    }
}
