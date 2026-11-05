import AppKit
import Foundation
import Testing
@testable import PhotoCore

@Suite("Film strip geometry")
struct FilmStripGeometryTests {
    /// A loupe tall enough that the cap never applies to the slider's range.
    let tall = 1000.0

    @Test func defaultsToTheLargestStep() {
        let geometry = FilmStripGeometry(storedSize: FilmStripGeometry.defaultSize, loupeHeight: tall)
        #expect(FilmStripGeometry.defaultSize == 120)
        #expect(geometry.cellSize == 120)
        #expect(geometry.stripHeight == 136)
        #expect(geometry.pitch == 124)
        #expect(FilmStripGeometry.steps.map(FilmStripGeometry.stripHeight(cellSize:)) == [64, 80, 96, 112, 136])
    }

    @Test func snapsToTheNearestStepWithTiesToTheLarger() {
        #expect(FilmStripGeometry.nearestStep(64) == 64)
        #expect(FilmStripGeometry.nearestStep(71) == 64)
        // Midpoints: 56 between 48 and 64, 72, 88, and 108 between 96 and 120.
        #expect(FilmStripGeometry.nearestStep(56) == 64)
        #expect(FilmStripGeometry.nearestStep(72) == 80)
        #expect(FilmStripGeometry.nearestStep(88) == 96)
        #expect(FilmStripGeometry.nearestStep(108) == 120)
        #expect(FilmStripGeometry.nearestStep(107.9) == 96)
        // Outside the steps: the nearer end.
        #expect(FilmStripGeometry.nearestStep(10) == 48)
        #expect(FilmStripGeometry.nearestStep(400) == 120)
    }

    @Test func storedSizesMapToSteps() {
        #expect(FilmStripGeometry.validatedSize(nil) == 120)
        #expect(FilmStripGeometry.validatedSize(.nan) == 120)
        // Sizes the slider build could store.
        #expect(FilmStripGeometry.validatedSize(53) == 48)
        #expect(FilmStripGeometry.validatedSize(100) == 96)
        #expect(FilmStripGeometry.validatedSize(115) == 120)
        #expect(FilmStripGeometry.validatedSize(30) == 48)
        #expect(FilmStripGeometry.validatedSize(500) == 120)
        #expect(FilmStripGeometry(storedSize: 70, loupeHeight: tall).cellSize == 64)
    }

    @Test func theCapShowsTheLargestStepThatFits() {
        // A quarter of 400 is 100: the 80 step's 96 pt strip fits, 96's 112 does not.
        #expect(FilmStripGeometry(storedSize: 120, loupeHeight: 400).cellSize == 80)
        #expect(FilmStripGeometry(storedSize: 120, loupeHeight: 400).stripHeight <= 0.25 * 400)
        // Exactly a quarter fits: 136 × 4 = 544.
        #expect(FilmStripGeometry(storedSize: 120, loupeHeight: 544).cellSize == 120)
        #expect(FilmStripGeometry(storedSize: 120, loupeHeight: 543).cellSize == 96)
        // Below the cap, the stored step is shown.
        #expect(FilmStripGeometry(storedSize: 64, loupeHeight: 400).cellSize == 64)
        // Never a size between steps.
        for height in stride(from: 0.0, through: 800, by: 7) {
            let cell = FilmStripGeometry(storedSize: 120, loupeHeight: height).cellSize
            #expect(FilmStripGeometry.steps.contains(cell))
        }
    }

    @Test func theCapNeverGoesBelowTheSmallestStep() {
        // Under 256 pt nothing fits; the 48 step shows anyway.
        #expect(FilmStripGeometry(storedSize: 120, loupeHeight: 255).cellSize == 48)
        #expect(FilmStripGeometry(storedSize: 120, loupeHeight: 0).cellSize == 48)
        #expect(FilmStripGeometry.dragHeights(loupeHeight: 100) == 64...64)
    }

