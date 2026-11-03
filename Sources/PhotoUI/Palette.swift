import AppKit
import PhotoCore

/// The app's colors, dynamic by appearance: the library window is always
/// dark, the import window follows the system, and Increase Contrast has its
/// own values. The values are `PaletteSpec`'s (PhotoCore), where
/// `PaletteContrastTests` checks them. Layers must resolve them against their
/// view's appearance (`resolved(for:)`).
public enum Palette {
    public static let gridBackground = color(.gridBackground)
    public static let loupeBackground = color(.loupeBackground)
    public static let cell = color(.cell)
    public static let cellSelected = color(.cellSelected)
    public static let fileName = color(.fileName)
    public static let badgeText = color(.badgeText)
    /// The import window's date line.
    public static let dateText = color(.dateText)
    public static let badgeFill = color(.badgeFill)
    public static let rawBadgeFill = color(.rawBadgeFill)
    public static let rating = color(.rating)
    public static let pick = color(.pick)
    public static let reject = color(.reject)

    private static func color(_ role: PaletteSpec.Role) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = PaletteSpec.color(role, in: PaletteAppearance(appearance))
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        }
    }

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

extension NSColor {
    /// The color as `appearance` shows it, for layers (whose colors do not
    /// follow the appearance by themselves).
    @MainActor
    public func resolved(for appearance: NSAppearance) -> NSColor {
        var color = self
        appearance.performAsCurrentDrawingAppearance {
            color = self.usingColorSpace(.sRGB) ?? self
        }
        return color
    }
}

extension PaletteAppearance {
    /// Which of the palette's four appearances `appearance` is.
    public init(_ appearance: NSAppearance) {
        switch appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua,
                                           .accessibilityHighContrastAqua]) {
        case .accessibilityHighContrastDarkAqua: self = .darkContrast
        case .darkAqua: self = .dark
        case .accessibilityHighContrastAqua: self = .lightContrast
        default: self = .light
        }
    }
}
