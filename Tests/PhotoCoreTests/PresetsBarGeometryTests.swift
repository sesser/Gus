import CoreGraphics
import PhotoCore
import Testing

/// The Presets heading's button row (#241 AC1, design §3): the switch is
/// right-aligned, the push buttons wrap as before, and nothing overlaps.
@Suite("Presets button row")
struct PresetsBarGeometryTests {
    /// About the app's small push buttons and the two-segment switch.
    let sizes = PresetsBarGeometry.Sizes(save: CGSize(width: 52, height: 22), importButton: CGSize(width: 60, height: 22),
                                         manage: CGSize(width: 68, height: 22), viewSwitch: CGSize(width: 59, height: 21))

    @Test func neededWidthsAddTheButtonsTheSpacingAndTheGap() {
        // 52 + 6 + 60 + 6 + 68 + 8 + 59
        #expect(PresetsBarGeometry.neededWidth(.oneLine, sizes) == 259)
        // 52 + 6 + 60 + 8 + 59, wider than Manage alone
        #expect(PresetsBarGeometry.neededWidth(.switchBesideImport, sizes) == 185)
        // max(52 + 6 + 60, 68 + 8 + 59)
        #expect(PresetsBarGeometry.neededWidth(.switchBesideManage, sizes) == 135)
    }

    @Test func takesTheFirstArrangementThatFits() {
        #expect(PresetsBarGeometry.arrangement(forWidth: 300, sizes) == .oneLine)
        #expect(PresetsBarGeometry.arrangement(forWidth: 259, sizes) == .oneLine)
        #expect(PresetsBarGeometry.arrangement(forWidth: 258.5, sizes) == .switchBesideImport)
        #expect(PresetsBarGeometry.arrangement(forWidth: 185, sizes) == .switchBesideImport)
        #expect(PresetsBarGeometry.arrangement(forWidth: 184, sizes) == .switchBesideManage)
        // Narrower than anything: the last, as the push buttons alone wrapped before.
        #expect(PresetsBarGeometry.arrangement(forWidth: 80, sizes) == .switchBesideManage)
        #expect(PresetsBarGeometry.arrangement(forWidth: nil, sizes) == .oneLine)
        #expect(PresetsBarGeometry.arrangement(forWidth: .infinity, sizes) == .oneLine)
    }

    @Test func nothingOverlapsAndTheSwitchIsAtTheRightEdge() {
        for width in stride(from: 60.0, through: 420, by: 0.5) {
            let frames = PresetsBarGeometry.frames(forWidth: width, sizes)
            let row = PresetsBarGeometry.size(forWidth: width, sizes)
            #expect(frames.count == 4)
            for i in frames.indices {
                for j in frames.indices where j > i {
                    #expect(!frames[i].intersects(frames[j]), "width \(width): items \(i) and \(j) overlap")
                }
                #expect(frames[i].minX >= 0 && frames[i].maxX <= row.width + 0.001)
                #expect(frames[i].minY >= 0 && frames[i].maxY <= row.height + 0.001)
            }
            #expect(abs(frames[3].maxX - row.width) < 0.001, "width \(width): the switch is not right-aligned")
            // The row takes the width offered, and never less than it needs.
            let needed = PresetsBarGeometry.neededWidth(PresetsBarGeometry.arrangement(forWidth: width, sizes), sizes)
            #expect(row.width == max(CGFloat(width), needed), "width \(width): row \(row.width), needs \(needed)")
        }
    }

    @Test func pushButtonsKeepTheirPlacesAndWrapAsBefore() {
        let one = PresetsBarGeometry.frames(forWidth: 320, sizes)
        #expect(one.map(\.minX) == [0, 58, 124, 261])
        #expect(Set(one.map(\.midY)).count == 1)
        #expect(PresetsBarGeometry.size(forWidth: 320, sizes).height == 22)

        let two = PresetsBarGeometry.frames(forWidth: 240, sizes)
        // Save, Import and the switch on the first line; Manage under Save.
        #expect(two[0].midY == two[1].midY && two[1].midY == two[3].midY)
        #expect(two[2].minX == 0 && two[2].minY == 22 + PresetsBarGeometry.lineSpacing)
        #expect(two[3].maxX == 240)
        #expect(PresetsBarGeometry.size(forWidth: 240, sizes).height == 50)

        let three = PresetsBarGeometry.frames(forWidth: 150, sizes)
        // Save and Import over Manage and the switch.
        #expect(three[0].midY == three[1].midY)
        #expect(three[2].midY == three[3].midY && three[2].minY > three[0].maxY)
        #expect(three[3].maxX == 150)
    }

    @Test func itemsAreCenteredOnTheirLine() {
        let frames = PresetsBarGeometry.frames(forWidth: 320, sizes)
        // The switch is a point shorter than the push buttons: half a point down.
        #expect(frames[3].minY == 0.5)
        #expect(frames[0].minY == 0)
    }

    @Test func aRowNarrowerThanItNeedsKeepsItsButtonsWhole() {
        let size = PresetsBarGeometry.size(forWidth: 80, sizes)
        #expect(size.width == PresetsBarGeometry.neededWidth(.switchBesideManage, sizes))
    }
}
