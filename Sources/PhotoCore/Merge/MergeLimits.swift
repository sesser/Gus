import Foundation

/// The bounds of an HDR merge (PRD A5, R9), in one place.
public enum MergeLimits {
    /// Frames a merge takes at least (fewer is no merge: the command is off, R1).
    public static let minFrames = 2
    /// Frames a merge takes at most (A5: a proposed bound, measured in
    /// status.md's memory spike).
    public static let maxFrames = 9

    /// The long edge of the reduced copies alignment, exposure, ghosts and
    /// tone statistics are measured on.
    public static let measureLongEdge = 2048

    // Alignment (R9): what still counts as a hand-held movement between frames.

    /// The center may move at most this part of the long edge.
    public static let maximumShiftFraction = 0.08
    public static let maximumRotationDegrees = 3.0
    /// A change of scale (a zoom between frames) of at most this part.
    public static let maximumScaleChange = 0.03
    /// How far a corner's homogeneous coordinate may stray from 1.
    public static let maximumPerspective = 0.02
    /// Frames whose luminance ranks correlate less than this after lining up
    /// are of different scenes (status.md "Spike 2" measures brackets and
    /// unrelated pairs).
    public static let minimumAlignmentCorrelation = 0.6
}
