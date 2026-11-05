import Foundation

/// The background jobs File ▸ Stop (⌘.) can stop from the library window
/// (design.md I4); the UI names them ("Stop Export"…). Other jobs keep their
/// Stop in the Activity popover only.
public enum StoppableJob: String, Hashable, Sendable, CaseIterable {
    case export
    /// Folders added without copying (and folder drops).
    case addFolders
    /// A copying import from a card or folder.
    case cardImport

    /// The job started last among those running, by start time; nil when
    /// none runs. Equal times go to the order of `allCases`, last first.
    public static func newest(_ running: [StoppableJob: Date]) -> StoppableJob? {
        running.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (allCases.firstIndex(of: lhs.key) ?? 0) < (allCases.firstIndex(of: rhs.key) ?? 0)
        }?.key
    }
}
