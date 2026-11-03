import Foundation
import Testing
@testable import PhotoCore

/// The import window's selection across scans of one source (sesser/Gus#19).
@Suite("Import selection")
struct ImportSelectionTests {
    private func shot(_ name: String, _ kind: FileKind = .jpeg, duplicate: Bool = false) -> SourceShot {
        var file = SourceFile(url: URL(fileURLWithPath: "/card/DCIM/100MSDCF/" + name), size: 1,
                              modifiedAt: .distantPast, kind: kind, metadata: .empty)
        file.isDuplicate = duplicate
        return SourceShot(files: [file])
    }

    /// Scans `next` after the person left `selection` checked in `shown`, the
    /// way the model does it.
    private func rescan(shown: [SourceShot], selection: Set<URL>, remembered: Set<URL> = [],
                        next: [SourceShot]) -> (selection: Set<URL>, leftOut: Set<URL>) {
        let leftOut = ImportSelection.leftOut(remembered: remembered, shown: shown, selection: selection)
        return (ImportSelection.selection(for: next, leftOut: leftOut), leftOut)
    }

    @Test func aNewSourceSelectsEveryShotNotInTheLibrary() {
        let shots = [shot("A.JPG"), shot("B.JPG"), shot("C.JPG", duplicate: true)]
        #expect(ImportSelection.selection(for: shots, leftOut: []) == [shots[0].id, shots[1].id])
    }

    @Test func rescanningKeepsAShotTheyLeftOut() {
        let shots = [shot("A.JPG"), shot("B.JPG"), shot("C.JPG")]
        let after = rescan(shown: shots, selection: [shots[0].id, shots[2].id], next: shots)
        #expect(after.selection == [shots[0].id, shots[2].id])
    }

    @Test func aShotNewToTheScanComesInSelected() {
        let photos = [shot("A.JPG"), shot("B.JPG")]
        let video = shot("C0001.MP4", .video)
        let after = rescan(shown: photos, selection: [photos[0].id], next: photos + [video])
        #expect(after.selection == [photos[0].id, video.id])
    }

    @Test func aShotNoLongerThereDropsOut() {
        let shots = [shot("A.JPG"), shot("B.JPG"), shot("C0001.MP4", .video)]
        let after = rescan(shown: shots, selection: Set(shots.map(\.id)), next: Array(shots.prefix(2)))
        #expect(after.selection == [shots[0].id, shots[1].id])
    }

    @Test func aVideoLeftOutStaysOutWhileVideosAreHiddenAndShownAgain() {
        let photos = [shot("A.JPG"), shot("B.JPG")]
        let video = shot("C0001.MP4", .video)
        // Video unchecked, then videos hidden: the video is not shown...
        let hidden = rescan(shown: photos + [video], selection: Set(photos.map(\.id)), next: photos)
        #expect(hidden.selection == Set(photos.map(\.id)))
        // ...and shown again: still left out.
        let shown = rescan(shown: photos, selection: hidden.selection, remembered: hidden.leftOut, next: photos + [video])
        #expect(shown.selection == Set(photos.map(\.id)))
    }

    @Test func checkingAShotAgainForgetsThatItWasLeftOut() {
        let shots = [shot("A.JPG"), shot("B.JPG")]
        let first = rescan(shown: shots, selection: [shots[0].id], next: shots)
        let second = rescan(shown: shots, selection: Set(shots.map(\.id)), remembered: first.leftOut, next: shots)
        #expect(second.leftOut.isEmpty)
        #expect(second.selection == Set(shots.map(\.id)))
    }

    @Test func aRescanWithNothingShownKeepsWhatWasRemembered() {
        // A second rescan while the first is still running: no shots are shown yet.
        let remembered: Set<URL> = [shot("B.JPG").id]
        #expect(ImportSelection.leftOut(remembered: remembered, shown: [], selection: []) == remembered)
    }

    @Test func duplicatesAreNeverSelectedOrCountedAsLeftOut() {
        let original = shot("A.JPG")
        let imported = shot("A.JPG", duplicate: true)
        // An imported shot is unchecked because it is in the library now, not by choice.
        let leftOut = ImportSelection.leftOut(remembered: [], shown: [imported, shot("B.JPG")],
                                              selection: [shot("B.JPG").id])
        #expect(leftOut.isEmpty)
        // So it comes back selected if it ever stops being a duplicate.
        #expect(ImportSelection.selection(for: [original], leftOut: leftOut) == [original.id])
        #expect(ImportSelection.selection(for: [imported], leftOut: []).isEmpty)
    }
}
