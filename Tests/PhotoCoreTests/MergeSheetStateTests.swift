import CoreGraphics
import Foundation
import Testing
@testable import PhotoCore

/// The Merge to HDR sheet's rules without its views (issue #150, revision
/// 2026-11-21; design §5.5 to §5.8, §6.4, §11).
@Suite("HDR merge sheet")
struct MergeSheetStateTests {
    typealias F = MergeSelectionTests

    /// −2, 0, +2 EV, the 0 EV frame second in time; IMG_3 in another folder.
    static func bracket(thirdFolder: String = "/shoot") -> MergeSelection {
        MergeSelection(frames: [
            F.frame(2, "IMG_2", second: 2, compensation: 0),
            F.frame(1, "IMG_1", second: 1, compensation: -2),
            F.frame(3, "IMG_3", second: 3, compensation: 2, folder: thirdFolder),
        ])
    }

    /// The sheet with every disk answer in: every master readable, `readOnly` folders not writable.
    static func answered(_ selection: MergeSelection, readOnly: Set<String> = []) -> MergeSheetState {
        var state = MergeSheetState(selection: selection)
        state.record(unreadable: nil)
        for frame in selection.frames {
            state.record(folder: frame.folder, writable: !readOnly.contains(frame.folder.path))
        }
        return state
    }

    @Test("AC3, AC9a: the sheet opens on the default reference (0 EV, not first in time) with both boxes on")
    func opensWithDefaults() {
        let state = MergeSheetState(selection: Self.bracket())
        #expect(state.reference.displayName == "IMG_2")
        #expect(state.selection.frames.map(\.displayName) == ["IMG_1", "IMG_2", "IMG_3"])
        #expect(state.options == MergeOptions(align: true, deghost: true))
        // Nothing asked yet: Merge is off until the disk answers.
        #expect(!state.canStart(isMerging: false))
        #expect(state.folderToAsk?.path == "/shoot")
    }

    @Test("AC3c, AC9a: a sheet opened again for the same frames starts from the defaults, whatever was chosen")
    func reopensWithDefaults() {
        let selection = Self.bracket()
        var state = MergeSheetState(selection: selection)
        state.chooseReference(3)
        state.options.align = false
        state.options.deghost = false
        #expect(state.reference.displayName == "IMG_3")
        // A selection that already carries another reference still opens on the default.
        let again = MergeSheetState(selection: state.selection)
        #expect(again.reference.displayName == "IMG_2")
        #expect(again.options == .standard)
        #expect(MergeSheetState(selection: selection) == MergeSheetState(selection: again.selection))
    }

    @Test("AC9a: the two boxes are independent and change nothing else on the sheet")
    func boxesAreIndependent() {
        let base = Self.answered(Self.bracket())
        for align in [true, false] {
            for deghost in [true, false] {
                var state = base
                state.options.align = align
                state.options.deghost = deghost
                #expect(state.options.align == align && state.options.deghost == deghost)
                #expect(state.reference == base.reference)
                #expect(state.refusal == nil)
                #expect(state.canStart(isMerging: false))
                #expect(state.name(format: .tiff) == base.name(format: .tiff))
            }
        }
    }

    @Test("H17: choosing a row makes it the reference; no choice or an unknown row leaves it; rows keep their order")
    func choosing() {
        var state = Self.answered(Self.bracket())
        let changed1 = state.chooseReference(1)
        #expect(changed1)
        #expect(state.reference.displayName == "IMG_1")
        #expect(state.selection.frames.map(\.displayName) == ["IMG_1", "IMG_2", "IMG_3"])
        // ⌘-click on the chosen row, a click below the rows: the table says nil.
        let changed2 = state.chooseReference(nil)
        #expect(!changed2)
        #expect(state.reference.displayName == "IMG_1")
        let changed3 = state.chooseReference(99)
        #expect(!changed3)
        let changed4 = state.chooseReference(1)
        #expect(!changed4)
        #expect(state.reference.displayName == "IMG_1")
    }

    @Test("AC3a: the Name line follows the reference and the format; a late answer for another is ignored")
    func nameFollows() {
        var state = Self.answered(Self.bracket())
        // Unnumbered while the disk is asked, in the reference's stem.
        #expect(state.name(format: .tiff) == ("IMG_2_HDR.tif", false))
        state.record(name: "IMG_2_HDR-2.tif", reference: 2, format: .tiff)
        #expect(state.name(format: .tiff) == ("IMG_2_HDR-2.tif", true))
        #expect(state.name(format: .dng) == ("IMG_2_HDR.dng", false))
        state.chooseReference(3)
        #expect(state.name(format: .tiff) == ("IMG_3_HDR.tif", false))
        // The answer for IMG_2 arrives after the change: not shown for IMG_3.
        state.record(name: "IMG_2_HDR-3.tif", reference: 2, format: .tiff)
        #expect(state.name(format: .tiff) == ("IMG_3_HDR.tif", false))
        state.record(name: "IMG_3_HDR.tif", reference: 3, format: .tiff)
        #expect(state.name(format: .tiff) == ("IMG_3_HDR.tif", true))
    }

