import AVFoundation
import CoreGraphics
import Foundation

/// Still frames from videos, for thumbnails and previews.
public enum VideoFrames {
    public enum Failure: Error {
        case noFrame(URL)
    }

    /// A representative frame (one second in, or a tenth of the way through a
    /// shorter clip), upright, no larger than `longEdge` pixels.
    public static func poster(of url: URL, longEdge: Int?) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let longEdge {
            generator.maximumSize = CGSize(width: longEdge, height: longEdge)
        }
        // Any nearby frame will do; exact seeking decodes from the previous keyframe.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let duration = try await asset.load(.duration).seconds
        let seconds = duration.isFinite ? min(1, max(0, duration * 0.1)) : 0
        do {
            return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        } catch {
            throw Failure.noFrame(url)
        }
    }
}
