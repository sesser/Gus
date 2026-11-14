import CLibRaw
import CoreImage
import Foundation
import os

/// Decodes a raw file with the vendored LibRaw (LGPL 2.1, `THIRD_PARTY_NOTICES.md`),
/// for raws the system's RAW decoder gives no image for (issue #161;
/// `PreviewGenerator.decode` falls back to it) and for comparing the two
/// decoders (`photobench rawcompare`).
///
/// It demosaics to linear camera RGB, balanced for the camera's own white
/// but not clipped at it, with no color matrix, no automatic brightening and
/// no tone curve, oriented, 16 bits a channel, and crops to the frame the
/// file records (`Frame`). The color step that follows (`CameraColorStep`:
/// white balance for the stack's Kelvin and tint, the camera's matrix, the
/// baseline look) turns that into the working space, so another white
/// balance never needs another decode (issue #170). A file whose color data
/// cannot be used (no matrix for the camera, no white balance coefficients,
/// a sensor that is not three colors) is rendered by LibRaw itself, to
/// linear Rec. 2020 with the camera's white balance, and gets the baseline
/// look only (`CameraColorStep.color` nil).
///
/// **The white level is the file's.** LibRaw's default takes the brightest
/// value in the frame as white when it is over three quarters of the file's
/// white level (`adjust_maximum_thr`), which made two frames of one scene
/// differ by up to 0.4 EV; that is turned off, so a decode's level never
/// depends on its content. The default exists for sensors that saturate
/// below the level their files state, whose blown highlights would
/// otherwise keep a cast: `whiteMargin` covers what was measured here.
///
/// Each call has a LibRaw instance of its own and LibRaw is built thread-safe
/// (without `LIBRAW_NOTHREADS`), so decodes may run at the same time.
public enum LibRawDecoder {
    private static let log = Logger(subsystem: AppBranding.bundleIdentifier, category: "decode")

    public struct Output {
        /// The decode before its color step, cut to the frame and with the
        /// camera's lens corrections: camera RGB when `step.color` is set,
        /// else the working space. Its pixels pass through Core Image
        /// unconverted (it is tagged as the working space either way).
        public var linear: CIImage
        /// What turns `linear` into the photo.
        public var step: CameraColorStep
        /// LibRaw's own pixels (before a Fujifilm RAF's frame is cut from them
        /// and its lens corrections applied): red, green, blue and alpha, 16
        /// bits each in host order, rows from the top.
        var rgba16: Data
        /// The decode's size in pixels (half the frame's with `halfSize`).
        public var size: CGSize
        /// The frame's size at full resolution.
        public var fullSize: CGSize
        public var cameraMake: String
        public var cameraModel: String
        /// The camera's lens corrections were read from the file and applied.
        public var hasLensCorrections = false

        /// The photo in the working space, with the camera's own white
        /// balance or the one given.
        public func image(whiteBalance: ColorTemperature? = nil) -> CIImage {
            step.apply(to: linear, temperature: whiteBalance?.kelvin, tint: whiteBalance?.tint)
        }
    }

    /// The part of the file's white level at which a channel counts as
    /// saturated. The sensors measured saturate a little under the level
    /// their files state (54 Fujifilm X-E3 files: their clipped areas peak
    /// at 16322 to 16383 of 16383 over a black of about 1022, so at 0.996
    /// and up; an X-T3, a Sony, an Olympus and a Panasonic at 0.999 and up),
    /// and a channel clipped just under white would leave blown highlights
    /// with a faint cast. At 0.99 every one of them is white, for 0.015 EV
    /// of highlight range. A sensor that saturates further below its file's
    /// white level than that keeps a cast in blown highlights (none here).
    static let whiteMargin = 0.99

    public enum Failure: Error, CustomStringConvertible {
        case libraw(String, code: Int32)
        case noMemory
        /// The sensor is larger than `maximumSensorPixels`: megapixels.
        case tooLarge(megapixels: Int)

        public var description: String {
            switch self {
            case .libraw(let step, let code): "LibRaw \(step): \(String(cString: libraw_strerror(code))) (\(code))"
            case .noMemory: "LibRaw could not allocate"
            case .tooLarge(let megapixels):
                "a \(megapixels) megapixel sensor is over the \(LibRawDecoder.maximumSensorPixels / 1_000_000) megapixels LibRaw is given here"
            }
        }
    }

