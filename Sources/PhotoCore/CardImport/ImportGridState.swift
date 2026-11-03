import Foundation

/// What the import window's grid area shows (the states table in section 8
/// of docs/UI_REDESIGN.md).
public enum ImportGridState: Equatable, Sendable {
    /// "Insert a Card or Choose a Folder".
    case noSource
    /// "Reading ‹source›…" until the first shots appear.
    case scanning
    /// "Can't Read ‹source›" with the error and Rescan.
    case readError(String)
    /// "No Photos on ‹source›".
    case noPhotos
    /// "All N Photos Are Already in the Library" with Show Them.
    case allImported(count: Int)
    /// The grid.
    case shots

    public static func of(hasSource: Bool, isScanning: Bool, readError: String?, shotCount: Int,
                          duplicateCount: Int, showsDuplicates: Bool) -> ImportGridState {
        guard hasSource else { return .noSource }
        if let readError { return .readError(readError) }
        if shotCount == 0 { return isScanning ? .scanning : .noPhotos }
        if duplicateCount == shotCount, !showsDuplicates { return .allImported(count: shotCount) }
        return .shots
    }
}

/// Keyboard moves in a grid of `count` items in rows of `columns`.
public enum GridMove: Sendable {
    case left, right, up, down, home, end, pageUp, pageDown

    /// The item a move from `current` lands on; nil when there are none.
    /// With no current item, any move starts at the first.
    public func target(from current: Int?, columns: Int, count: Int, pageRows: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        let columns = max(1, columns)
        let page = columns * max(1, pageRows)
        let target = switch self {
        case .left: current - 1
        case .right: current + 1
        case .up: current - columns
        case .down: current + columns
        case .home: 0
        case .end: count - 1
        case .pageUp: current - page
        case .pageDown: current + page
        }
        return min(max(target, 0), count - 1)
    }
}
