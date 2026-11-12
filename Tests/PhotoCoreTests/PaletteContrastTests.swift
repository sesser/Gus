import AppKit
import Testing
@testable import PhotoCore

/// Every pair the palette draws, resolved in all four appearances, against
/// the WCAG ratios (section 10 of docs/UI_REDESIGN.md).
@Suite("Palette contrast")
struct PaletteContrastTests {
    private func color(_ role: PaletteSpec.Role, _ appearance: PaletteAppearance) -> PaletteColor {
        PaletteSpec.color(role, in: appearance)
    }

    /// A cell's fill in each of its states.
    private func cellSurfaces(_ appearance: PaletteAppearance) -> [(String, PaletteColor)] {
        [("cell", color(.cell, appearance)), ("selected cell", color(.cellSelected, appearance))]
    }

    @Test(arguments: PaletteAppearance.allCases)
    func textReadsOnItsSurfaces(_ appearance: PaletteAppearance) {
        let needed = appearance.increasesContrast ? 7.0 : 4.5
        for (name, surface) in cellSurfaces(appearance) {
            let fileName = color(.fileName, appearance).contrast(with: surface)
            #expect(fileName >= needed, "file name on \(name) in \(appearance): \(fileName)")
            for fill in [PaletteSpec.Role.badgeFill, .rawBadgeFill] {
                let badge = color(fill, appearance).over(surface)
                let ratio = color(.badgeText, appearance).contrast(with: badge)
                #expect(ratio >= needed, "badge text on \(fill) over \(name) in \(appearance): \(ratio)")
            }
        }
        // The import window's date line: on its tile or the grid around it.
        for (name, surface) in cellSurfaces(appearance) + [("grid", color(.gridBackground, appearance))] {
            let ratio = color(.dateText, appearance).contrast(with: surface)
            #expect(ratio >= needed, "date on \(name) in \(appearance): \(ratio)")
        }
    }

    @Test(arguments: PaletteAppearance.allCases)
    func cullingMarksStandOut(_ appearance: PaletteAppearance) {
        let needed = appearance.increasesContrast ? 4.5 : 3.0
        for mark in [PaletteSpec.Role.rating, .pick, .reject] {
            for (name, surface) in cellSurfaces(appearance) {
                let ratio = color(mark, appearance).contrast(with: surface)
                #expect(ratio >= needed, "\(mark) on \(name) in \(appearance): \(ratio)")
            }
        }
    }

    /// The film strip's marks sit on a black backing over the thumbnail, so
    /// they are checked over the extremes the photo can be: white and black.
    /// Only the dark appearances: the strip is in the library window, which
    /// is always dark (decision 8).
    @Test(arguments: [PaletteAppearance.dark, .darkContrast])
    func filmStripMarksReadOnTheirBacking(_ appearance: PaletteAppearance) {
        let needed = appearance.increasesContrast ? 4.5 : 3.0
        let white = PaletteColor.gray(1)
        for (name, image) in [("white", PaletteColor.gray(1)), ("black", PaletteColor.gray(0))] {
            let backing = PaletteSpec.filmStripMarkBacking.over(image)
            let glyph = white.contrast(with: backing)
            #expect(glyph >= needed, "white glyph on the backing over \(name) in \(appearance): \(glyph)")
            for mark in [PaletteSpec.Role.pick, .reject] {
                let ratio = color(mark, appearance).contrast(with: backing)
                #expect(ratio >= needed, "\(mark) on the backing over \(name) in \(appearance): \(ratio)")
            }
        }
    }

    @Test func graysAreNeutral() {
        let grays: [PaletteSpec.Role] = [.gridBackground, .loupeBackground, .cell, .cellSelected, .fileName, .badgeText,
                                         .dateText, .badgeFill]
        for role in grays {
            for appearance in PaletteAppearance.allCases {
                #expect(color(role, appearance).isNeutral, "\(role) in \(appearance)")
            }
        }
    }

    @Test func increasedContrastKeepsTheSelectionDarkAndTheBorderWide() {
        #expect(color(.cellSelected, .darkContrast).red <= 0.24)
        #expect(PaletteSpec.selectedBorderWidth(in: .darkContrast) == 3)
        #expect(PaletteSpec.selectedBorderWidth(in: .lightContrast) == 3)
        #expect(PaletteSpec.selectedBorderWidth(in: .dark) == 2)
    }

    @Test func theLoupeSurroundIsTheSameDarkGrayEverywhere() {
        for appearance in PaletteAppearance.allCases {
            #expect(color(.loupeBackground, appearance) == .gray(0.09))
        }
    }

    /// The comparison's active ring against the loupe's surround
    /// (side-by-side-comparison design §16 D2): 3:1 in every appearance, the
    /// figure for a non-text element; Increase Contrast's answer is the
    /// ring's 3 pt width. The ring's colors are the system's, so they are
    /// resolved here: the neutral one it takes while the window is not key,
    /// and the accent color. A test can't choose the accent setting (the
    /// system reads it once per process), so it checks the accent as this
    /// Mac has it set, and the system's eight named colors as the nearest
    /// stand-ins for the other settings; the lowest of them all measured
    /// 4.47:1. Dark appearances only: the library window is always dark.
    @Test(arguments: [PaletteAppearance.dark, .darkContrast])
    @MainActor func theComparisonRingStandsOutOnTheSurround(_ appearance: PaletteAppearance) throws {
        let needed = 3.0
        let surround = color(.loupeBackground, appearance)
        let system = try #require(NSAppearance(named: appearance.increasesContrast ? .accessibilityHighContrastDarkAqua
                                                                                   : .darkAqua))
        let colors: [(String, NSColor)] = [
            ("accent", .controlAccentColor), ("neutral", .secondaryLabelColor), ("blue", .systemBlue),
            ("purple", .systemPurple), ("pink", .systemPink), ("red", .systemRed), ("orange", .systemOrange),
            ("yellow", .systemYellow), ("green", .systemGreen), ("graphite", .systemGray),
        ]
        for (name, dynamic) in colors {
            var resolved: NSColor?
            system.performAsCurrentDrawingAppearance { resolved = dynamic.usingColorSpace(.sRGB) }
            let value = try #require(resolved)
            let ring = PaletteColor(Double(value.redComponent), Double(value.greenComponent), Double(value.blueComponent),
                                    alpha: Double(value.alphaComponent)).over(surround)
            let ratio = ring.contrast(with: surround)
            #expect(ratio >= needed, "\(name) ring on the surround in \(appearance): \(ratio)")
            if ProcessInfo.processInfo.environment["PALETTE_REPORT"] != nil {
                print(String(format: "ring %@ in %@: %.2f:1", name, "\(appearance)", ratio))
            }
        }
    }

    @Test func contrastMathMatchesWCAG() {
        #expect(abs(PaletteColor.gray(0).contrast(with: .gray(1)) - 21) < 0.001)
        #expect(abs(PaletteColor.gray(0.5).contrast(with: .gray(0.5)) - 1) < 0.001)
        #expect(PaletteColor.gray(1, alpha: 0.5).over(.gray(0)) == .gray(0.5))
    }
}
