import Foundation

/// The per-pixel math of the merge, which the kernels (`MergeKernels`)
/// compute on the GPU, and its constants.
///
/// **Radiance** (Debevec and Malik 1997, "Recovering high dynamic range
/// radiance maps from photographs", eq. 6, for a camera whose response is
/// already linear): each frame's value divided by its exposure relative to
/// the reference is an estimate of the scene's light, and the estimates are
/// averaged with weights that drop to nothing toward black and toward the
/// frame's clipping level.
///
/// - The weighting function of a value `z` (its brightest channel over the
///   frame's clipping level) is `1 - (2z - 1)^12`, the broad hat of Reinhard,
///   Ward, Pattanaik and Debevec, "High Dynamic Range Imaging" (2005), §4.7:
///   flat over the usable range, zero at black and at clipping.
/// - It is multiplied by the frame's relative exposure: with photon noise, a
///   frame's estimate has a variance inversely proportional to its exposure,
///   so the inverse-variance weight grows with it (Granados et al. 2010,
///   "Optimal HDR reconstruction with linear digital cameras").
/// - The darkest frame keeps a weight of 1 up to its clipping level and the
///   brightest one down to black (`openTop`, `openBottom`): no other frame
///   holds those values better, so falling to nothing there would leave
///   the brightest highlights and the deepest shadows with no estimate.
/// - A ghost mask value `m` (0 to 1) scales a frame's weight by `1 - m`, and
///   the reference keeps a small floor weight everywhere, so where every other
///   frame is masked the reference's pixel is the result (R10).
public enum MergeMath {
    /// A frame sampled between pixels counts a neighbor's brightness for its
    /// weight when the neighbor makes at least this share of the mix (1/64;
    /// the kernel's `tapShare`):
    /// a fraction of a pixel's movement then doesn't turn a clipped
    /// neighbor's few percent into a clipped pixel, and a decision between
    /// float and double rounding can't fall on an everyday share.
    public static let tapShare: Double = 1.0 / 64

    /// The reference's floor weight: far below any frame's real weight (a
    /// hat value of 1e-4 is a frame within 0.0003% of black or of clipping).
    public static let referenceFloorWeight: Float = 1e-4
}

/// What the merge knows about each frame before it renders: how bright it
/// is against the reference, where it clips, and how it lines up.
public struct MergeFramePlan: Sendable, Equatable {
    /// Exposure relative to the reference (2 is one stop brighter).
    public var exposure: Double
    /// The value at which the frame's brightest channel is clipped.
    public var clip: Double
    /// The frame onto the reference, in Core Image coordinates of the
    /// measuring copy (`HDRMerger.radiance` scales it to the full size).
    public var homography: MergeAlignment.Homography

    public init(exposure: Double, clip: Double, homography: MergeAlignment.Homography) {
        self.exposure = exposure
        self.clip = clip
        self.homography = homography
    }
}