    /// The largest sensor (raw width times raw height) LibRaw is asked to
    /// decode. A full decode holds about 22 bytes a pixel in LibRaw's and
    /// this bridge's buffers (10 GB peak for 192 megapixels, code review
    /// C17), starts without the user asking, several at a time, and cannot
    /// be cancelled. 150 megapixels is above every camera's single frame
    /// (the largest medium format backs) and bounds a decode at about 3.3 GB;
    /// a larger file is refused, with a log line, and is undecodable.
    public static let maximumSensorPixels = 150_000_000

    static func isTooLarge(rawWidth: Int, rawHeight: Int) -> Bool {
        rawWidth * rawHeight > maximumSensorPixels
    }

    /// The camera's frame of a Fujifilm RAF, when it can be used with
    /// LibRaw's image: the file's records describe the sensor as LibRaw reads
    /// it (the same full size), and the sensor is not a Super CCD, which
    /// LibRaw reads turned 45 degrees (`fuji_width`): its records are not a
    /// rectangle of LibRaw's image at all.
    static func cameraFrame(_ camera: FujifilmRAF?, rawWidth: Int, rawHeight: Int, isDiagonal: Bool) -> FujifilmRAF.PixelRect? {
        guard let camera, !isDiagonal, camera.fullWidth == rawWidth, camera.fullHeight == rawHeight else { return nil }
        return camera.cameraFrame
    }

    /// The part of the sensor a decode keeps, from the file's header.
    ///
    /// LibRaw's visible area includes pixels the camera leaves out of its own
    /// pictures (6032x4028 on a Fujifilm X-E3). The frame is, in order:
    ///
    /// 1. the camera's own frame, where the file states it (a Fujifilm RAF:
    ///    6000x4000 at (16, 21) of that sensor, the size of the camera's JPEG
    ///    and of the system decoder's image where it reads such files, and
    ///    the frame the camera's lens corrections are centered on). LibRaw
    ///    decodes the whole visible area and the frame is cut from its image
    ///    (`window`): LibRaw's own crop must start on the sensor's color
    ///    pattern, which this frame does not;
    /// 2. the file's first inset crop as LibRaw reads it (a DNG's default
    ///    crop), which LibRaw crops to itself (`cropBox`);
    /// 3. the visible area.
    ///
    /// A Super CCD's file (`diagonalOutput`) is never cropped: LibRaw turns
    /// its sensor 45 degrees, and neither kind of crop is a rectangle of the
    /// result (as a crop box it gave a strip of the picture, code review C18).
    ///
    /// The second inset crop (a 16:9 or 1:1 picture's) is not read.
    struct Frame {
        /// In sensor pixels, before the orientation.
        var width: Int
        var height: Int
        /// LibRaw's crop box for the frame (left, top, width, height in the
        /// visible area), nil when LibRaw decodes the whole visible area.
        var cropBox: (left: UInt32, top: UInt32, width: UInt32, height: UInt32)?
        /// Where the frame starts in the visible area, in sensor pixels from
        /// its top left, when it is cut from LibRaw's image afterwards.
        var window: (left: Int, top: Int)?
        var visibleWidth: Int
        var visibleHeight: Int
        /// LibRaw's orientation of its image: 1 mirrors columns, 2 mirrors
        /// rows, 4 swaps rows and columns first (`LibRaw::flip_index`).
        var flip: Int

        /// The file's orientation swaps width and height: a quarter turn, mirrored
        /// or not (bit 4 of LibRaw's flip: 5 and 6, and the mirrored 4 and 7).
        var isTurned: Bool { flip & 4 != 0 }

        var longEdge: Int { max(width, height) }

        /// The frame as it is shown.
        var orientedSize: CGSize {
            isTurned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }

