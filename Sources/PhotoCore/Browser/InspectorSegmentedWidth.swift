import CoreGraphics

/// The debug script's verdict on one segmented control in the inspector at
/// its narrowest width (`print inspectorwidth`, #223). Pure, so the cases that
/// must keep reporting (the #223 overflow) are pinned by tests.
public enum InspectorSegmentedWidth {
    public enum Verdict: String, Sendable {
        /// Fits the room it has at the narrowest column.
        case fits
        /// Keeps its width and is wider than its room: it would widen the column (#223).
        case overflow
        /// Fills the width offered and is narrower than its intrinsic width there: check the drawing.
        case compressed
        /// Keeps its own width at the column's trailing edge (the Presets view switch): it moves with
        /// that edge as the pane narrows, so its room from where it is now means nothing.
        case trailing
    }

    /// - Parameters:
    ///   - frame: The control's frame in the visible area of the inspector's scroll view.
    ///   - needs: Its intrinsic width.
    ///   - fillsWidth: It takes the width offered (`AppKitSegmented.fillsWidth`).
    ///   - visibleWidth: The visible area's width now.
    ///   - room: The width it has from where it starts at the narrowest column.
    ///   - padding: The inspector's padding on each side.
    public static func verdict(frame: CGRect, needs: CGFloat, fillsWidth: Bool, visibleWidth: CGFloat,
                               room: CGFloat, padding: CGFloat) -> Verdict {
        // Only a control at its own width that SwiftUI placed away from the
        // column's leading edge and against its trailing edge. A keeps-width
        // control stretched across the column (Spots' Heal / Clone, Tone
        // Curve before #223) also ends at the trailing edge, but starts at the
        // leading one and is wider than it needs: its room is real.
        let ownWidth = abs(frame.width - needs) < 0.5
        let awayFromLeadingEdge = frame.minX > padding + 0.5
        let atTrailingEdge = abs(frame.maxX - (visibleWidth - padding)) < 0.5
        if !fillsWidth, ownWidth, awayFromLeadingEdge, atTrailingEdge { return .trailing }
        if needs <= room + 0.5 { return .fits }
        return fillsWidth ? .compressed : .overflow
    }
}