    @Test("AC12: the read-only folder's refusal follows the reference, named after it, and lifts in a writable folder")
    func folderRefusalFollows() {
        // The default reference IMG_2 is in the read-only folder; IMG_3 is not.
        var state = Self.answered(Self.bracket(thirdFolder: "/open"), readOnly: ["/shoot"])
        #expect(state.refusal == .unwritableFolder(reference: "IMG_2", folder: "shoot"))
        #expect(state.flagged == [2])
        #expect(!state.canStart(isMerging: false))
        state.chooseReference(3)
        #expect(state.refusal == nil)
        #expect(state.flagged.isEmpty)
        #expect(state.canStart(isMerging: false))
        #expect(state.framesInSeveralFolders)
        // The reverse brings it on again, naming the chosen frame.
        state.chooseReference(1)
        #expect(state.refusal == .unwritableFolder(reference: "IMG_1", folder: "shoot"))
        #expect(state.flagged == [1])
    }

    @Test("§5.8: a new folder is asked once, Merge is off meanwhile, and an answer for a superseded reference decides nothing")
    func folderAskedOnce() throws {
        var state = MergeSheetState(selection: Self.bracket(thirdFolder: "/open"))
        state.record(unreadable: nil)
        let first = try #require(state.folderToAsk)
        state.asking(first)
        #expect(state.folderToAsk == nil)
        // The person moves to the frame in the other folder before the answer.
        state.chooseReference(3)
        let second = try #require(state.folderToAsk)
        #expect(second.path == "/open")
        state.asking(second)
        // Back to a frame of the first folder: it is being asked already.
        state.chooseReference(1)
        #expect(state.folderToAsk == nil)
        #expect(!state.canStart(isMerging: false))
        // The /open answer comes for IMG_3, which is no longer the reference.
        let changed5 = state.record(folder: second, writable: true)
        #expect(!changed5)
        #expect(!state.canStart(isMerging: false))
        let changed6 = state.record(folder: first, writable: true)
        #expect(changed6)
        #expect(state.canStart(isMerging: false))
        // Back to IMG_3: its folder's answer was kept, nothing to ask.
        state.chooseReference(3)
        #expect(state.folderToAsk == nil)
        #expect(state.canStart(isMerging: false))
        #expect(!state.canStart(isMerging: true))
    }

    @Test("§6.4: the different-size refusal names and flags by the chosen reference; it applies whichever is chosen")
    func sizeRefusalFollows() {
        let selection = MergeSelection(frames: [
            F.frame(1, "A", second: 1, compensation: -2),
            F.frame(2, "B", second: 2, compensation: 0),
            F.frame(3, "C", size: CGSize(width: 400, height: 600), second: 3, compensation: 2),
        ])
        var state = Self.answered(selection)
        #expect(state.refusal == .differentSize(name: "C", reference: "B"))
        #expect(state.flagged == [3])
        state.chooseReference(3)
        #expect(state.refusal == .differentSize(name: "A", reference: "C"))
        #expect(state.flagged == [1, 2])
        // A flagged frame may be chosen, and a video too: the refusal stays (A13, §5.5).
        let withVideo = MergeSelection(frames: [F.frame(1, "A", second: 1),
                                                F.frame(2, "Clip", kind: .video, second: 2),
                                                F.frame(3, "C", second: 3)])
        var video = Self.answered(withVideo)
        let changed7 = video.chooseReference(2)
        #expect(changed7)
        #expect(video.refusal == .video(name: "Clip"))
    }

    @Test("§6.4: an unreadable master is refused whichever frame is the reference")
    func unreadableStays() {
        var state = MergeSheetState(selection: Self.bracket())
        state.record(unreadable: 3)
        state.record(folder: URL(fileURLWithPath: "/shoot"), writable: true)
        #expect(state.refusal == .unreadable(name: "IMG_3"))
        state.chooseReference(1)
        #expect(state.refusal == .unreadable(name: "IMG_3"))
        #expect(state.flagged == [3])
    }

    @Test("§11: after a change of reference VoiceOver hears a new message, that Merge is available, or nothing more")
    func announcement() {
        let readOnly = MergeRefusal.unwritableFolder(reference: "IMG_2", folder: "shoot")
        let other = MergeRefusal.unwritableFolder(reference: "IMG_1", folder: "shoot")
        #expect(MergeSheetState.messageChange(from: nil, to: readOnly) == .refusal(readOnly))
        #expect(MergeSheetState.messageChange(from: readOnly, to: nil) == .available)
        #expect(MergeSheetState.messageChange(from: readOnly, to: other) == .refusal(other))
        #expect(MergeSheetState.messageChange(from: readOnly, to: readOnly) == .none)
        #expect(MergeSheetState.messageChange(from: nil, to: nil) == .none)
    }

