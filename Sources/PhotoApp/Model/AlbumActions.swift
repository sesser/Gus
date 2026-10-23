import Foundation
import PhotoCore

extension LibraryModel {
    // MARK: Names

    func title(for selection: SidebarSelection) -> String {
        switch selection {
        case .allPhotos: String(localized: "All Photos")
        case .builtIn(let album): album.title
        case .year(let year): String(year)
        case .month(let year, let month): MonthText.name(year: year, month: month)
        case .project(let id): projects.first { $0.id == id }?.project.name ?? AppBranding.displayName
        case .album(let id): albums.first { $0.id == id }?.album.name ?? AppBranding.displayName
        case .smartAlbum(let id): smartAlbums.first { $0.id == id }?.name ?? AppBranding.displayName
        case .keyword(let id): keywords.first { $0.id == id }?.name ?? AppBranding.displayName
        case .changedOnDisk: String(localized: "Changed on Disk")
        }
    }

    /// The project the sidebar points at, if any (for new albums).
    var selectedProjectID: Int64? {
        switch sidebarSelection {
        case .project(let id): id
        case .album(let id): albums.first { $0.id == id }?.album.projectId
        case .smartAlbum(let id): smartAlbums.first { $0.id == id }?.projectID
        default: nil
        }
    }

    var currentAlbumID: Int64? {
        if case .album(let id) = sidebarSelection { id } else { nil }
    }

    // MARK: Albums

