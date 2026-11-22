/// Which photos the lens frame question asks about (docs/features/
/// lens-corrections/design.md §6): a paste or preset that moves the
/// corrected frame of a photo with masks or spots asks first, once for the
/// whole command, with counts.
public enum LensFrameQuestion {
    /// Masks and spots of a photo, whether their groups are on or not.
    public static func masksAndSpots(_ values: Adjustments) -> Int {
        values.local.masks.count + values.spots.spots.count
    }

    /// A target that holds masks or spots, with its values before and after.
    public struct Candidate: Sendable {
        public var id: Int64
        public var before: Adjustments
        public var after: Adjustments
        /// Distortion uses Auto before or after: its file decides what moves.
        public var usesAuto: Bool
    }

    /// The targets the question may be about: those with masks or spots
    /// before or after `transform`, less the open photo (`open`) when the
    /// question was already answered on this visit for as many as it has
    /// (`openAnswer`). Whether each one's frame really moves is decided with
    /// its file's lens state (`LensCorrectionPlan.movesFrame`).
    ///
    /// `transform` is the change as the question sees it: a paste's spots are
    /// the source's, placed with the source's frame, so a paste passes
    /// `CopiedAdjustments.pastedForFrameQuestion`, which counts only what the
    /// target already has (copy-adjustments-selective R7, code review C1).
    public static func candidates(_ stacks: [Int64: EditStack], transform: (Adjustments) -> Adjustments,
                                  open: Int64?, openAnswer: Int?) -> [Candidate] {
        stacks.compactMap { id, stack in
            let before = Adjustments(stack: stack)
            let after = transform(before)
            let count = max(masksAndSpots(before), masksAndSpots(after))
            guard count > 0 else { return nil }
            if id == open, let openAnswer, count <= openAnswer { return nil }
            let usesAuto = (before.distortion.isOn && before.distortion.source == .auto)
                || (after.distortion.isOn && after.distortion.source == .auto)
            return Candidate(id: id, before: before, after: after, usesAuto: usesAuto)
        }
    }
}
