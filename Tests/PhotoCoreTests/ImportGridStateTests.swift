import Testing
@testable import PhotoCore

@Suite("Import grid state")
struct ImportGridStateTests {
    func state(source: Bool = true, scanning: Bool = false, error: String? = nil, shots: Int = 0,
               duplicates: Int = 0, showing: Bool = false) -> ImportGridState {
        .of(hasSource: source, isScanning: scanning, readError: error, shotCount: shots,
            duplicateCount: duplicates, showsDuplicates: showing)
    }

    @Test func followsTheStatesTable() {
        #expect(state(source: false) == .noSource)
        #expect(state(scanning: true) == .scanning)
        #expect(state() == .noPhotos)
        #expect(state(error: "Permission denied") == .readError("Permission denied"))
        #expect(state(shots: 412, duplicates: 412) == .allImported(count: 412))
        #expect(state(shots: 412, duplicates: 412, showing: true) == .shots)
        #expect(state(shots: 412, duplicates: 10) == .shots)
        // Shots stay on screen while a rescan runs.
        #expect(state(scanning: true, shots: 3) == .shots)
    }
}

@Suite("Grid moves")
struct GridMoveTests {
    @Test func movesAndClamps() {
        #expect(GridMove.right.target(from: 0, columns: 4, count: 10, pageRows: 2) == 1)
        #expect(GridMove.left.target(from: 0, columns: 4, count: 10, pageRows: 2) == 0)
        #expect(GridMove.down.target(from: 1, columns: 4, count: 10, pageRows: 2) == 5)
        #expect(GridMove.down.target(from: 8, columns: 4, count: 10, pageRows: 2) == 9)
        #expect(GridMove.up.target(from: 2, columns: 4, count: 10, pageRows: 2) == 0)
        #expect(GridMove.pageDown.target(from: 0, columns: 4, count: 10, pageRows: 2) == 8)
        #expect(GridMove.end.target(from: 0, columns: 4, count: 10, pageRows: 2) == 9)
        #expect(GridMove.home.target(from: 7, columns: 4, count: 10, pageRows: 2) == 0)
    }

    @Test func startsAtTheFirstItem() {
        #expect(GridMove.down.target(from: nil, columns: 4, count: 10, pageRows: 2) == 0)
        #expect(GridMove.down.target(from: nil, columns: 4, count: 0, pageRows: 2) == nil)
    }
}