        init(_ sizes: libraw_image_sizes_t, cameraFrame: FujifilmRAF.PixelRect? = nil, diagonalOutput: CGSize? = nil) {
            let inset = sizes.raw_inset_crops.0
            self.init(visibleWidth: Int(sizes.width), visibleHeight: Int(sizes.height),
                      leftMargin: Int(sizes.left_margin), topMargin: Int(sizes.top_margin),
                      insetLeft: Int(inset.cleft), insetTop: Int(inset.ctop),
                      insetWidth: Int(inset.cwidth), insetHeight: Int(inset.cheight), flip: Int(sizes.flip),
                      cameraFrame: cameraFrame, diagonalOutput: diagonalOutput)
        }

        /// LibRaw's sizes: the visible area and its margins on the sensor, and
        /// the inset crop in sensor coordinates (an unset one has no size, and
        /// its origin is 0xffff). An inset that starts before the visible
        /// area is not a crop of it and is left out, as is a camera frame
        /// that does not lie within the visible area.
        init(visibleWidth: Int, visibleHeight: Int, leftMargin: Int, topMargin: Int,
             insetLeft: Int, insetTop: Int, insetWidth: Int, insetHeight: Int, flip: Int,
             cameraFrame: FujifilmRAF.PixelRect? = nil, diagonalOutput: CGSize? = nil) {
            self.visibleWidth = visibleWidth
            self.visibleHeight = visibleHeight
            self.flip = flip
            if let diagonalOutput {
                // The picture as LibRaw gives it (already as shown): no crop of either kind.
                let turned = flip & 4 != 0
                width = Int(turned ? diagonalOutput.height : diagonalOutput.width)
                height = Int(turned ? diagonalOutput.width : diagonalOutput.height)
                cropBox = nil
            } else if let camera = cameraFrame, camera.width > 0, camera.height > 0,
               camera.left >= leftMargin, camera.top >= topMargin,
               camera.left - leftMargin + camera.width <= visibleWidth,
               camera.top - topMargin + camera.height <= visibleHeight {
                width = camera.width
                height = camera.height
                window = (camera.left - leftMargin, camera.top - topMargin)
                cropBox = nil
            } else if insetWidth > 0, insetHeight > 0, insetLeft >= leftMargin, insetTop >= topMargin,
                      insetLeft != 0xffff, insetTop != 0xffff {
                width = insetWidth
                height = insetHeight
                cropBox = (UInt32(insetLeft - leftMargin), UInt32(insetTop - topMargin),
                           UInt32(insetWidth), UInt32(insetHeight))
            } else {
                width = visibleWidth
                height = visibleHeight
                cropBox = nil
            }
        }

        /// The frame in LibRaw's image of the whole visible area, oriented as
        /// LibRaw orients it and `imageSize` large (the visible area, or half
        /// of it), in Core Image's coordinates (from the bottom left). It may
        /// start between pixels in a half-size image. Nil without a `window`.
        func windowRect(inImageOf imageSize: CGSize) -> CGRect? {
            guard let window, visibleWidth > 0, visibleHeight > 0 else { return nil }
            // Columns and rows the frame covers on the sensor, mirrored as LibRaw mirrors them …
            var columns = (start: window.left, end: window.left + width)
            var rows = (start: window.top, end: window.top + height)
            if flip & 1 != 0 { columns = (visibleWidth - columns.end, visibleWidth - columns.start) }
            if flip & 2 != 0 { rows = (visibleHeight - rows.end, visibleHeight - rows.start) }
            // … then swapped: the image's columns are the sensor's rows.
            var across = (range: columns, of: visibleWidth), down = (range: rows, of: visibleHeight)
            if isTurned { swap(&across, &down) }
            let sx = imageSize.width / CGFloat(across.of), sy = imageSize.height / CGFloat(down.of)
            return CGRect(x: CGFloat(across.range.start) * sx, y: imageSize.height - CGFloat(down.range.end) * sy,
                          width: CGFloat(across.range.end - across.range.start) * sx,
                          height: CGFloat(down.range.end - down.range.start) * sy)
        }
    }

    /// Whether a decode for a target of `longEdge` pixels (nil for full
    /// resolution) bins each 2x2 block instead of demosaicing: when the
    /// target is at most half the frame's long edge. Much faster, and still
    /// at least the target's size.
    static func usesHalfSize(longEdge: Int?, frameLongEdge: Int) -> Bool {
        longEdge.map { $0 * 2 <= frameLongEdge } ?? false
    }

