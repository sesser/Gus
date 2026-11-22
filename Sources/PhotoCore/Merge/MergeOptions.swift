import Foundation

/// The two choices of the Merge to HDR sheet besides the reference (issue #150,
/// R9, R10; design §5.6). Both on every time the sheet opens; never stored.
public struct MergeOptions: Sendable, Hashable {
    /// Line the frames up to the reference (Vision's registration). Off: the
    /// frames are merged at their own pixel positions, nothing is measured
    /// or moved, and no frame is refused for failing to line up (A14).
    public var align: Bool
    /// Take areas where a frame disagrees with the reference from the
    /// reference alone (`MergeGhosts`). Off: the plain exposure-weighted blend,
    /// with no ghost masks.
    public var deghost: Bool

    public init(align: Bool = true, deghost: Bool = true) {
        self.align = align
        self.deghost = deghost
    }

    /// What the sheet opens with and `photocli merge` uses unless told otherwise.
    public static let standard = MergeOptions()
}
