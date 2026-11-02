import Foundation

/// The four appearances the palette has values for.
public enum PaletteAppearance: CaseIterable, Hashable, Sendable {
    case dark, darkContrast, light, lightContrast

    public var increasesContrast: Bool { self == .darkContrast || self == .lightContrast }
    public var isDark: Bool { self == .dark || self == .darkContrast }
}

/// An sRGB color with alpha.
public struct PaletteColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static func gray(_ white: Double, alpha: Double = 1) -> PaletteColor {
        PaletteColor(white, white, white, alpha: alpha)
    }

    public var isNeutral: Bool { red == green && green == blue }

    /// This color laid over an opaque `background`.
    public func over(_ background: PaletteColor) -> PaletteColor {
        PaletteColor(red * alpha + background.red * (1 - alpha), green * alpha + background.green * (1 - alpha),
                     blue * alpha + background.blue * (1 - alpha))
    }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio of two opaque colors, 1 … 21.
    public func contrast(with other: PaletteColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The values of the app's palette (`Palette` in PhotoUI builds dynamic
/// colors from them), kept as data so `PaletteContrastTests` can check every
/// pair against the WCAG ratios in all four appearances (section 10 of
/// docs/UI_REDESIGN.md). Grays are neutral so photos are judged against a
/// surround that does not tint them.
public enum PaletteSpec {
    public enum Role: CaseIterable, Hashable, Sendable {
        case gridBackground, loupeBackground, cell, cellSelected
        case fileName, badgeText, dateText, badgeFill, rawBadgeFill
        case rating, pick, reject
    }

    public static func color(_ role: Role, in appearance: PaletteAppearance) -> PaletteColor {
        let (dark, darkContrast, light, lightContrast) = values(role)
        return switch appearance {
        case .dark: dark
        case .darkContrast: darkContrast
        case .light: light
        case .lightContrast: lightContrast
        }
    }

    /// The selected cell's accent border: 3 pt with Increase Contrast.
    public static func selectedBorderWidth(in appearance: PaletteAppearance) -> Double {
        appearance.increasesContrast ? 3 : 2
    }

    private typealias Values = (PaletteColor, PaletteColor, PaletteColor, PaletteColor)

    private static func gray(_ dark: Double, _ darkContrast: Double, _ light: Double, _ lightContrast: Double) -> Values {
        (.gray(dark), .gray(darkContrast), .gray(light), .gray(lightContrast))
    }

    private static func values(_ role: Role) -> Values {
        switch role {
        case .gridBackground: gray(0.12, 0.04, 0.93, 1)
        // The color-judgment surround: dark in every appearance.
        case .loupeBackground: gray(0.09, 0.09, 0.09, 0.09)
        case .cell: gray(0.17, 0.12, 0.86, 0.90)
        case .cellSelected: gray(0.27, 0.22, 0.76, 0.80)
        case .fileName: gray(0.80, 0.97, 0.20, 0)
        case .badgeText: gray(0.92, 1, 0.12, 0)
        case .dateText: gray(0.70, 0.92, 0.30, 0.10)
        case .badgeFill: (.gray(1, alpha: 0.10), .gray(1, alpha: 0.08), .gray(0, alpha: 0.08), .gray(0, alpha: 0.06))
        case .rawBadgeFill:
            (PaletteColor(0.95, 0.70, 0.30, alpha: 0.22), PaletteColor(0.95, 0.70, 0.30, alpha: 0.12),
             PaletteColor(0.95, 0.60, 0.10, alpha: 0.25), PaletteColor(0.95, 0.60, 0.10, alpha: 0.18))
        case .rating:
            (PaletteColor(0.98, 0.82, 0.35), PaletteColor(1, 0.85, 0.30),
             PaletteColor(0.55, 0.35, 0), PaletteColor(0.45, 0.28, 0))
        case .pick:
            (PaletteColor(0.45, 0.85, 0.50), PaletteColor(0.50, 0.95, 0.55),
             PaletteColor(0.10, 0.45, 0.18), PaletteColor(0, 0.33, 0.10))
        case .reject:
            (PaletteColor(0.98, 0.48, 0.42), PaletteColor(1, 0.55, 0.50),
             PaletteColor(0.70, 0.15, 0.10), PaletteColor(0.55, 0.08, 0.04))
        }
    }
}
