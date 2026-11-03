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

    @Test func contrastMathMatchesWCAG() {
        #expect(abs(PaletteColor.gray(0).contrast(with: .gray(1)) - 21) < 0.001)
        #expect(abs(PaletteColor.gray(0.5).contrast(with: .gray(0.5)) - 1) < 0.001)
        #expect(PaletteColor.gray(1, alpha: 0.5).over(.gray(0)) == .gray(0.5))
    }
}
