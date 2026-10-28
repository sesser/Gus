import AppKit
import PhotoCore

extension LibraryModel {
    // MARK: Copy and paste

    /// Remembers the focused photo's adjustments for Paste Adjustments.
    func copyAdjustments() {
        guard let item = focusedItem else { return }
        if editor.item?.versionID == item.versionID, editor.state == .ready {
            copiedAdjustments = editor.adjustments
            return
        }
        let catalog = self.catalog
        Task {
            let stack = (try? await catalog.version(id: item.versionID)?.decodedEditStack()) ?? .identity
            copiedAdjustments = Adjustments(stack: stack)
        }
    }

    /// Gives the selection (grid) or the photo on screen (loupe) the copied adjustments.
    func pasteAdjustments() {
        guard let copiedAdjustments else { return }
        applyAdjustments(copiedAdjustments, toVersions: actionTargetVersionIDs,
                         actionName: String(localized: "Paste Adjustments", comment: "Undo action name"))
    }

    // MARK: Applying to many photos

    /// Replaces the adjustments of `ids` (keeping operations this build does not
    /// know), as one undo step.
    func applyAdjustments(_ values: Adjustments, toVersions ids: [Int64], actionName: String) {
        changeAdjustments(ofVersions: ids, actionName: actionName) { values.pasted(onto: $0) }
    }

    /// Gives each of `ids` `transform` of its adjustments, as one undo step.
    func changeAdjustments(ofVersions ids: [Int64], actionName: String,
                           _ transform: @escaping @Sendable (Adjustments) -> Adjustments) {
        guard !ids.isEmpty else { return }
        let change = Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>()
        let catalog = self.catalog
        persist {
            let before = try await catalog.editStacks(forVersions: ids)
            let after = before.mapValues { transform(Adjustments(stack: $0)).editStack }
            try await catalog.setEditStacks(after)
            change.value = (before, after)
        }
        afterPendingWrites { model in
            if let value = change.value { model.showEditStacks(value.after) }
        }
        registerEditStacksUndo(change, isUndo: true, actionName: actionName)
    }

    private func registerEditStacksUndo(_ change: Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>,
                                        isUndo: Bool, actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist {
                guard let value = change.value else { return }
                try await catalog.setEditStacks(isUndo ? value.before : value.after)
            }
            model.afterPendingWrites { model in
                if let value = change.value { model.showEditStacks(isUndo ? value.before : value.after) }
            }
            model.registerEditStacksUndo(change, isUndo: !isUndo, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    /// Shows saved stacks in the grid, the loupe and the Adjust tab.
    private func showEditStacks(_ stacks: [Int64: EditStack]) {
        for (id, stack) in stacks {
            setEditStackHash(stack.renderHash, forVersion: id)
            editor.catalogChanged(stack, forVersion: id)
        }
    }
}