    /// −2, 0, +2 EV in three folders: IMG_2 (the default) in /a, IMG_1 in /b, IMG_3 in /c.
    static func threeFolders() -> MergeSelection {
        MergeSelection(frames: [
            F.frame(2, "IMG_2", second: 2, compensation: 0, folder: "/a"),
            F.frame(1, "IMG_1", second: 1, compensation: -2, folder: "/b"),
            F.frame(3, "IMG_3", second: 3, compensation: 2, folder: "/c"),
        ])
    }

    /// The sheet open on /a, answered: every master readable, /a writable.
    static func openOnA() throws -> MergeSheetState {
        var state = MergeSheetState(selection: threeFolders())
        let asked1 = state.decideSpinner(restart: false)
        let wait = try #require(asked1)
        state.record(unreadable: nil)
        state.record(folder: URL(fileURLWithPath: "/a"), writable: true)
        let asked7 = state.decideSpinner(restart: false)
        #expect(asked7 == nil)
        state.spinnerWaitEnded(wait)
        #expect(state.spinner == .hidden)
        return state
    }

    @Test("§5.4, §5.8 (C16): the spinner hides at once when the reference moves to a folder already answered")
    func spinnerHidesForAnAnsweredFolder() throws {
        var state = try Self.openOnA()
        // /c is slow: the spinner shows after the half second.
        state.chooseReference(3)
        state.asking(try #require(state.folderToAsk))
        let asked2 = state.decideSpinner(restart: true)
        let wait = try #require(asked2)
        #expect(state.spinner == .waiting(wait))
        state.spinnerWaitEnded(wait)
        #expect(state.spinner == .shown)
        // Back to IMG_2, whose folder answered: Merge is on and the spinner gone,
        // though /c hasn't answered.
        state.chooseReference(2)
        let asked8 = state.decideSpinner(restart: true)
        #expect(asked8 == nil)
        #expect(state.spinner == .hidden)
        #expect(state.canStart(isMerging: false))
        // /c's late answer changes nothing on screen.
        state.record(folder: URL(fileURLWithPath: "/c"), writable: true)
        let asked9 = state.decideSpinner(restart: false)
        #expect(asked9 == nil)
        #expect(state.spinner == .hidden)
    }

    @Test("§5.4, §5.8 (C16): a wait that ended for another reference never stops the next folder's spinner")
    func spinnerWaitsAgainForEachCheck() throws {
        var state = try Self.openOnA()
        // To slow /c, then within the half second back to answered /a.
        state.chooseReference(3)
        state.asking(try #require(state.folderToAsk))
        let asked3 = state.decideSpinner(restart: true)
        let first = try #require(asked3)
        state.chooseReference(2)
        let asked10 = state.decideSpinner(restart: true)
        #expect(asked10 == nil)
        // The first wait ends now: nothing to show.
        state.spinnerWaitEnded(first)
        #expect(state.spinner == .hidden)
        // To slow /b: a new wait, and the spinner after it.
        state.chooseReference(1)
        state.asking(try #require(state.folderToAsk))
        let asked4 = state.decideSpinner(restart: true)
        let second = try #require(asked4)
        #expect(second != first)
        #expect(state.spinner == .waiting(second))
        state.spinnerWaitEnded(first)
        #expect(state.spinner == .waiting(second))
        state.spinnerWaitEnded(second)
        #expect(state.spinner == .shown)
        // An answer for /c (superseded) leaves it; /b's hides it.
        state.record(folder: URL(fileURLWithPath: "/c"), writable: true)
        let asked11 = state.decideSpinner(restart: false)
        #expect(asked11 == nil)
        #expect(state.spinner == .shown)
        state.record(folder: URL(fileURLWithPath: "/b"), writable: true)
        let asked12 = state.decideSpinner(restart: false)
        #expect(asked12 == nil)
        #expect(state.spinner == .hidden)
    }

    @Test("§5.8 (C16): moving between two folders still being asked restarts the wait; a shown spinner stays")
    func spinnerAcrossPendingFolders() throws {
        var state = try Self.openOnA()
        state.chooseReference(3)
        state.asking(try #require(state.folderToAsk))
        let asked5 = state.decideSpinner(restart: true)
        let first = try #require(asked5)
        // To /b before the half second: the wait starts again for /b's check.
        state.chooseReference(1)
        state.asking(try #require(state.folderToAsk))
        let asked6 = state.decideSpinner(restart: true)
        let second = try #require(asked6)
        state.spinnerWaitEnded(first)
        #expect(state.spinner == .waiting(second))
        state.spinnerWaitEnded(second)
        #expect(state.spinner == .shown)
        // Back to /c, still being asked: the spinner stays rather than blinking.
        state.chooseReference(3)
        #expect(state.folderToAsk == nil)
        let asked13 = state.decideSpinner(restart: true)
        #expect(asked13 == nil)
        #expect(state.spinner == .shown)
    }
}
