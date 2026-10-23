import Foundation

/// The subset of a master's embedded metadata the catalog keeps in columns.
public struct ImageMetadata: Hashable, Sendable, Codable {
    /// Capture instant. When the file has no time zone offset, the local wall-clock
    /// time is stored as if it were UTC and `captureOffsetSeconds` is nil.
    public var captureDate: Date?
    public var captureOffsetSeconds: Int?
    /// Pixel size of the decoded image before orientation is applied.
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// EXIF orientation, 1 through 8.
    public var orientation: Int
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var iso: Int?
    /// Seconds.
    public var exposureTime: Double?
    public var fNumber: Double?
    /// Millimetres.
    public var focalLength: Double?

    public init(captureDate: Date? = nil, captureOffsetSeconds: Int? = nil,
                pixelWidth: Int? = nil, pixelHeight: Int? = nil, orientation: Int = 1,
                cameraMake: String? = nil, cameraModel: String? = nil, lensModel: String? = nil,
                iso: Int? = nil, exposureTime: Double? = nil, fNumber: Double? = nil,
                focalLength: Double? = nil) {
        self.captureDate = captureDate
        self.captureOffsetSeconds = captureOffsetSeconds
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.orientation = (1...8).contains(orientation) ? orientation : 1
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.iso = iso
        self.exposureTime = exposureTime
        self.fNumber = fNumber
        self.focalLength = focalLength
    }

    public static let empty = ImageMetadata()
}

extension ImageMetadata {
    /// Orientations 5–8 swap width and height.
    public static func swapsDimensions(_ orientation: Int) -> Bool {
        (5...8).contains(orientation)
    }
}
