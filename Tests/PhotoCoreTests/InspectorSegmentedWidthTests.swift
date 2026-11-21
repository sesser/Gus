import CoreGraphics
import PhotoCore
import Testing

/// `print inspectorwidth`'s verdict (#223), with the Presets view switch's
/// exemption (#241 code review C1). Figures from the app at a 300 pt pane with
/// a legacy scroller: 283 pt visible, 239 pt of room from the column's edge at
/// the narrowest pane.
@Suite("Inspector segmented control width")
struct InspectorSegmentedWidthTests {
    func verdict(x: CGFloat, width: CGFloat, needs: CGFloat, fills: Bool, room: CGFloat) -> InspectorSegmentedWidth.Verdict {
        InspectorSegmentedWidth.verdict(frame: CGRect(x: x, y: 0, width: width, height: 24), needs: needs, fillsWidth: fills,
                                        visibleWidth: 283, room: room, padding: 12)
    }

    /// Tone Curve's channels before #223's fix: keeps its width, stretched
    /// across the column, needs more than the narrowest room. Must stay an overflow.
    @Test func theOldToneCurveOverflowStillReports() {
        #expect(verdict(x: 12, width: 259, needs: 244, fills: false, room: 239) == .overflow)
    }

    /// Spots' Heal / Clone: keeps its width, stretched across the column, fits.
    @Test func aStretchedControlThatFitsIsNotTrailing() {
        #expect(verdict(x: 12, width: 259, needs: 120, fills: false, room: 239) == .fits)
    }

    /// A control at its own width that fills the column from its leading edge.
    @Test func aControlAtItsOwnWidthFromTheLeadingEdgeIsMeasured() {
        #expect(verdict(x: 12, width: 259, needs: 259, fills: false, room: 239) == .overflow)
    }

    @Test func thePresetsViewSwitchIsTrailing() {
        #expect(verdict(x: 215, width: 56, needs: 56, fills: false, room: 36) == .trailing)
    }

    @Test func aKeepsWidthControlElsewhereIsMeasured() {
        // Auto / Manual at x 98, not at the trailing edge.
        #expect(verdict(x: 98, width: 120, needs: 136, fills: false, room: 153) == .fits)
        #expect(verdict(x: 98, width: 160, needs: 160, fills: false, room: 153) == .overflow)
    }

    @Test func fillsWidthControlsAreCompressedNotTrailing() {
        #expect(verdict(x: 12, width: 259, needs: 256.5, fills: true, room: 239) == .compressed)
        #expect(verdict(x: 215, width: 56, needs: 56, fills: true, room: 36) == .compressed)
    }
}
