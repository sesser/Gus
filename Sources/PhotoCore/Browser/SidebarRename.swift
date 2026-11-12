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

    /// Whether the row is in the sidebar's list: the sidebar is shown, its
    /// section is turned on and expanded, and for a project's album the
    /// project is expanded. A row scrolled out of view is still listed.
    public func isListed(in list: SidebarListState) -> Bool {
        guard list.showsSidebar else { return false }
        switch self {
        case .albums: return list.albumsOpen
        case .projects(let project): return list.projectsOpen && (project.map(list.expandedProjects.contains) ?? true)
        }
    }
}

/// How much of the sidebar's list is open, as far as rows that rename in
/// place go. When a change here takes a row being renamed out of the list
/// (its section hidden or folded, its project folded, the sidebar hidden),
/// the rename ends, saved, as when the keyboard moves elsewhere
/// (docs/features/rename-albums-in-place/design.md §2.3; code review C1).
public struct SidebarListState: Equatable, Sendable {
    public var showsSidebar: Bool
    /// The Albums section is turned on (View ▸ Sidebar Sections) and expanded.
    public var albumsOpen: Bool
    /// The same for the Projects section.
    public var projectsOpen: Bool
    /// The projects whose albums are disclosed.
    public var expandedProjects: Set<Int64>

    public init(showsSidebar: Bool, albumsOpen: Bool, projectsOpen: Bool, expandedProjects: Set<Int64>) {
        self.showsSidebar = showsSidebar
        self.albumsOpen = albumsOpen
        self.projectsOpen = projectsOpen
        self.expandedProjects = expandedProjects
    }

    /// Whether the change from `old` to this state took the row out of the list.
    public func removed(_ place: SidebarRowPlace, since old: SidebarListState) -> Bool {
        place.isListed(in: old) && !place.isListed(in: self)
    }
}
