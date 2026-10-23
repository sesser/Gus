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

    // Values another app (or the camera) stored in the file. They seed the
    // default version at import; the catalog does not keep them on `image`.

    /// IPTC Keywords and XMP dc:subject, de-duplicated ignoring case.
    public var keywords: [String] = []
    /// XMP rating: 1–5 stars, 0 unrated, -1 rejected.
    public var rating: Int?
    /// XMP label, usually a color name.
    public var label: String?

    public init(captureDate: Date? = nil, captureOffsetSeconds: Int? = nil,
                pixelWidth: Int? = nil, pixelHeight: Int? = nil, orientation: Int = 1,
                cameraMake: String? = nil, cameraModel: String? = nil, lensModel: String? = nil,
                iso: Int? = nil, exposureTime: Double? = nil, fNumber: Double? = nil,
                focalLength: Double? = nil, keywords: [String] = [], rating: Int? = nil, label: String? = nil) {
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
        self.keywords = ImageMetadata.uniqueKeywords(keywords)
        self.rating = rating.map { min(max($0, -1), 5) }
        self.label = label?.trimmedNonEmpty
    }

    public static let empty = ImageMetadata()
}

extension ImageMetadata {
    /// Keeps the first spelling of each keyword, ignoring case and blanks.
    public static func uniqueKeywords(_ keywords: [String]) -> [String] {
        var seen: Set<String> = []
        return keywords.compactMap { keyword in
            guard let name = Catalog.normalizedKeywordName(keyword), seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    /// The culling values the file asks for.
    var embeddedCulling: (rating: Rating, flag: Flag, label: ColorLabel) {
        let rating = self.rating ?? 0
        return (Rating(clamping: max(rating, 0)), rating < 0 ? .rejected : .none,
                label.flatMap(ColorLabel.init(xmpName:)) ?? .none)
    }

    /// Orientations 5–8 swap width and height.
    public static func swapsDimensions(_ orientation: Int) -> Bool {
        (5...8).contains(orientation)
    }
}