    /// The size of a full-resolution decode of `url` as it is shown, read
    /// from the file's header alone (nothing is unpacked), or nil when LibRaw
    /// cannot read the file.
    public static func frameSize(_ url: URL) -> CGSize? {
        guard let processor = libraw_init(0) else { return nil }
        defer { libraw_close(processor) }
        guard libraw_open_file(processor, url.path) == LIBRAW_SUCCESS.rawValue else { return nil }
        let sizes = processor.pointee.sizes
        // A file `decode` refuses has no frame.
        guard !isTooLarge(rawWidth: Int(sizes.raw_width), rawHeight: Int(sizes.raw_height)) else { return nil }
        let frame = frame(of: processor, url: url).frame
        return frame.width > 0 && frame.height > 0 ? frame.orientedSize : nil
    }

    /// The frame of an opened file, and the Fujifilm container it came from, if it is one.
    private static func frame(of processor: UnsafeMutablePointer<libraw_data_t>, url: URL) -> (frame: Frame, camera: FujifilmRAF?) {
        let sizes = processor.pointee.sizes
        let camera = FujifilmRAF(contentsOf: url)
        if processor.pointee.rawdata.ioparams.fuji_width != 0 {
            // Never a crop box for these, also when the size cannot be worked out.
            let size = diagonalOutputSize(url) ?? CGSize(width: Int(sizes.width), height: Int(sizes.height))
            return (Frame(sizes, diagonalOutput: size), camera)
        }
        let cameraFrame = cameraFrame(camera, rawWidth: Int(sizes.raw_width), rawHeight: Int(sizes.raw_height), isDiagonal: false)
        return (Frame(sizes, cameraFrame: cameraFrame), camera)
    }

    /// The size of LibRaw's picture of a Super CCD file, as shown: LibRaw
    /// works it out from the header (`libraw_adjust_sizes_info_only`), on an
    /// instance of its own, since that changes the instance's sizes.
    private static func diagonalOutputSize(_ url: URL) -> CGSize? {
        guard let processor = libraw_init(0) else { return nil }
        defer { libraw_close(processor) }
        guard libraw_open_file(processor, url.path) == LIBRAW_SUCCESS.rawValue,
              libraw_adjust_sizes_info_only(processor) == LIBRAW_SUCCESS.rawValue else { return nil }
        let sizes = processor.pointee.sizes
        return sizes.iwidth > 0 && sizes.iheight > 0 ? CGSize(width: Int(sizes.iwidth), height: Int(sizes.iheight)) : nil
    }

    /// The camera's color as the file's header gives it (nothing is
    /// unpacked, about 1 ms), or nil when LibRaw cannot read the file or its
    /// color data cannot be used: the as-shot Kelvin and tint the White
    /// Balance group shows before any decode, and whether it can offer any.
    public static func cameraColor(_ url: URL) -> CameraColor? {
        guard let processor = libraw_init(0) else { return nil }
        defer { libraw_close(processor) }
        guard libraw_open_file(processor, url.path) == LIBRAW_SUCCESS.rawValue else { return nil }
        return cameraColor(of: processor)
    }

