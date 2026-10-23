import Foundation
import PhotoCore

/// The photos an open keyword field will tag, fixed when it opens.
struct KeywordEntryRequest: Identifiable, Equatable {
    let id = UUID()
    let versionIDs: [Int64]
}

/// A result that a queued catalog write fills in. Later steps on the write chain
/// (such as the undo of that write) read it; by then it is set.
@MainActor
final class Pending<Value> {
    var value: Value?
}

extension Notification.Name {
    /// The grid or loupe, whichever is showing, should take keyboard focus back
    /// (after the keyword field closes, for instance).
    static let browserShouldTakeFocus = Notification.Name("browserShouldTakeFocus")
}

extension LibraryModel {
    // MARK: Keyword field

    var keywordNames: [String] { keywords.map(\.name) }

    func beginKeywordEntry() {
        let ids = actionTargetVersionIDs
        guard !ids.isEmpty else { return }
        keywordEntry = KeywordEntryRequest(versionIDs: ids)
    }

    func endKeywordEntry(adding names: [String]) {
        if let request = keywordEntry, !names.isEmpty {
            addKeywords(names, to: request.versionIDs)
        }
        keywordEntry = nil
        NotificationCenter.default.post(name: .browserShouldTakeFocus, object: self)
    }

    // MARK: Assigning

    /// Adds keywords (creating new ones) to `versionIDs`, or to the selection.
    func addKeywords(_ names: [String], to versionIDs: [Int64]? = nil) {
        let names = ImageMetadata.uniqueKeywords(names)
        let ids = versionIDs ?? actionTargetVersionIDs
        guard !names.isEmpty, !ids.isEmpty else { return }
        let addition = Pending<KeywordAddition>()
        let catalog = self.catalog
        persist { addition.value = try await catalog.addKeywords(named: names, toVersions: ids) }
        afterPendingWrites { await $0.refreshKeywords() }
        let actionName = names.count == 1
            ? String(localized: "Add Keyword", comment: "Undo action name")
            : String(localized: "Add Keywords", comment: "Undo action name")
        registerAdditionUndo(addition, isUndo: true, actionName: actionName)
    }

    /// Undo takes away what the addition added, including keywords it created;
    /// redo puts it all back.
    private func registerAdditionUndo(_ addition: Pending<KeywordAddition>, isUndo: Bool, actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist {
                guard let value = addition.value else { return }
                if isUndo {
                    try await catalog.undoKeywordAddition(value)
                } else {
                    try await catalog.redoKeywordAddition(value)
                }
            }
            model.afterPendingWrites { await $0.refreshKeywords() }
            model.registerAdditionUndo(addition, isUndo: !isUndo, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Removes a keyword from `versionIDs`, or from the selection.
    func removeKeyword(_ keywordID: Int64, from versionIDs: [Int64]? = nil) {
        let ids = versionIDs ?? actionTargetVersionIDs
        guard !ids.isEmpty else { return }
        let removed = Pending<[VersionKeywordRecord]>()
        let catalog = self.catalog
        persist { removed.value = try await catalog.removeKeywords([keywordID], fromVersions: ids) }
        afterPendingWrites { await $0.refreshKeywords() }
        registerAssignmentUndo(removed, wereAdded: false,
                               actionName: String(localized: "Remove Keyword", comment: "Undo action name"))
    }

    /// Undo of a remove puts back exactly what it removed; redo removes it again.
    private func registerAssignmentUndo(_ assignments: Pending<[VersionKeywordRecord]>, wereAdded: Bool,
                                        actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist {
                let records = assignments.value ?? []
                if wereAdded {
                    try await catalog.deleteKeywordAssignments(records)
                } else {
                    try await catalog.insertKeywordAssignments(records)
                }
            }
            model.afterPendingWrites { await $0.refreshKeywords() }
            model.registerAssignmentUndo(assignments, wereAdded: !wereAdded, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Managing keywords

    /// Renames a keyword; renaming onto another keyword's name merges into it.
    func renameKeyword(_ keywordID: Int64, to name: String) {
        guard Catalog.normalizedKeywordName(name) != nil else { return }
        let result = Pending<KeywordRename>()
        let catalog = self.catalog
        persist { result.value = try await catalog.renameKeyword(id: keywordID, to: name) }
        afterPendingWrites { model in
            if case .merged(let merge)? = result.value {
                model.statusMessage = String(localized: "Merged “\(merge.source.keyword.name)” into “\(merge.target.name)”.")
                if model.sidebarSelection == .keyword(keywordID), let target = merge.target.id {
                    model.sidebarSelection = .keyword(target)
                }
            }
            await model.refreshKeywords()
        }
        let actionName = String(localized: "Rename Keyword", comment: "Undo action name")
        undoManager.registerUndo(withTarget: self) { model in
            model.persist {
                switch result.value {
                case .renamed(let previous)?: _ = try await catalog.renameKeyword(id: keywordID, to: previous)
                case .merged(let merge)?: try await catalog.undoKeywordMerge(merge)
                case .unchanged?, nil: break
                }
            }
            model.afterPendingWrites { await $0.refreshKeywords() }
            model.undoManager.registerUndo(withTarget: model) { $0.renameKeyword(keywordID, to: name) }
            model.undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Deletes a keyword from the library (the photos stay).
    func deleteKeyword(_ keywordID: Int64) {
        let deleted = Pending<DeletedKeyword>()
        let catalog = self.catalog
        if sidebarSelection == .keyword(keywordID) { sidebarSelection = .allPhotos }
        persist { deleted.value = try await catalog.deleteKeyword(id: keywordID) }
        afterPendingWrites { await $0.refreshKeywords() }
        let actionName = String(localized: "Delete Keyword", comment: "Undo action name")
        undoManager.registerUndo(withTarget: self) { model in
            model.persist {
                if let keyword = deleted.value { try await catalog.restoreKeyword(keyword) }
            }
            model.afterPendingWrites { await $0.refreshKeywords() }
            model.undoManager.registerUndo(withTarget: model) { $0.deleteKeyword(keywordID) }
            model.undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }
}
