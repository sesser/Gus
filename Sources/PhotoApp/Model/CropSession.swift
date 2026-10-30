import CoreGraphics
import Foundation
import PhotoCore

/// Proportions the crop frame can be held to.
enum CropAspect: String, CaseIterable, Sendable {
    case free, square, threeTwo, fourThree, sixteenNine

    /// Long side over short side; nil for free.
    var ratio: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .threeTwo: 3.0 / 2
        case .fourThree: 4.0 / 3
        case .sixteenNine: 16.0 / 9
        }
    }

    var title: String {
        switch self {
        case .free: String(localized: "Free", comment: "Crop aspect ratio: not constrained")
        case .square: String(localized: "1:1", comment: "Crop aspect ratio")
        case .threeTwo: String(localized: "3:2", comment: "Crop aspect ratio")
        case .fourThree: String(localized: "4:3", comment: "Crop aspect ratio")
        case .sixteenNine: String(localized: "16:9", comment: "Crop aspect ratio")
        }
    }
}

/// A crop being edited in the loupe. The photo is shown whole under the crop
/// frame; nothing is saved until the session ends.
struct CropSession: Equatable {
    /// The values being edited. The rectangle is always set.
    var crop: Crop
    /// What the frame is held to.
    var aspect = CropAspect.free
    /// The straighten slider or a rotating drag is moving.
    var isStraightening = false
    /// The rectangle when straightening began: each angle fits it again, so
    /// going back to the starting angle gives it back.
    var straightenStart: CropRect?
    /// The rectangle of a photo without a crop: the camera's own crop, or the whole frame.
    var cameraRect: CropRect
    /// Pixel size of the whole image, before the quarter turns.
    var sourceSize: CGSize

    var rect: CropRect { crop.rect ?? .full }

    /// Pixel size of the frame the rectangle is in.
    var turnedSize: CGSize { crop.turnedSize(sourceSize) }

    /// Width over height the frame is held to, following its current orientation.
    var ratio: Double? {
        guard let ratio = aspect.ratio else { return nil }
        return CropGeometry.ratio(of: rect, size: turnedSize) >= 1 ? ratio : 1 / ratio
    }

    /// The crop to save: none when it is back to the photo's own frame.
    var saved: Crop {
        if crop.quarterTurns == 0, crop.angle == 0, rect.isClose(to: cameraRect) { return Crop() }
        return crop
    }
}
