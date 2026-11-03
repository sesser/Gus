import CoreGraphics
import Testing
@testable import PhotoCore

@Suite("Loupe zoom steps")
struct LoupeZoomStepTests {
    @Test func zoomInGoesToTheFirstStepAboveFit() {
        #expect(LoupeZoomSteps.zoomIn(from: 0.3, fit: 0.3) == 0.5)
        #expect(LoupeZoomSteps.zoomIn(from: 0.5, fit: 0.3) == 1)
        // A photo smaller than the window fits at 100 %: the next step is 200 %.
        #expect(LoupeZoomSteps.zoomIn(from: 1, fit: 1) == 2)
    }

    @Test func zoomInStopsAtTheLargestStep() {
        #expect(LoupeZoomSteps.zoomIn(from: 8, fit: 0.3) == nil)
        #expect(LoupeZoomSteps.zoomIn(from: 7.95, fit: 0.3) == nil)
    }

    @Test func zoomOutGoesBackToFitFromTheSmallestStep() {
        #expect(LoupeZoomSteps.zoomOut(from: 2, fit: 0.3) == 1)
        #expect(LoupeZoomSteps.zoomOut(from: 0.5, fit: 0.3) == 0.3)
        // Only steps above Fit are used: 25 % is below this Fit.
        #expect(LoupeZoomSteps.zoomOut(from: 0.5, fit: 0.4) == 0.4)
        #expect(LoupeZoomSteps.zoomOut(from: 0.3, fit: 0.3) == nil)
    }

    @Test func afterAPinchTheKeysSnapToTheNextStep() {
        #expect(LoupeZoomSteps.zoomIn(from: 1.4, fit: 0.3) == 2)
        #expect(LoupeZoomSteps.zoomOut(from: 1.4, fit: 0.3) == 1)
        #expect(LoupeZoomSteps.zoomOut(from: 0.45, fit: 0.3) == 0.3)
    }
}

@Suite("Rotating without a crop session")
struct CropTurnTests {
    private let camera = CropRect(x: 0, y: 0.125, width: 1, height: 0.75)

    @Test func aPhotoWithoutACropTurnsWholly() {
        let turned = Crop().turned(clockwise: true, cameraRect: nil)
        #expect(turned == Crop(quarterTurns: 1))
        #expect(Crop().turned(clockwise: false, cameraRect: nil) == Crop(quarterTurns: 3))
    }

    @Test func aRawKeepsItsCameraFrame() {
        // A 4:3 crop the camera chose, kept through the turn (a crop decodes the whole sensor).
        let turned = Crop().turned(clockwise: true, cameraRect: camera)
        #expect(turned.quarterTurns == 1)
        #expect(turned.rect == camera.turned(clockwise: true))
    }

    @Test func anExistingCropTurnsWithItsFrame() {
        let crop = Crop(rect: CropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4), quarterTurns: 1, angle: 3)
        let turned = crop.turned(clockwise: false, cameraRect: camera)
        #expect(turned == Crop(rect: crop.rect?.turned(clockwise: false), quarterTurns: 0, angle: 3))
    }

    @Test func fourTurnsGiveBackNoCrop() {
        for cameraRect in [nil, camera] {
            var crop = Crop()
            for _ in 0..<4 { crop = crop.turned(clockwise: true, cameraRect: cameraRect) }
            #expect(crop.isIdentity, "camera frame \(String(describing: cameraRect))")
            crop = Crop().turned(clockwise: true, cameraRect: cameraRect).turned(clockwise: false, cameraRect: cameraRect)
            #expect(crop.isIdentity)
        }
    }

    @Test func theWholeSensorIsNotTheCameraFrame() {
        // A turn showing the whole sensor (no rectangle), turned back upright on a raw
        // with a camera frame: still the whole sensor, so the rectangle becomes explicit.
        let crop = Crop(quarterTurns: 1).turned(clockwise: false, cameraRect: camera)
        #expect(crop == Crop(rect: .full))
        #expect(!crop.isIdentity)
        // Without a camera frame the whole sensor is what the photo shows anyway.
        #expect(Crop(quarterTurns: 1).turned(clockwise: false, cameraRect: nil).isIdentity)
    }
}

@Suite("Batch adjustments")
struct BatchEditTests {
    @Test func videosAreSkipped() {
        let selection = BatchEdit.select([
            .init(versionID: 1, isVideo: false), .init(versionID: 2, isVideo: true), .init(versionID: 3, isVideo: false),
        ])
        #expect(selection.versionIDs == [1, 3])
        #expect(selection.skippedVideos == 1)
        #expect(selection.skipped == 1)
    }

    @Test func offlineMastersAreSkippedOnlyWhenTheChangeReadsThem() {
        let candidates: [BatchEdit.Candidate] = [
            .init(versionID: 1, isVideo: false, needsMaster: true, isOnline: false),
            .init(versionID: 2, isVideo: false, needsMaster: false, isOnline: false),
            .init(versionID: 3, isVideo: false, needsMaster: true, isOnline: true),
        ]
        let selection = BatchEdit.select(candidates)
        #expect(selection.versionIDs == [2, 3])
        #expect(selection.skippedOffline == 1)
    }

    @Test func aVersionCountsOnce() {
        let selection = BatchEdit.select([.init(versionID: 4, isVideo: false), .init(versionID: 4, isVideo: false)])
        #expect(selection.versionIDs == [4])
    }
}