    @Test func dragsMoveBetweenTheStepsThatFitAndSettleOnTheNearest() {
        #expect(FilmStripGeometry.dragHeights(loupeHeight: tall) == 64...136)
        #expect(FilmStripGeometry.dragHeights(loupeHeight: 400) == 64...96)
        // A strip 100 pt tall has 84 pt cells: nearest 80.
        #expect(FilmStripGeometry.settledStep(stripHeight: 100, loupeHeight: tall) == 80)
        // 104 pt: 88, the midpoint of 80 and 96, goes to 96.
        #expect(FilmStripGeometry.settledStep(stripHeight: 104, loupeHeight: tall) == 96)
        #expect(FilmStripGeometry.settledStep(stripHeight: 136, loupeHeight: 400) == 80)
    }

    @Test func aReleaseAtTheCapKeepsALargerStoredStep() {
        // A quarter of 400 fits the 80 step at most.
        #expect(FilmStripGeometry.storedStep(afterSettlingOn: 80, stored: 120, loupeHeight: 400) == 120)
        // Below the cap's step: the new step is stored.
        #expect(FilmStripGeometry.storedStep(afterSettlingOn: 64, stored: 120, loupeHeight: 400) == 64)
        // At the cap with a smaller stored step: the cap's step is stored.
        #expect(FilmStripGeometry.storedStep(afterSettlingOn: 80, stored: 48, loupeHeight: 400) == 80)
        // No cap: what the release settled on.
        #expect(FilmStripGeometry.storedStep(afterSettlingOn: 96, stored: 120, loupeHeight: 1000) == 96)
    }

    @Test func incrementAndDecrementMoveOneStepAmongThoseThatFit() {
        #expect(FilmStripGeometry.step(after: 64, up: true, loupeHeight: tall) == 80)
        #expect(FilmStripGeometry.step(after: 64, up: false, loupeHeight: tall) == 48)
        #expect(FilmStripGeometry.step(after: 48, up: false, loupeHeight: tall) == nil)
        #expect(FilmStripGeometry.step(after: 120, up: true, loupeHeight: tall) == nil)
        #expect(FilmStripGeometry.step(after: 80, up: true, loupeHeight: 400) == nil)
    }

    @Test func thumbnailsLoadAtTheLargestStepsPixels() {
        #expect(FilmStripGeometry.thumbnailPixelSize(backingScale: 2) == 240)
        #expect(FilmStripGeometry.thumbnailPixelSize(backingScale: 1) == 120)
    }

