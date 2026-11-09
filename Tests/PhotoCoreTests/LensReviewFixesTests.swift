import CoreGraphics
import Foundation
import Testing
@testable import PhotoCore

@Suite("Lens review fixes")
struct LensReviewFixesTests {
    @Test("R16a: only versions whose originals failed are left out; an unreadable stack stays for the catalog to report")
    func measurementsLeaveOutOnlyFailedOriginals() {
        var measured = BatchEdit.AlignmentMeasurements()
        measured.record(ColorAlignment(automatic: true, red: 5, blue: -3), id: 1, name: "a.tif")
        measured.record(nil, id: 2, name: "b.tif")
        // Version 3's stack could not be read, so nothing was recorded for it.
        #expect(measured.versionsToChange(from: [1, 2, 3]) == [1, 3])
        #expect(measured.unreadableOriginals == ["b.tif"])
        #expect(measured.alignments[1]?.red == 5 && measured.alignments[2] == nil)
    }

    @Test("A replaced run owns nothing: only the newest run clears the shared state")
    func latestRunOwnership() {
        var runs = BatchEdit.LatestRun()
        let first = runs.begin()
        #expect(runs.owns(first))
        let second = runs.begin()
        #expect(!runs.owns(first))
        #expect(runs.owns(second))
    }

    @Test("Refinement follows what is on screen, not the suspended map")
    func refinementWanted() {
        let photo = LiveRenderSession.Content.photo
        #expect(LoupeRefinement.wanted(content: photo, replacesSlot: false, isZoomed: true) == nil)
        #expect(LoupeRefinement.wanted(content: photo, replacesSlot: true, isZoomed: true) == .photoWithoutSlot)
        // The map is suspended, a slot is replaced and the loupe zoomed to fit: nothing to refine.
        #expect(LoupeRefinement.wanted(content: photo, replacesSlot: true, isZoomed: false) == nil)
        #expect(LoupeRefinement.wanted(content: .sharpeningMap, replacesSlot: false, isZoomed: false) == .map)
    }

    @Test("The debug script moves and deletes no file: originals are never moved")
    func debugScriptLeavesFilesAlone() throws {
        let verbs = ["moveItem(", "removeItem(", "trashItem(", "replaceItem(", "copyItem("]
        var paths: [String] = []
        for path in RepositoryFiles.files(under: "Sources/PhotoApp/Model") where path.contains("/Debug") {
            paths.append(path)
        }
        #expect(paths.count >= 3, "expected to find the debug script's files")
        for path in paths {
            let text = try String(contentsOf: RepositoryFiles.url(path), encoding: .utf8)
            for verb in verbs {
                #expect(!text.contains(verb), "\(path) calls \(verb)")
            }
        }
    }

    @Test("Matrix inverse round-trips")
    func matrixInverse() {
        let m: [[Double]] = [[2, 0, 1], [0, 3, 0], [1, 0, 2]]
        let v = SIMD3<Double>(0.25, -1.5, 4)
        let back = Matrix3.multiply(Matrix3.inverse(m), Matrix3.multiply(m, v))
        #expect(abs(back.x - v.x) < 1e-12 && abs(back.y - v.y) < 1e-12 && abs(back.z - v.z) < 1e-12)
    }
}
