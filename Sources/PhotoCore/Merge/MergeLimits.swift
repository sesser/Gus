import Foundation

/// The bounds of an HDR merge (PRD A5, R9), in one place.
public enum MergeLimits {
    /// Frames a merge takes at least (fewer is no merge: the command is off, R1).
    public static let minFrames = 2
    /// Frames a merge takes at most (A5: a proposed bound, measured in
    /// status.md's memory spike).
    public static let maxFrames = 9

    /// Pixels a frame may have at most (security review M1): the size the app
    /// already gives LibRaw (`LibRawDecoder.maximumSensorPixels`), which is
    /// above every camera made today (the largest backs record 150 MP). A
    /// file whose header claims more (a hostile or broken PNG or TIFF) is
    /// refused before anything is allocated.
    public static let maximumPixels = LibRawDecoder.maximumSensorPixels

    /// Bytes the frames' full-resolution pixels may take together (8 a
    /// pixel, half floats; status.md Spike 3): half of this Mac's memory.
    /// The other half is left to the system RAW decoder's working set (about
    /// 0.8 to 1.5 GB), Core Image, the reduced copies and the rest of the app.
    public static var frameMemoryBudget: Int {
        Int(min(ProcessInfo.processInfo.physicalMemory / 2, UInt64(Int.max)))
    }

    /// The bytes `frames` frames of `pixels` each take, held for a merge.
    public static func heldBytes(pixels: Int, frames: Int) -> Int {
        let (bytes, overflow) = pixels.multipliedReportingOverflow(by: 8 * max(frames, 1))
        return overflow ? .max : bytes
    }

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