    @Test func endInsetsLetBothEndsReachTheCenter() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        #expect(geometry.endInset(visibleWidth: 864) == 400)
        // 400 + 10 × 68 − 4 + 400.
        #expect(geometry.contentWidth(count: 10, visibleWidth: 864) == 1476)
        #expect(geometry.maximumOffset(count: 10, visibleWidth: 864) == 9 * 68)
    }

    @Test func centeringIsIndexTimesPitch() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        let width = 864.0
        for index in [0, 1, 5, 9] {
            let offset = geometry.centeringOffset(for: index, count: 10, visibleWidth: width)
            #expect(offset == Double(index) * geometry.pitch)
            // The cell's center is the visible center.
            let center = geometry.cellOrigin(index, visibleWidth: width) + geometry.cellSize / 2
            #expect(center - offset == width / 2)
            #expect(geometry.centeredIndex(offset: offset, count: 10, visibleWidth: width) == index)
        }
    }

    @Test func centersTheFirstAndTheLastPhoto() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        #expect(geometry.centeringOffset(for: 0, count: 500, visibleWidth: 900) == 0)
        #expect(geometry.centeringOffset(for: 499, count: 500, visibleWidth: 900) == 499 * 68)
        #expect(geometry.centeringOffset(for: 499, count: 500, visibleWidth: 900)
            == geometry.maximumOffset(count: 500, visibleWidth: 900))
    }

    @Test func centersOneAndTwoPhotosInsteadOfLeftAligningThem() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        let width = 900.0
        // One photo: centered, nothing to scroll.
        #expect(geometry.centeringOffset(for: 0, count: 1, visibleWidth: width) == 0)
        #expect(geometry.maximumOffset(count: 1, visibleWidth: width) == 0)
        #expect(geometry.cellOrigin(0, visibleWidth: width) + 32 == width / 2)
        // Two photos: each centered in turn, the same place as with many.
        #expect(geometry.centeringOffset(for: 0, count: 2, visibleWidth: width) == 0)
        #expect(geometry.centeringOffset(for: 1, count: 2, visibleWidth: width) == 68)
    }

    @Test func clampsIndicesAndOffsets() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        #expect(geometry.centeringOffset(for: 20, count: 10, visibleWidth: 864) == 9 * 68)
        #expect(geometry.centeringOffset(for: -3, count: 10, visibleWidth: 864) == 0)
        #expect(geometry.centeringOffset(for: 0, count: 0, visibleWidth: 864) == 0)
        #expect(geometry.clampedOffset(-50, count: 10, visibleWidth: 864) == 0)
        #expect(geometry.clampedOffset(10_000, count: 10, visibleWidth: 864) == 9 * 68)
    }

    @Test func aStripNarrowerThanOneCellHasNoInsetAndCentersAsWellAsItCan() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        let width = 40.0
        #expect(geometry.endInset(visibleWidth: width) == 0)
        // Cell 3 starts at 204; its middle (236) is the visible middle at 216.
        #expect(geometry.centeringOffset(for: 3, count: 10, visibleWidth: width) == 216)
        #expect(geometry.centeringOffset(for: 0, count: 10, visibleWidth: width) == 12)
        #expect(geometry.visibleRange(offset: 216, visibleWidth: width, count: 10) == 3..<4)
        #expect(geometry.centeredIndex(offset: 216, count: 10, visibleWidth: width) == 3)
    }

    @Test func visibleRangeCoversCellsThatIntersectTheVisibleWidth() {
        let geometry = FilmStripGeometry(storedSize: 64, loupeHeight: tall)
        let width = 864.0 // inset 400
        // Centered on 0: cells start at 400, 468, …; 864 − 400 = 464 → cells 0…6.
        #expect(geometry.visibleRange(offset: 0, visibleWidth: width, count: 100) == 0..<7)
        // Centered on 50: offset 3400, visible document 3400…4264, cells 44…56.
        #expect(geometry.visibleRange(offset: 3400, visibleWidth: width, count: 100) == 44..<57)
        #expect(geometry.visibleRange(offset: 0, visibleWidth: width, count: 3) == 0..<3)
        #expect(geometry.visibleRange(offset: 0, visibleWidth: width, count: 0).isEmpty)
        #expect(geometry.visibleRange(offset: 0, visibleWidth: 0, count: 10).isEmpty)
    }

    @Test func onlyNearMovesAnimate() {
        let width = 800.0
        #expect(FilmStripGeometry.animatesMove(from: 0, to: 68, visibleWidth: width, isKeyRepeat: false,
                                               reduceMotion: false))
        #expect(FilmStripGeometry.animatesMove(from: 800, to: 0, visibleWidth: width, isKeyRepeat: false,
                                               reduceMotion: false))
        // Further than one visible width (Home, End, after scrolling away): jump.
        #expect(!FilmStripGeometry.animatesMove(from: 0, to: 801, visibleWidth: width, isKeyRepeat: false,
                                                reduceMotion: false))
        // A held arrow and Reduce Motion: jump.
        #expect(!FilmStripGeometry.animatesMove(from: 0, to: 68, visibleWidth: width, isKeyRepeat: true,
                                                reduceMotion: false))
        #expect(!FilmStripGeometry.animatesMove(from: 0, to: 68, visibleWidth: width, isKeyRepeat: false,
                                                reduceMotion: true))
        #expect(!FilmStripGeometry.animatesMove(from: 68, to: 68, visibleWidth: width, isKeyRepeat: false,
                                                reduceMotion: false))
    }

    /// The caption's toggle symbol exists on macOS 15, the app's minimum:
    /// it resolves here, and the system's symbol list dates it before 15.
    @Test @MainActor func toggleSymbolResolvesOnMacOS15() throws {
        #expect(NSImage(systemSymbolName: FilmStripGeometry.toggleSymbolName, accessibilityDescription: nil) != nil)
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let symbols = try #require(plist["symbols"] as? [String: String])
        let releases = try #require(plist["year_to_release"] as? [String: [String: String]])
        let year = try #require(symbols[FilmStripGeometry.toggleSymbolName])
        let macOS = try #require(releases[year]?["macOS"])
        let major = try #require(Int(macOS.split(separator: ".").first ?? ""))
        #expect(major <= 15, "\(FilmStripGeometry.toggleSymbolName) needs macOS \(macOS)")
    }
}
