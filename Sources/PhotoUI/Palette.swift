import AppKit
import PhotoCore

/// Neutral grays so photos are judged against a background that does not tint them.
public enum Palette {
    public static let gridBackground = NSColor(white: 0.12, alpha: 1)
    public static let loupeBackground = NSColor(white: 0.09, alpha: 1)
    public static let cell = NSColor(white: 0.17, alpha: 1)
    public static let cellSelected = NSColor(white: 0.27, alpha: 1)
    public static let rating = NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.35, alpha: 1)
    public static let fileName = NSColor(white: 0.78, alpha: 1)
    public static let badgeText = NSColor(white: 0.86, alpha: 1)
    public static let badgeFill = NSColor(white: 1, alpha: 0.13)
    public static let rawBadgeFill = NSColor(calibratedRed: 0.95, green: 0.7, blue: 0.3, alpha: 0.3)
    public static let pick = NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.5, alpha: 1)
    public static let reject = NSColor(calibratedRed: 0.95, green: 0.4, blue: 0.35, alpha: 1)

    public static func color(for label: ColorLabel) -> NSColor? {
        switch label {
        case .none: nil
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }
}

/// Badge text for file types. The abbreviations are conventional, but they go
/// through the String Catalog like every other UI string.
public enum FileKindText {
    public static func badge(_ kind: FileKind) -> String {
        switch kind {
        case .raw: String(localized: "RAW", comment: "Grid badge: camera raw file")
        case .jpeg: String(localized: "JPEG", comment: "Grid badge: JPEG file")
        case .heic: String(localized: "HEIC", comment: "Grid badge: HEIC or HEIF file")
        case .tiff: String(localized: "TIFF", comment: "Grid badge: TIFF file")
        case .png: String(localized: "PNG", comment: "Grid badge: PNG file")
        case .video: String(localized: "VIDEO", comment: "Grid badge: video file")
        }
    }

    /// "0:42", "1:05:09".
    public static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// A grouped pair shows both types, the one on screen first ("RAW+JPEG").
    public static func badge(for item: CatalogItem) -> String? {
        guard let kind = item.fileKind else { return nil }
        // A video's length says more than its type.
        if kind == .video, let seconds = item.duration { return "▶ " + duration(seconds) }
        guard item.representsPair, let partner = item.partnerKind else { return badge(kind) }
        return String(localized: "\(badge(kind))+\(badge(partner))",
                      comment: "Grid badge for a RAW+JPEG pair; the first type is the file shown")
    }
}
