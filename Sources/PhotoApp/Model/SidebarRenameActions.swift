import AppKit
import Observation
import PhotoCore
import PhotoUI

/// A project's or an album's name being edited in its sidebar row: which
/// row, and the text so far. The text lives here, not in the field, so that
/// a rename started on another row can save this one first.
@MainActor
@Observable
final class SidebarRename {
    let item: SidebarSelection
    var draft: String

    init(item: SidebarSelection, name: String) {
        self.item = item
        draft = name
    }
}

/// A request to bring a sidebar row into view.
struct SidebarReveal: Equatable {
    var item: SidebarSelection
    /// Open what hides the row first: its section and, for a project's
    /// album, the project. False only scrolls.
    var opensContainers: Bool
    /// Tells one request from the next for the same row.
    var revision: Int
}

extension SidebarSelection {
    /// How this row is renamed, if it can be (`SidebarRenameRoute`).
    var renameRoute: SidebarRenameRoute? {
        switch self {
        case .project: SidebarRenameRoute.route(for: .project)
        case .album: SidebarRenameRoute.route(for: .album)
        case .smartAlbum: SidebarRenameRoute.route(for: .smartAlbum)
        case .keyword: SidebarRenameRoute.route(for: .keyword)
        case .allPhotos, .builtIn, .year, .month, .changedOnDisk: nil
        }
    }
}

/// Renaming a project or an album in place in the sidebar
/// (docs/features/library-ops/design.md §4 and
/// docs/features/rename-albums-in-place/design.md §2): File ▸ Rename, the
/// row's Rename and Return all start it here, and the row's field ends it
/// here. Saving goes on to `renameProject` or `renameAlbum`.
extension LibraryModel {
    /// The name of a row that is renamed in place, nil for any other row and
    /// for a project or album that is gone.
    private func inPlaceName(of item: SidebarSelection) -> String? {
        switch item {
        case .project(let id): projects.first { $0.id == id }?.project.name
        case .album(let id): albums.first { $0.id == id }?.album.name
        default: nil
        }
    }

    /// Where a project's or an album's row lives in the sidebar.
    func sidebarRowPlace(of item: SidebarSelection) -> SidebarRowPlace? {
        switch item {
        case .project(let id): projects.contains { $0.id == id } ? .project : nil
        case .album(let id): albums.first { $0.id == id }.map { .album(inProject: $0.album.projectId) }
        default: nil
        }
    }

    /// Puts a project's or an album's sidebar row into editing, making the
    /// row visible first, every time: the sidebar, the row's section, the
    /// project of a project's album, the row. One row at a time: a rename
    /// open on another row ends first, saved, as when the keyboard moves
    /// elsewhere. A rename already open on this row keeps what was typed and
    /// is shown again.
    func beginSidebarRename(_ item: SidebarSelection) {
        guard item.renameRoute == .inPlace, let name = inPlaceName(of: item), let place = sidebarRowPlace(of: item) else { return }
        if let open = sidebarRename, open.item != item { endSidebarRename(open, save: true) }
        showsSidebar = true
        switch place {
        case .albums: setSidebarSection(.albums, shown: true)
        case .projects: setSidebarSection(.projects, shown: true)
        }
        if sidebarRename == nil { sidebarRename = SidebarRename(item: item, name: name) }
        revealSidebarRow(item, opening: true)
    }

    /// The sidebar's list changed what it shows. If that took the row being
    /// renamed out of the list (its section hidden or folded, its project
    /// folded, the sidebar hidden), its field went with it and can no longer
    /// end the rename: it ends here, saved, as when the keyboard moves
    /// elsewhere. Returns whether a rename ended.
    @discardableResult
    func sidebarListChanged(from old: SidebarListState, to new: SidebarListState) -> Bool {
        guard let rename = sidebarRename, let place = sidebarRowPlace(of: rename.item),
              new.removed(place, since: old) else { return false }
        endSidebarRename(rename, save: true)
        return true
    }

    /// The row's field ended. `save` is false for Escape: the old name
    /// stays. An empty name is refused with the alert sound, and VoiceOver is
    /// told why. A field that is no longer the open rename is ignored, so
    /// each rename ends once.
    func endSidebarRename(_ rename: SidebarRename, save: Bool) {
        guard sidebarRename === rename else { return }
        sidebarRename = nil
        guard save, let current = inPlaceName(of: rename.item) else { return }
        switch InPlaceRename.resolve(typed: rename.draft, current: current) {
        case .rename(let name):
            switch rename.item {
            case .project(let id): renameProject(id, to: name)
            case .album(let id): renameAlbum(id, to: name)
            default: break
            }
        case .unchanged:
            break
        case .refused:
            NSSound.beep()
            AccessibilityText.announce(LibraryOpsText.emptyName)
        }
    }

    /// The project or album being renamed was removed or deleted under its
    /// field: nothing is left to name.
    func endSidebarRenameIfGone() {
        if let rename = sidebarRename, inPlaceName(of: rename.item) == nil { sidebarRename = nil }
    }
}

/// The words of the in-place rename that are an album's own; the rest are
/// shared with projects (`LibraryOpsText`).
enum SidebarRenameText {
    static var albumNameLabel: String {
        String(localized: "Album name", comment: "VoiceOver's label for an album's name field in the sidebar")
    }

    /// The accessibility label of the field in a row being renamed.
    static func fieldLabel(for item: SidebarSelection) -> String {
        if case .album = item { albumNameLabel } else { LibraryOpsText.projectNameLabel }
    }
}
