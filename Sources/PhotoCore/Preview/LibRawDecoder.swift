import CLibRaw
import CoreImage
import Foundation

/// Decodes a raw file with the vendored LibRaw (CDDL), for raws the system's
/// RAW decoder cannot read (issue #161) and for comparing the two decoders.
///
/// A spike: it demosaics to linear Rec. 2020 (camera white balance, no
/// automatic brightening, no tone curve), oriented, 16 bits a channel. It
/// applies none of the stack's decode settings.
public enum LibRawDecoder {
    public struct Output {
        public var image: CIImage
        /// The decode's size in pixels (half the sensor's with `halfSize`).
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

    /// The raw's decode. `halfSize` demosaics by binning each 2x2 block, which
    /// is much faster and enough for a target of half the sensor or less.
    public static func decode(_ url: URL, halfSize: Bool = false, longEdge: Int? = nil) throws -> Output {
        guard let processor = libraw_init(0) else { throw Failure.noMemory }
        defer { libraw_close(processor) }
        libraw_set_output_bps(processor, 16)
        libraw_set_output_color(processor, 8)
        libraw_set_gamma(processor, 0, 1)
        libraw_set_gamma(processor, 1, 1)
        libraw_set_no_auto_bright(processor, 1)
        processor.pointee.params.use_camera_wb = 1

        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("open", code: code) }
        // The frame the camera records (a Fujifilm's 6000x4000 inside the 6032x4028
        // LibRaw would otherwise keep), in the coordinates of the visible area.
        let inset = processor.pointee.sizes.raw_inset_crops.0
        let sizes = processor.pointee.sizes
        if inset.cwidth > 0, inset.cheight > 0, inset.cleft >= sizes.left_margin, inset.ctop >= sizes.top_margin {
            processor.pointee.params.cropbox = (UInt32(inset.cleft - sizes.left_margin),
                                                UInt32(inset.ctop - sizes.top_margin),
                                                UInt32(inset.cwidth), UInt32(inset.cheight))
        }
        // Half size too when the target is at most half the frame's long edge.
        let frameEdge = inset.cwidth > 0 ? max(inset.cwidth, inset.cheight) : max(sizes.width, sizes.height)
        let half = halfSize || longEdge.map { $0 * 2 <= Int(frameEdge) } == true
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
        guard processed.pointee.bits == 16, colors == 3 else { throw Failure.libraw("unexpected format", code: -1) }
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
        return Output(image: image, size: size, fullSize: half ? CGSize(width: width * 2, height: height * 2) : size, cameraMake: make, cameraModel: model)
    }
}