    /// Creates an album (library-wide when `projectID` is nil) holding
    /// `versionIDs`, and shows it.
    func createAlbum(named name: String, projectID: Int64?, adding versionIDs: [Int64]) {
        guard let name = Catalog.normalizedKeywordName(name) else { return }
        let created = Pending<AlbumRecord>()
        let catalog = self.catalog
        persist {
            let album = try await catalog.createAlbum(name: name, projectID: projectID)
            if let id = album.id, !versionIDs.isEmpty { try await catalog.addVersions(versionIDs, toAlbum: id) }
            created.value = album
        }
        afterPendingWrites { model in
            await model.refreshSidebar()
            if let id = created.value?.id { model.sidebarSelection = .album(id) }
        }
        let actionName = String(localized: "New Album", comment: "Undo action name")
        undoManager.registerUndo(withTarget: self) { model in
            model.deleteAlbum({ created.value?.id }, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    func deleteAlbum(_ id: Int64) {
        deleteAlbum({ id }, actionName: String(localized: "Delete Album", comment: "Undo action name"))
    }

    /// `id` is read when the deletion runs, so it can name an album whose
    /// creation is still queued (the undo of "New Album").
    private func deleteAlbum(_ id: @escaping @MainActor () -> Int64?, actionName: String) {
        let deleted = Pending<DeletedAlbum>()
        let catalog = self.catalog
        persist {
            guard let albumID = id() else { return }
            deleted.value = try await catalog.deleteAlbum(id: albumID)
        }
        afterPendingWrites { await $0.refreshSidebar() }
        undoManager.registerUndo(withTarget: self) { model in
            model.persist { if let album = deleted.value { try await catalog.restoreAlbum(album) } }
            model.afterPendingWrites { await $0.refreshSidebar() }
            model.undoManager.registerUndo(withTarget: model) { $0.deleteAlbum(id, actionName: actionName) }
            model.undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    func renameAlbum(_ id: Int64, to name: String) {
        guard let name = Catalog.normalizedKeywordName(name),
              let previous = albums.first(where: { $0.id == id })?.album.name, previous != name else { return }
        let catalog = self.catalog
        persist { try await catalog.renameAlbum(id: id, to: name) }
        afterPendingWrites { await $0.refreshSidebar() }
        undoManager.registerUndo(withTarget: self) { $0.renameAlbum(id, to: previous) }
        undoManager.setActionName(String(localized: "Rename Album", comment: "Undo action name"))
    }

    /// Adds photos to an album: `versionIDs`, or the selection.
    func addToAlbum(_ albumID: Int64, versionIDs: [Int64]? = nil) {
        let ids = versionIDs ?? actionTargetVersionIDs
        guard !ids.isEmpty else { return }
        let added = Pending<[AlbumMemberRecord]>()
        let catalog = self.catalog
        persist { added.value = try await catalog.addVersions(ids, toAlbum: albumID) }
        afterPendingWrites { await $0.membershipChanged(albumID) }
        registerMembershipUndo(added, albumID: albumID, wereAdded: true,
                               actionName: String(localized: "Add to Album", comment: "Undo action name"))
    }

    /// Takes the selected photos out of the album on screen.
    func removeFromCurrentAlbum() {
        guard let albumID = currentAlbumID else { return }
        let ids = actionTargetVersionIDs
        guard !ids.isEmpty else { return }
        let removed = Pending<[AlbumMemberRecord]>()
        let catalog = self.catalog
        persist { removed.value = try await catalog.removeVersions(ids, fromAlbum: albumID) }
        afterPendingWrites { await $0.membershipChanged(albumID) }
        registerMembershipUndo(removed, albumID: albumID, wereAdded: false,
                               actionName: String(localized: "Remove from Album", comment: "Undo action name"))
    }

    private func registerMembershipUndo(_ members: Pending<[AlbumMemberRecord]>, albumID: Int64, wereAdded: Bool,
                                        actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist {
                let records = members.value ?? []
                if wereAdded {
                    try await catalog.deleteAlbumMembers(records)
                } else {
                    try await catalog.insertAlbumMembers(records)
                }
            }
            model.afterPendingWrites { await $0.membershipChanged(albumID) }
            model.registerMembershipUndo(members, albumID: albumID, wereAdded: !wereAdded, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func membershipChanged(_ albumID: Int64) async {
        await refreshSidebar()
        // Unlike a filter, an album's contents are what you put in it: show the change.
        if currentAlbumID == albumID { reloadItems(keepFocus: true) }
    }

    // MARK: Smart albums

    func createSmartAlbum(named name: String, projectID: Int64?, rules: SmartAlbumRules) {
        guard let name = Catalog.normalizedKeywordName(name) else { return }
        let created = Pending<SmartAlbum>()
        let catalog = self.catalog
        persist { created.value = try await catalog.createSmartAlbum(name: name, projectID: projectID, rules: rules) }
        afterPendingWrites { model in
            await model.refreshSidebar()
            if let id = created.value?.id { model.sidebarSelection = .smartAlbum(id) }
        }
        let actionName = String(localized: "New Smart Album", comment: "Undo action name")
        undoManager.registerUndo(withTarget: self) { model in
            model.deleteSmartAlbum({ created.value?.id }, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Saves edits to a smart album (name, project, rules).
    func saveSmartAlbum(_ album: SmartAlbum) {
        guard let previous = smartAlbums.first(where: { $0.id == album.id }), previous != album else { return }
        let catalog = self.catalog
        persist { try await catalog.saveSmartAlbum(album) }
        afterPendingWrites { model in
            await model.refreshSidebar()
            if model.sidebarSelection == .smartAlbum(album.id) { model.reloadItems(keepFocus: true) }
        }
        undoManager.registerUndo(withTarget: self) { $0.saveSmartAlbum(previous) }
        undoManager.setActionName(String(localized: "Edit Smart Album", comment: "Undo action name"))
    }

    func deleteSmartAlbum(_ id: Int64) {
        deleteSmartAlbum({ id }, actionName: String(localized: "Delete Smart Album", comment: "Undo action name"))
    }

    private func deleteSmartAlbum(_ id: @escaping @MainActor () -> Int64?, actionName: String) {
        let deleted = Pending<SmartAlbum>()
        let catalog = self.catalog
        persist {
            guard let albumID = id() else { return }
            deleted.value = try await catalog.deleteSmartAlbum(id: albumID)
        }
        afterPendingWrites { await $0.refreshSidebar() }
        undoManager.registerUndo(withTarget: self) { model in
            model.persist { if let album = deleted.value { try await catalog.saveSmartAlbum(album) } }
            model.afterPendingWrites { await $0.refreshSidebar() }
            model.undoManager.registerUndo(withTarget: model) { $0.deleteSmartAlbum(id, actionName: actionName) }
            model.undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Photos matching `rules` (within the project, if any), for the editor's
    /// live count.
    func countMatching(_ rules: SmartAlbumRules, projectID: Int64?) async -> Int? {
        try? await catalog.itemCount(matching: LibraryFilter(scope: .rules(rules, projectID: projectID),
                                                             groupsPairs: groupPairs))
    }
}

extension BuiltInAlbum {
    var title: String {
        switch self {
        case .lastImport: String(localized: "Last Import")
        case .picks: String(localized: "Picks")
        case .rejects: String(localized: "Rejects")
        case .unrated: String(localized: "Unrated")
        case .noKeywords: String(localized: "No Keywords")
        }
    }

    var symbol: String {
        switch self {
        case .lastImport: "clock.arrow.circlepath"
        case .picks: "flag"
        case .rejects: "xmark.circle"
        case .unrated: "star.slash"
        case .noKeywords: "tag.slash"
        }
    }
}

enum MonthText {
    static func name(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return "\(year)-\(month)" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    static func monthOnly(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return "\(month)" }
        return date.formatted(.dateTime.month(.wide))
    }
}