    /// The camera's color of an opened file, with the built-in profile:
    ///
    /// - the as-shot neutral is the reciprocal of the camera's white balance
    ///   coefficients (LibRaw's `cam_mul`, which for a DNG are the
    ///   reciprocal of `AsShotNeutral`);
    /// - a DNG brings its own color matrices with their illuminants, its
    ///   forward matrices, camera calibration, analog balance and baseline
    ///   exposure; any other file has LibRaw's matrix for the camera, which
    ///   is for D65 (Adobe's second matrix, as dcraw's table has it).
    ///
    /// Nil for a sensor that is not three colors, a file whose white balance
    /// the camera already applied (LibRaw's `as_shot_wb_applied`), one
    /// without coefficients or without a matrix, and color data that gives
    /// no white point.
    static func cameraColor(of processor: UnsafeMutablePointer<libraw_data_t>) -> CameraColor? {
        guard processor.pointee.idata.colors == 3, processor.pointee.color.as_shot_wb_applied == 0 else { return nil }
        let multipliers = processor.pointee.color.cam_mul
        let coefficients = SIMD3(Double(multipliers.0), Double(multipliers.1), Double(multipliers.2))
        guard coefficients.min() > 1e-5, coefficients.max().isFinite else { return nil }
        var calibrations: [CameraProfile.Calibration] = []
        var cameraCalibration: [Matrix3x3] = []
        var baselineExposure = 0.0
        if processor.pointee.idata.dng_version != 0 {
            let levels = processor.pointee.color.dng_levels
            let balance = Matrix3x3.diagonal(SIMD3(Double(levels.analogbalance.0), Double(levels.analogbalance.1),
                                                   Double(levels.analogbalance.2)))
            for color in [processor.pointee.color.dng_color.0, processor.pointee.color.dng_color.1] {
                let m = color.colormatrix
                let matrix = Matrix3x3([m.0.0, m.0.1, m.0.2, m.1.0, m.1.1, m.1.2, m.2.0, m.2.1, m.2.2].map(Double.init))
                guard let kelvin = CameraProfile.kelvin(ofLightSource: Int(color.illuminant)), matrix.inverse != nil else { continue }
                let f = color.forwardmatrix
                let forward = Matrix3x3([f.0.0, f.0.1, f.0.2, f.1.0, f.1.1, f.1.2, f.2.0, f.2.1, f.2.2].map(Double.init))
                let c = color.calibration
                let calibration = Matrix3x3([c.0.0, c.0.1, c.0.2, c.1.0, c.1.1, c.1.2, c.2.0, c.2.1, c.2.2].map(Double.init))
                calibrations.append(.init(illuminant: kelvin, colorMatrix: matrix,
                                          forwardMatrix: forward.inverse != nil ? forward : nil))
                // A file without the tag leaves LibRaw's matrix at zero: identity.
                cameraCalibration.append(balance * (calibration.inverse != nil ? calibration : .identity))
            }
            // The profile sorts its calibrations by temperature; keep each camera calibration with its own.
            if calibrations.count == 2, calibrations[0].illuminant > calibrations[1].illuminant {
                cameraCalibration.swapAt(0, 1)
            }
            // LibRaw's value for "not in the file".
            if levels.baseline_exposure > -100, levels.baseline_exposure.isFinite {
                baselineExposure = Double(levels.baseline_exposure)
            }
        }
        if let bias = fujifilmExposureBias(of: processor) {
            baselineExposure = bias
        }
        if calibrations.isEmpty {
            let m = processor.pointee.color.cam_xyz
            let matrix = Matrix3x3([m.0.0, m.0.1, m.0.2, m.1.0, m.1.1, m.1.2, m.2.0, m.2.1, m.2.2].map(Double.init))
            guard matrix.inverse != nil else { return nil }
            calibrations = [.init(illuminant: 6500, colorMatrix: matrix)]
            cameraCalibration = []
        }
        let color = CameraColor(profile: .builtIn(calibrations: calibrations), asShotNeutral: SIMD3(1, 1, 1) / coefficients,
                                calibration: cameraCalibration, baselineExposure: baselineExposure)
        return color.isUsable ? color : nil
    }

    /// The exposure a Fujifilm camera held back from the raw data, in stops
    /// over its normal amount; nil for other makers' files and for a file
    /// that does not say.
    ///
    /// A RAF records how far below the camera's nominal exposure its raw
    /// data sits (`RawExposureBias` in ExifTool's naming, LibRaw's
    /// `ExpoMidPointShift`): −0.72 normally, −1.72 when the camera's dynamic
    /// range setting was 200% and −2.72 at 400%, where it exposes the
    /// sensor one or two stops less and brightens its own JPEG back. The
    /// system decoder brightens such raws by the same amount: for six X-T3
    /// files its `baselineExposure` was 0.12 at −0.72 and 1.12 at −1.72.
    /// `BaselineLook.exposure` was measured on a file at −0.72, so this is
    /// what a file adds to it.
    static func fujifilmExposureBias(of processor: UnsafeMutablePointer<libraw_data_t>) -> Double? {
        guard processor.pointee.idata.maker_index == LIBRAW_CAMERAMAKER_Fujifilm.rawValue else { return nil }
        return fujifilmExposure(rawExposureBias: Double(processor.pointee.makernotes.fuji.ExpoMidPointShift))
    }

