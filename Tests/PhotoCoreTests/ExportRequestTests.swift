import Foundation
import Testing
@testable import PhotoCore

// Issue #163: the export sheet's request (read the photos, count the files in
// the way, then start or ask) runs one at a time, and a request cancelled with
// the sheet never shows its answer.

@Suite("Export request: one at a time, and a cancelled one is never answered")
struct ExportRequestGateTests {
    // The macros can't call a mutating method on the gate, so each call's
    // result is taken first.

    @Test func aSecondRequestWhileOneReadsIsRefused() throws {
        var gate = ExportRequestGate()
        let first = try #require(gate.begin(isExporting: false) as ExportRequestGate.Request?)
        // Return pressed again before the first request has counted.
        let second = gate.begin(isExporting: false)
        #expect(second == nil)
        #expect(gate.isPending)
        let answered = gate.end(first)
        #expect(answered)
        #expect(!gate.isPending)
    }

    @Test func noRequestWhileAnExportRuns() {
        var gate = ExportRequestGate()
        let request = gate.begin(isExporting: true)
        #expect(request == nil)
        #expect(!gate.isPending)
    }

    @Test func aRequestCanFollowOneThatEnded() throws {
        var gate = ExportRequestGate()
        let first = gate.begin(isExporting: false)
        let firstAnswered = try gate.end(#require(first))
        let second = gate.begin(isExporting: false)
        #expect(firstAnswered)
        #expect(second != nil && second != first)
        let secondAnswered = try gate.end(#require(second))
        #expect(secondAnswered)
    }

    @Test func aCancelledRequestEndsUnanswered() throws {
        var gate = ExportRequestGate()
        let request = try #require(gate.begin(isExporting: false) as ExportRequestGate.Request?)
        // Cancel closes the sheet while the count still reads.
        gate.cancel()
        #expect(!gate.isPending)
        let answered = gate.end(request)
        #expect(!answered, "its alert or export must not follow")
    }

    @Test func anOldRequestEndingLateLeavesTheNewOneAlone() throws {
        var gate = ExportRequestGate()
        let old = try #require(gate.begin(isExporting: false) as ExportRequestGate.Request?)
        gate.cancel()
        // The sheet is opened again on another selection and Export pressed
        // before the old count has noticed it was stopped.
        let new = try #require(gate.begin(isExporting: false) as ExportRequestGate.Request?)
        let oldAnswered = gate.end(old)
        #expect(!oldAnswered, "the old request's answer is dropped")
        #expect(gate.isPending, "and the new one still holds the gate")
        let third = gate.begin(isExporting: false)
        #expect(third == nil)
        let newAnswered = gate.end(new)
        #expect(newAnswered)
    }

    @Test func endingTwiceAnswersOnce() throws {
        var gate = ExportRequestGate()
        let request = try #require(gate.begin(isExporting: false) as ExportRequestGate.Request?)
        let first = gate.end(request)
        let second = gate.end(request)
        #expect(first && !second)
    }
}

@Suite("Export clashes: a count made while the task was cancelled is not an answer")
struct ExportClashesCancellationTests {
    let folder = URL(fileURLWithPath: "/shoot")

    func context(_ name: String) -> TemplateContext {
        ExportNamingTests().context(name)
    }

    @Test func theCountIsGivenWhenNothingCancels() throws {
        let clashes = try ExportJob.clashes([context("a.NEF"), context("b.NEF")], settings: ExportSettings(),
                                            in: folder, masters: .none,
                                            holdsMasterContent: { $0.lastPathComponent == "a.jpg" },
                                            fileExists: { _ in true })
        #expect(clashes == ExportClashes(existing: 2, masters: 1))
    }

    @Test func aReadCutShortByCancelThrowsInsteadOfCounting() async {
        // The content read is where Cancel lands: `MasterFiles.holdsContent`
        // says "a master" for a read the cancellation cut short, so the count
        // made then would overstate the originals.
        let outcome = await Task {
            Result {
                try ExportJob.clashes([context("a.NEF")], settings: ExportSettings(), in: folder, masters: .none,
                                      holdsMasterContent: { _ in
                                          withUnsafeCurrentTask { $0?.cancel() }
                                          return true
                                      },
                                      fileExists: { _ in true })
            }
        }.value
        #expect(throws: CancellationError.self) { try outcome.get() }
    }
}
