import CLibRaw
import CoreImage
import Foundation

/// Decodes a raw file with the vendored LibRaw (LGPL 2.1, `THIRD_PARTY_NOTICES.md`),
/// for raws the system's RAW decoder gives no image for (issue #161;
/// `PreviewGenerator.decode` falls back to it) and for comparing the two
/// decoders (`photobench rawcompare`).
///
/// It demosaics to linear Rec. 2020 with the camera's white balance, no
/// automatic brightening and no tone curve, oriented, 16 bits a channel, and
/// crops to the frame the file records (`Frame`). It takes none of the stack's
/// decode settings: its image is a rendered image, like a JPEG's
/// (`SystemRAWDecoder`).
///
/// LibRaw's defaults are otherwise kept. One of them makes a decode's level
/// depend on its content: when the brightest value in the frame is over three
/// quarters of the file's white level, that value becomes white
/// (`adjust_maximum_thr`, against color casts in clipped highlights).
///
/// Each call has a LibRaw instance of its own and LibRaw is built thread-safe
/// (without `LIBRAW_NOTHREADS`), so decodes may run at the same time.
public enum LibRawDecoder {
    public struct Output {
        public var image: CIImage
        /// The image's pixels: red, green, blue and alpha, 16 bits each in host
        /// order, rows from the top. The image reads the same bytes.
        var rgba16: Data
        /// The decode's size in pixels (half the frame's with `halfSize`).
        public var size: CGSize
        /// The frame's size at full resolution.
        public var fullSize: CGSize
        public var cameraMake: String
        public var cameraModel: String
    }

    public enum Failure: Error, CustomStringConvertible {
        case libraw(String, code: Int32)
        case noMemory

        public var description: String {
            switch self {
            case .libraw(let step, let code): "LibRaw \(step): \(String(cString: libraw_strerror(code))) (\(code))"
            case .noMemory: "LibRaw could not allocate"
            }
        }
    }

    /// The part of the sensor a decode keeps, from the file's header.
    ///
    /// LibRaw's visible area includes pixels the camera leaves out of its own
    /// pictures (6032x4028 on a Fujifilm X-E3); the file's first inset crop is
    /// the camera's frame, as LibRaw reads it (5998x3997 there, where the
    /// camera's JPEG is 6000x4000). Files without one keep the visible area.
    /// The second inset crop (a 16:9 or 1:1 picture's) is not read.
    struct Frame {
        /// In sensor pixels, before the orientation.
        var width: Int
        var height: Int
        /// LibRaw's crop box for the frame (left, top, width, height in the
        /// visible area), nil for the whole visible area.
        var cropBox: (left: UInt32, top: UInt32, width: UInt32, height: UInt32)?
        /// The file's orientation turns the picture a quarter (LibRaw's flip 5 and 6).
        var isTurned: Bool

        var longEdge: Int { max(width, height) }

        /// The frame as it is shown.
        var orientedSize: CGSize {
            isTurned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }

        init(_ sizes: libraw_image_sizes_t) {
            let inset = sizes.raw_inset_crops.0
            self.init(visibleWidth: Int(sizes.width), visibleHeight: Int(sizes.height),
                      leftMargin: Int(sizes.left_margin), topMargin: Int(sizes.top_margin),
                      insetLeft: Int(inset.cleft), insetTop: Int(inset.ctop),
                      insetWidth: Int(inset.cwidth), insetHeight: Int(inset.cheight), flip: Int(sizes.flip))
        }

        /// LibRaw's sizes: the visible area and its margins on the sensor, and
        /// the inset crop in sensor coordinates (an unset one has no size, and
        /// its origin is 0xffff). An inset that starts before the visible
        /// area is not a crop of it and is left out.
        init(visibleWidth: Int, visibleHeight: Int, leftMargin: Int, topMargin: Int,
             insetLeft: Int, insetTop: Int, insetWidth: Int, insetHeight: Int, flip: Int) {
            if insetWidth > 0, insetHeight > 0, insetLeft >= leftMargin, insetTop >= topMargin,
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
            isTurned = flip == 5 || flip == 6
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
        let frame = Frame(processor.pointee.sizes)
        return frame.width > 0 && frame.height > 0 ? frame.orientedSize : nil
    }

    /// The raw's decode. `halfSize` asks for a binned decode whatever the
    /// target; otherwise `longEdge` decides (`usesHalfSize`).
    public static func decode(_ url: URL, halfSize: Bool = false, longEdge: Int? = nil) throws -> Output {
        guard let processor = libraw_init(0) else { throw Failure.noMemory }
        defer { libraw_close(processor) }
        libraw_set_output_bps(processor, 16)
        // Rec. 2020 primaries, linear (gamma 1/1), as the working space.
        libraw_set_output_color(processor, 8)
        libraw_set_gamma(processor, 0, 1)
        libraw_set_gamma(processor, 1, 1)
        libraw_set_no_auto_bright(processor, 1)
        processor.pointee.params.use_camera_wb = 1

        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("open", code: code) }
        let frame = Frame(processor.pointee.sizes)
        if let box = frame.cropBox {
            processor.pointee.params.cropbox = (box.left, box.top, box.width, box.height)
        }
        let half = halfSize || usesHalfSize(longEdge: longEdge, frameLongEdge: frame.longEdge)
        processor.pointee.params.half_size = half ? 1 : 0
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
        let size = CGSize(width: width, height: height)
        return Output(image: image, rgba16: rgba, size: size,
                      fullSize: half ? CGSize(width: width * 2, height: height * 2) : size,
                      cameraMake: make, cameraModel: model)
    }
}
