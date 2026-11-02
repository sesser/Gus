import AppKit
import PhotoCore

/// Neutral grays so photos are judged against a background that does not
/// tint them. Every color is dynamic: the library window is always dark, the
/// import window follows the system, and Increase Contrast gets stronger
/// variants (section 10 of docs/UI_REDESIGN.md). Layers must resolve them
/// against their view's appearance (`resolved(for:)`).
public enum Palette {
    public static let gridBackground = gray(dark: 0.12, darkContrast: 0.04, light: 0.93, lightContrast: 1)
    public static let loupeBackground = gray(dark: 0.09, darkContrast: 0, light: 0.86, lightContrast: 0.95)
    public static let cell = gray(dark: 0.17, darkContrast: 0.16, light: 0.86, lightContrast: 0.82)
    public static let cellSelected = gray(dark: 0.27, darkContrast: 0.36, light: 0.76, lightContrast: 0.66)
    public static let fileName = gray(dark: 0.78, darkContrast: 0.96, light: 0.25, lightContrast: 0.05)
    public static let badgeText = gray(dark: 0.86, darkContrast: 1, light: 0.2, lightContrast: 0)
    public static let badgeFill = dynamic(dark: NSColor(white: 1, alpha: 0.13), darkContrast: NSColor(white: 1, alpha: 0.28),
                                          light: NSColor(white: 0, alpha: 0.08), lightContrast: NSColor(white: 0, alpha: 0.2))
    public static let rawBadgeFill = dynamic(
        dark: NSColor(srgbRed: 0.95, green: 0.7, blue: 0.3, alpha: 0.3),
        darkContrast: NSColor(srgbRed: 0.95, green: 0.7, blue: 0.3, alpha: 0.5),
        light: NSColor(srgbRed: 0.95, green: 0.6, blue: 0.1, alpha: 0.25),
        lightContrast: NSColor(srgbRed: 0.9, green: 0.5, blue: 0, alpha: 0.4))
    public static let rating = dynamic(dark: NSColor(srgbRed: 0.98, green: 0.82, blue: 0.35, alpha: 1),
                                       darkContrast: NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1),
                                       light: NSColor(srgbRed: 0.85, green: 0.6, blue: 0, alpha: 1),
                                       lightContrast: NSColor(srgbRed: 0.7, green: 0.45, blue: 0, alpha: 1))
    public static let pick = dynamic(dark: NSColor(srgbRed: 0.45, green: 0.85, blue: 0.5, alpha: 1),
                                     darkContrast: NSColor(srgbRed: 0.5, green: 0.95, blue: 0.55, alpha: 1),
                                     light: NSColor(srgbRed: 0.15, green: 0.6, blue: 0.25, alpha: 1),
                                     lightContrast: NSColor(srgbRed: 0.05, green: 0.45, blue: 0.15, alpha: 1))
    public static let reject = dynamic(dark: NSColor(srgbRed: 0.95, green: 0.4, blue: 0.35, alpha: 1),
                                       darkContrast: NSColor(srgbRed: 1, green: 0.45, blue: 0.4, alpha: 1),
                                       light: NSColor(srgbRed: 0.8, green: 0.2, blue: 0.15, alpha: 1),
                                       lightContrast: NSColor(srgbRed: 0.65, green: 0.1, blue: 0.05, alpha: 1))

    /// A color by appearance: dark or light, with or without Increase Contrast.
    public static func dynamic(dark: NSColor, darkContrast: NSColor, light: NSColor, lightContrast: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua,
                                               .accessibilityHighContrastAqua]) {
            case .accessibilityHighContrastDarkAqua: darkContrast
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: lightContrast
            default: light
            }
        }
    }

    static func gray(dark: CGFloat, darkContrast: CGFloat, light: CGFloat, lightContrast: CGFloat) -> NSColor {
        dynamic(dark: NSColor(white: dark, alpha: 1), darkContrast: NSColor(white: darkContrast, alpha: 1),
                light: NSColor(white: light, alpha: 1), lightContrast: NSColor(white: lightContrast, alpha: 1))
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