    /// The stops a Fujifilm raw with this `RawExposureBias` adds to the
    /// baseline. LibRaw's value for "not in the file" is −999; nothing a
    /// camera writes is outside −4 … 0, and such a value adds nothing.
    static func fujifilmExposure(rawExposureBias shift: Double) -> Double? {
        guard shift.isFinite, (-4.0...0.0).contains(shift) else { return nil }
        return max(0, fujifilmNormalExposureBias - shift)
    }

    /// `RawExposureBias` of a Fujifilm raw shot at 100% dynamic range.
    static let fujifilmNormalExposureBias = -0.72

    /// The raw's decode. `halfSize` asks for a binned decode whatever the
    /// target; otherwise `longEdge` decides (`usesHalfSize`).
    ///
    /// A Fujifilm RAF is cut to the camera's frame and given the camera's
    /// lens corrections from the file (`EmbeddedLensCorrection`), as the
    /// system decoder does for the raws it reads; `lensCorrections` false
    /// leaves them out, for comparing.
    public static func decode(_ url: URL, halfSize: Bool = false, longEdge: Int? = nil,
                              lensCorrections: Bool = true) throws -> Output {
        guard let processor = libraw_init(0) else { throw Failure.noMemory }
        defer { libraw_close(processor) }
        libraw_set_output_bps(processor, 16)
        // Linear (gamma 1/1).
        libraw_set_gamma(processor, 0, 1)
        libraw_set_gamma(processor, 1, 1)
        libraw_set_no_auto_bright(processor, 1)
        // White is the file's white level, whatever the frame holds.
        libraw_set_adjust_maximum_thr(processor, 0)

        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("open", code: code) }
        let opened = processor.pointee.sizes
        guard !isTooLarge(rawWidth: Int(opened.raw_width), rawHeight: Int(opened.raw_height)) else {
            throw Failure.tooLarge(megapixels: Int(opened.raw_width) * Int(opened.raw_height) / 1_000_000)
        }
        let (frame, camera) = frame(of: processor, url: url)
        if let box = frame.cropBox {
            processor.pointee.params.cropbox = (box.left, box.top, box.width, box.height)
        }
        let half = halfSize || usesHalfSize(longEdge: longEdge, frameLongEdge: frame.longEdge)
        processor.pointee.params.half_size = half ? 1 : 0
        let color = cameraColor(of: processor)
        var channelScale = SIMD3<Double>(1, 1, 1)
        if let color {
            // Camera RGB: no color matrix. Balanced for the camera's white with our own
            // multipliers (the reciprocal of the neutral the color step works from), the
            // largest 1, so no channel is clipped below its saturation (LibRaw's highlight
            // mode 1): the color step clips, at white, after its own white balance.
            libraw_set_output_color(processor, 0)
            processor.pointee.params.highlight = 1
            processor.pointee.params.use_camera_wb = 0
            processor.pointee.params.use_auto_wb = 0
            let multipliers = color.asShotNeutral.min() / color.asShotNeutral
            processor.pointee.params.user_mul = (Float(multipliers.x), Float(multipliers.y), Float(multipliers.z),
                                                 Float(multipliers.y))
            channelScale = multipliers * whiteMargin
        } else {
            // Rec. 2020 primaries, as the working space, with the camera's white balance, clipped at white.
            libraw_set_output_color(processor, 8)
            processor.pointee.params.use_camera_wb = 1
            log.notice("\(url.lastPathComponent, privacy: .private): no usable camera color data; white balance cannot be changed")
        }
        code = libraw_unpack(processor)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("unpack", code: code) }
        code = libraw_dcraw_process(processor)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("process", code: code) }

        var status: Int32 = 0
        guard let processed = libraw_dcraw_make_mem_image(processor, &status) else {
            throw Failure.libraw("make image", code: status)
        }
        defer { libraw_dcraw_clear_mem(processed) }

        let width = Int(processed.pointee.width), height = Int(processed.pointee.height)
        let colors = Int(processed.pointee.colors)
        guard processed.pointee.bits == 16, colors == 3, width > 0, height > 0 else {
            throw Failure.libraw("unexpected format", code: -1)
        }
        let dataOffset = MemoryLayout<libraw_processed_image_t>.offset(of: \.data)!
        let source = UnsafeRawPointer(processed).advanced(by: dataOffset).assumingMemoryBound(to: UInt16.self)

        var rgba = Data(count: width * height * 8)
        rgba.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for pixel in 0..<(width * height) {
                out[pixel * 4] = source[pixel * 3]
                out[pixel * 4 + 1] = source[pixel * 3 + 1]
                out[pixel * 4 + 2] = source[pixel * 3 + 2]
                out[pixel * 4 + 3] = .max
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020) else { throw Failure.noMemory }
        let image = CIImage(bitmapData: rgba, bytesPerRow: width * 8, size: CGSize(width: width, height: height),
                            format: .RGBA16, colorSpace: space)
        let make = withUnsafePointer(to: processor.pointee.idata.make) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
        }
        let model = withUnsafePointer(to: processor.pointee.idata.model) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
        }
        let decoded = CGSize(width: width, height: height)
        let framed = framed(image, size: decoded, frame: frame,
                            tables: lensCorrections ? lensTables(camera, frame: frame, file: url.lastPathComponent) : nil)
        return Output(linear: framed.image, step: CameraColorStep(color: color, channelScale: channelScale),
                      rgba16: rgba, size: framed.size,
                      fullSize: framed.fullSize ?? (half ? CGSize(width: width * 2, height: height * 2) : decoded),
                      cameraMake: make, cameraModel: model, hasLensCorrections: framed.corrected)
    }

    /// The camera's lens tables for a decode of `frame`: only for a frame
    /// that is the camera's own (the tables are centered on it), and only
    /// when the file's tables are for that frame (`FujifilmRAF.lensTables`).
    /// A file that has tables which are not used says why in the log.
    static func lensTables(_ camera: FujifilmRAF?, frame: Frame, file: String) -> FujifilmRAF.LensTables? {
        guard let camera, let lens = camera.lens, !lens.isIdentity else { return nil }
        guard frame.window != nil, let cameraFrame = camera.cameraFrame else {
            log.notice("\(file, privacy: .private): the camera's lens corrections are not applied: its frame is not a part of LibRaw's image")
            return nil
        }
        let usable = camera.lensTables(for: cameraFrame)
        if let refusal = usable.refusal {
            log.notice("\(file, privacy: .private): the camera's lens corrections are not applied: \(refusal, privacy: .public)")
        }
        return usable.tables
    }

    /// LibRaw's image cut to `frame` and corrected with `tables`: what a
    /// decode returns for it. For a frame LibRaw cropped itself (or its whole
    /// image) that is the image as it is. For a camera's frame of LibRaw's
    /// image (`Frame.window`) the frame is cut from it, with the camera's lens
    /// corrections when there are tables. A half-size image's frame can start
    /// between two pixels: it is then resampled too, with tables that correct
    /// nothing, so that every size shows the same frame. `fullSize` is the
    /// frame's size at full resolution, nil when the image is not cut.
    static func framed(_ image: CIImage, size: CGSize, frame: Frame, tables: FujifilmRAF.LensTables?)
        -> (image: CIImage, size: CGSize, fullSize: CGSize?, corrected: Bool) {
        guard let window = frame.windowRect(inImageOf: size) else { return (image, size, nil, false) }
        let startsOnPixels = window.minX == window.minX.rounded() && window.minY == window.minY.rounded()
        let correct = tables.map { !$0.isIdentity } ?? false
        if correct || !startsOnPixels,
           let result = EmbeddedLensCorrection(correct ? tables ?? .none : .none, shortSideRadius: Double(
               min(window.width, window.height) / hypot(window.width, window.height))).apply(to: image, frame: window) {
            return (result, result.extent.size, frame.orientedSize, correct)
        }
        // Cut on whole pixels (also when the kernel is not available).
        if correct { log.error("the lens correction kernel is not available: a photo is shown uncorrected") }
        let cut = CGRect(x: window.minX.rounded(.down), y: window.minY.rounded(.down),
                         width: window.width.rounded(), height: window.height.rounded())
        let cropped = image.cropped(to: cut).transformed(by: CGAffineTransform(translationX: -cut.minX, y: -cut.minY))
        return (cropped, cropped.extent.size, frame.orientedSize, false)
    }
}
