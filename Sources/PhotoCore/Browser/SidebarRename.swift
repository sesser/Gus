import Foundation

/// How each kind of sidebar item is renamed
/// (docs/features/rename-albums-in-place/design.md §3 and §4). Projects and
/// albums are plain names the library owns, so their row's name becomes a
/// text field. A keyword keeps its sheet, which explains that the name of
/// another keyword merges the two. A smart album has no Rename: its name is
/// the first field of its editor.
public enum SidebarRenameRoute: Equatable, Sendable {
    /// In the row: File ▸ Rename “‹name›”, the row menu's Rename, Return.
    case inPlace
    /// A sheet follows: File ▸ Rename “‹name›”… and the row menu's Rename….
    case sheet

    /// The kinds of sidebar item a person makes and names.
    public enum Item: Equatable, Sendable, CaseIterable {
        case project, album, smartAlbum, keyword
    }

    /// Nil when the item has no Rename.
    public static func route(for item: Item) -> SidebarRenameRoute? {
        switch item {
        case .project, .album: .inPlace
        case .keyword: .sheet
        case .smartAlbum: nil
        }
    }

    /// Whether the menu title ends in an ellipsis: only when more input
    /// follows the choice.
    public var titleHasEllipsis: Bool { self == .sheet }
}

/// Where a row that can be renamed in place lives in the sidebar, for
/// showing it before File ▸ Rename edits it (design §2.5): the section to
/// turn on and expand, and the project to expand for one of its albums.
public enum SidebarRowPlace: Equatable, Sendable {
    /// The Albums section: an album of the whole library.
    case albums
    /// The Projects section: a project's own row, or an album under
    /// `expanding`, its project.
    case projects(expanding: Int64?)

    public static var project: SidebarRowPlace { .projects(expanding: nil) }

    public static func album(inProject projectID: Int64?) -> SidebarRowPlace {
        projectID.map { .projects(expanding: $0) } ?? .albums
    }
}
