/// What the browser shows when the selected source has no photos to show
/// (docs/features/ui-redesign/design.md N3); the UI puts it into words.
public enum EmptySourceState: Hashable, Sendable {
    /// The library has no photos at all: "No Photos Yet" with the import buttons.
    case emptyLibrary
    /// The source has photos, but a filter hides them all: "No Photos Match".
    case noMatches
    /// The source itself is empty: "No Photos in “‹source›”".
    case emptySource(SourceKind)

    /// The kinds of source whose empty state says more than its title.
    public enum SourceKind: Hashable, Sendable {
        /// Explains how photos get into an album.
        case album
        /// Explains that no photo meets the rules, and offers to edit them.
        case smartAlbum
        /// Everything else (All Photos, built-in albums, dates, keywords,
        /// projects, Changed on Disk): the title only.
        case other
    }

    /// The state for a source showing `shownCount` photos, or nil while it
    /// shows any. An empty library wins over a filter, and a filter over the
    /// source's own state.
    public static func resolve(shownCount: Int, libraryCount: Int, isFiltered: Bool,
                               source: SourceKind) -> EmptySourceState? {
        guard shownCount == 0 else { return nil }
        if libraryCount == 0 { return .emptyLibrary }
        if isFiltered { return .noMatches }
        return .emptySource(source)
    }
}
