import CLibRaw
import CoreImage
import Foundation

/// The decode with our own demosaic (issue #196): LibRaw unpacks, the GPU
/// demosaics (`GPUDemosaic`), and the rest is as for LibRaw's own decode:
/// the crop, the orientation, a Fujifilm RAF's frame and lens corrections,
/// the color step.
extension LibRawDecoder {
    /// Which demosaic a decode may use.
    public enum DemosaicChoice: String, Sendable, Hashable {
        /// Ours, for a pattern our kernels demosaic; LibRaw's otherwise.
        case automatic
        /// LibRaw's own, always: the debug switch (Q6), for comparing.
        case libRaw = "libraw"
    }

    /// Which demosaic made a decode's image.
    public enum Demosaic: Sendable, Hashable, CustomStringConvertible {
        /// Ours, on the GPU, for this kind of pattern.
        case gpu(CFAPattern.Kind)
        /// LibRaw's own, and why.
        case libRaw(reason: String)

        public var description: String {
            switch self {
            case .gpu(let kind): "gpu (\(kind.rawValue))"
            case .libRaw(let reason): "libraw (\(reason))"
            }
        }
    }

    /// The demosaic of a process, set at launch: `--demosaic libraw` (the
    /// apps), or `RAW_DEMOSAIC=libraw` in the environment (every tool and
    /// the tests). Hidden: for comparing, never a user setting (PRD Q6).
    public static let launchDemosaic: DemosaicChoice = {
        let asked = LaunchOptions.current.demosaic ?? ProcessInfo.processInfo.environment["RAW_DEMOSAIC"]
        return asked.flatMap { DemosaicChoice(rawValue: $0.lowercased()) } ?? .automatic
    }()

    /// The demosaic for the work of one task (`photocli render --demosaic`,
    /// tests), over `launchDemosaic`.
    @TaskLocal public static var demosaicOverride: DemosaicChoice?

    static var currentDemosaic: DemosaicChoice { demosaicOverride ?? launchDemosaic }

    /// A decode's pixels before the crop, the orientation and the frame:
    /// red, green, blue and alpha, rows from the top.
    struct Pixels: @unchecked Sendable {
        // @unchecked: the data is immutable once made.
        var width: Int
        var height: Int
        var bytesPerRow: Int
        /// Half floats (ours) or 16-bit integers (LibRaw's), host order.
        var isHalfFloat: Bool
        var data: Data

        /// Every channel of every pixel, four to a pixel, on LibRaw's 16-bit
        /// scale (1 is 65535).
        func samples() -> [Float] {
            var out = [Float](repeating: 0, count: width * height * 4)
            data.withUnsafeBytes { raw in
                for y in 0..<height {
                    for i in 0..<(width * 4) {
                        out[y * width * 4 + i] = isHalfFloat
                            ? Float(raw.load(fromByteOffset: y * bytesPerRow + i * 2, as: Float16.self)) * 65535
                            : Float(raw.load(fromByteOffset: y * bytesPerRow + i * 2, as: UInt16.self))
                    }
                }
            }
            return out
        }
    }

    enum GPUDecode {
        case decoded(Output)
        /// The file is not for our kernels, and why: LibRaw's own demosaic.
        case unsupported(String)
    }

