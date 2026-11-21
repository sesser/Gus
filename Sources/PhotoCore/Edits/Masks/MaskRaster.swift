import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One stored detection result (issue #88, R5): Vision's all-instances soft
/// mask quantized to 8 bits, as an 8-bit gray PNG, kept in the catalog's
/// `maskRaster` table and named by the SHA-256 of those bytes (`digest`).
///
/// The raster keeps its own width and height (Vision's model decides them:
/// 512 x 512 for Subject, 512 x 384 or 384 x 512 for People) and is stretched
/// over the mask frame in unit coordinates (R7). Rows are written once and
/// never updated; a new detection writes a new row. An empty result (nothing
/// found) is a stored result too: one black pixel with zero instances, so it
/// survives closing the library and stays different from a missing row
/// (design §6).
public struct MaskRaster: Sendable, Hashable {
    /// The Vision request a result came from.
    public enum Request: String, Sendable, CaseIterable {
        /// `VNGenerateForegroundInstanceMaskRequest`: Subject and Background.
        case foreground
        /// `VNGeneratePersonInstanceMaskRequest`: People.
        case person
    }

    /// Lowercase hexadecimal SHA-256 of `png`.
    public let digest: String
    public let png: Data
    public let width: Int
    public let height: Int
    /// How many instances the result holds; 0 for an empty result.
    public let instances: Int
    /// Provenance, for diagnosis only: nothing reads them to render.
    public let request: Request
    public let revision: Int
    public let systemVersion: String

    /// The stored encoding (`maskRaster.encoding`).
    public static let encoding = "png-gray8"
    /// The largest side written or read: Vision's masks are 512 pixels. A
    /// row over it is damaged; a crafted one can't make the renderer hold
    /// gigabytes (security review L1).
    public static let maximumSide = 1024
    /// The most bytes a stored row's PNG may hold to be read at all: a
    /// 1024 x 1024 gray PNG, even incompressible, fits.
    public static let maximumStoredBytes = 2 * 1024 * 1024

    /// Encodes `levels` (row-major, top row first, 0 … 255).
    public init(levels: [UInt8], width: Int, height: Int, instances: Int, request: Request, revision: Int = 1,
                systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) throws(Failure) {
        guard width > 0, height > 0, width <= Self.maximumSide, height <= Self.maximumSide,
              levels.count == width * height else { throw .invalidSize }
        guard let png = Self.encodePNG(levels, width: width, height: height) else { throw .encodingFailed }
        self.init(stored: png, width: width, height: height, instances: instances, request: request,
                  revision: revision, systemVersion: systemVersion)
    }

    /// A row as stored; `digest` is computed from the bytes.
    init(stored png: Data, width: Int, height: Int, instances: Int, request: Request, revision: Int,
         systemVersion: String) {
        self.png = png
        digest = Digest.sha256Hex(png)
        self.width = width
        self.height = height
        self.instances = max(instances, 0)
        self.request = request
        self.revision = revision
        self.systemVersion = systemVersion
    }

    /// The stored result of a detection that found nothing.
    public static func empty(_ request: Request, revision: Int = 1) -> MaskRaster {
        // One pixel always encodes.
        (try? MaskRaster(levels: [0], width: 1, height: 1, instances: 0, request: request, revision: revision))!
    }

    public enum Failure: Error, Equatable, Sendable {
        case invalidSize
        case encodingFailed
        /// The bytes are not an 8-bit gray PNG of a size this build reads.
        case unreadable
    }

    /// A digest as the stack and the table hold it.
    public static func isDigest(_ text: String) -> Bool {
        text.count == 64 && PreviewCacheKey.isHex(text)
    }

    // MARK: Pixels

    /// The levels of a stored PNG. Accepts exactly what `init` writes (8-bit
    /// gray, no alpha) at most `maximumSide` on a side: anything else is
    /// damaged, and selects nothing (design §6, "missing or damaged").
    public static func pixels(fromPNG data: Data) throws(Failure) -> Pixels {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.bitsPerComponent == 8, image.bitsPerPixel == 8,
              image.colorSpace?.model == .monochrome, image.alphaInfo == .none,
              image.width > 0, image.height > 0, image.width <= maximumSide, image.height <= maximumSide,
              let bytes = image.dataProvider?.data as Data?, bytes.count >= image.bytesPerRow * (image.height - 1) + image.width
        else { throw .unreadable }
        var levels = [UInt8](repeating: 0, count: image.width * image.height)
        bytes.withUnsafeBytes { raw in
            for y in 0..<image.height {
                let row = raw.baseAddress!.advanced(by: y * image.bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<image.width { levels[y * image.width + x] = row[x] }
            }
        }
        return Pixels(width: image.width, height: image.height, levels: levels)
    }

    /// The decoded levels of a stored result.
    public struct Pixels: Sendable, Hashable {
        public let width: Int
        public let height: Int
        /// Row-major, top row first.
        public let levels: [UInt8]

        public init(width: Int, height: Int, levels: [UInt8]) {
            self.width = width
            self.height = height
            self.levels = levels
        }
    }

    static func encodePNG(_ levels: [UInt8], width: Int, height: Int) -> Data? {
        guard let provider = CGDataProvider(data: Data(levels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
