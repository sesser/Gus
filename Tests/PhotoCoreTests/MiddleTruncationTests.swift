import Testing
@testable import PhotoCore

@Suite("Middle truncation")
struct MiddleTruncationTests {
    /// One unit per character.
    let width: (String) -> Double = { Double($0.count) }
    let line: (String) -> String = { "Export to “\($0)”" }

    @Test func truncatesInTheMiddle() {
        #expect(MiddleTruncation.truncate("Exports", keeping: 4) == "Ex…ts")
        #expect(MiddleTruncation.truncate("Exports", keeping: 3) == "Ex…s")
        #expect(MiddleTruncation.truncate("Exports", keeping: 7) == "Exports")
        #expect(MiddleTruncation.truncate("Exports", keeping: 0) == "…")
    }

    @Test func leavesALineThatFits() {
        #expect(MiddleTruncation.fit("Exports", maxWidth: 40, line: line, width: width) == "Export to “Exports”")
    }

    @Test func shortensOnlyTheName() {
        // "Export to “”" is 12; 17 leaves 5, the ellipsis and 4 characters.
        let fitted = MiddleTruncation.fit("Exports", maxWidth: 17, line: line, width: width)
        #expect(fitted == "Export to “Ex…ts”")
        #expect(fitted.hasPrefix("Export to “") && fitted.hasSuffix("”"))
        #expect(width(fitted) <= 17)
    }

    @Test func keepsTheCountsAfterTheName() {
        let counts: (String) -> String = { "Reading \($0)… 12 of 412" }
        let fitted = MiddleTruncation.fit("Untitled Card", maxWidth: 24, line: counts, width: width)
        #expect(fitted.hasSuffix("… 12 of 412"))
        #expect(width(fitted) <= 24)
    }

    @Test func stopsAtTwoCharacters() {
        #expect(MiddleTruncation.fit("Exports", maxWidth: 5, line: line, width: width) == "Export to “E…s”")
    }
}