    /// The decode with our demosaic, or why the file needs LibRaw's.
    /// Throws `GPUDemosaic.Failure` when the GPU work fails (the caller
    /// then uses LibRaw's demosaic, R19), `CancellationError` when the task
    /// was cancelled between the unpack and the GPU work (R21), and LibRaw's
    /// own failures to open or unpack the file.
    static func decodeOnGPU(_ url: URL, halfSize: Bool, longEdge: Int?, lensCorrections: Bool) throws -> GPUDecode {
        guard let processor = libraw_init(0) else { throw Failure.noMemory }
        defer { libraw_close(processor) }
        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("open", code: code) }
        let opened = processor.pointee.sizes
        guard !isTooLarge(rawWidth: Int(opened.raw_width), rawHeight: Int(opened.raw_height)) else {
            throw Failure.tooLarge(megapixels: Int(opened.raw_width) * Int(opened.raw_height) / 1_000_000)
        }
        // A file without usable color data is rendered by LibRaw itself, in the working space.
        guard let color = cameraColor(of: processor) else { return .unsupported("no usable camera color data") }
        let pattern: CFAPattern
        switch SensorMosaic.pattern(of: processor) {
        case .success(let found): pattern = found
        case .failure(let why): return .unsupported(why.description)
        }
        let (frame, camera) = frame(of: processor, url: url)
        let half = halfSize || usesHalfSize(longEdge: longEdge, frameLongEdge: frame.longEdge)
        let multipliers = color.asShotNeutral.min() / color.asShotNeutral
        let make = withUnsafePointer(to: processor.pointee.idata.make) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
        }
        let model = withUnsafePointer(to: processor.pointee.idata.model) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
        }
        let exposure = fileExposure(of: processor)

        code = libraw_unpack(processor)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("unpack", code: code) }
        try Task.checkCancellation()
        let mosaic: SensorMosaic
        do {
            mosaic = try SensorMosaic.unpacked(processor, pattern: pattern, multipliers: multipliers)
        } catch let why as SensorMosaic.Unsupported {
            return .unsupported(why.description)
        }
        // LibRaw's buffers go before the GPU's are made (R21).
        libraw_recycle(processor)
        try Task.checkCancellation()

        let demosaiced = try GPUDemosaic.shared().run(mosaic, halfSize: half)
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020) else { throw Failure.noMemory }
        let decodedSize = CGSize(width: demosaiced.width, height: demosaiced.height)
        let data = demosaiced.data
        var image = CIImage(bitmapData: data, bytesPerRow: demosaiced.bytesPerRow, size: decodedSize,
                            format: .RGBAh, colorSpace: space)
        // LibRaw's crop box, which its own decode crops to before demosaicing: here cut afterwards, so its
        // edge pixels have their neighbours.
        if let box = frame.cropBox {
            let scale = half ? 0.5 : 1.0
            let left = (Double(box.left) * scale).rounded(.down), top = (Double(box.top) * scale).rounded(.down)
            let width = min((Double(box.width) * scale).rounded(.down), decodedSize.width - left)
            let height = min((Double(box.height) * scale).rounded(.down), decodedSize.height - top)
            let rect = CGRect(x: left, y: decodedSize.height - top - height, width: width, height: height)
            image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        image = oriented(image, flip: frame.flip)
        let size = image.extent.size
        let framed = framed(image, size: size, frame: frame,
                            tables: lensCorrections ? lensTables(camera, frame: frame, file: url.lastPathComponent) : nil)
        let step = CameraColorStep(color: color, channelScale: SIMD3<Double>(multipliers) * whiteMargin, fileExposure: exposure)
        let pixels = Pixels(width: demosaiced.width, height: demosaiced.height, bytesPerRow: demosaiced.bytesPerRow,
                            isHalfFloat: true, data: data)
        let full = half ? CGSize(width: size.width * 2, height: size.height * 2) : size
        return .decoded(Output(linear: framed.image, step: step, pixels: pixels, demosaic: .gpu(pattern.kind),
                               size: framed.size, fullSize: framed.fullSize ?? full,
                               cameraMake: make, cameraModel: model, hasLensCorrections: framed.corrected))
    }

    /// The image (the sensor's rows and columns, extent at the origin)
    /// oriented as LibRaw orients its own: columns mirrored when bit 1 of
    /// `flip` is set, rows when bit 2 is, then rows and columns swapped when
    /// bit 4 is (`Frame.windowRect` reads the frame the same way). Only
    /// whole-pixel moves, so no pixel is resampled.
    static func oriented(_ image: CIImage, flip: Int) -> CIImage {
        var result = image
        var width = image.extent.width, height = image.extent.height
        // In Core Image's coordinates (y up): mirroring columns is x → W − x, rows y → H − y.
        if flip & 1 != 0 { result = result.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)) }
        if flip & 2 != 0 { result = result.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)) }
        if flip & 4 != 0 {
            // Row r becomes column r, column c row c: (x, y) → (H − y, W − x).
            result = result.transformed(by: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width))
            swap(&width, &height)
        }
        return result
    }
}

extension LibRawDecoder {
    /// The file's sensor values, unpacked by LibRaw with the multipliers a
    /// decode uses, for measuring the kernels on real files (`photobench
    /// demosaic`, tests). Throws `SensorMosaic.Unsupported` for a file our
    /// kernels do not demosaic.
    public static func sensorMosaic(_ url: URL) throws -> SensorMosaic {
        guard let processor = libraw_init(0) else { throw Failure.noMemory }
        defer { libraw_close(processor) }
        var code = libraw_open_file(processor, url.path)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("open", code: code) }
        guard let color = cameraColor(of: processor) else { throw SensorMosaic.Unsupported.noSensorData }
        let pattern = try SensorMosaic.pattern(of: processor).get()
        code = libraw_unpack(processor)
        guard code == LIBRAW_SUCCESS.rawValue else { throw Failure.libraw("unpack", code: code) }
        return try SensorMosaic.unpacked(processor, pattern: pattern,
                                         multipliers: color.asShotNeutral.min() / color.asShotNeutral)
    }
}
