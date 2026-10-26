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

    // MARK: Presets

    func refreshAdjustmentPresets() async {
        adjustmentPresets = (try? await catalog.adjustmentPresets()) ?? []
    }

    /// Saves the focused photo's adjustments under `name` (replacing a preset of that name).
    func saveAdjustmentPreset(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let item = focusedItem else { return }
        let catalog = self.catalog
        let loaded = editor.item?.versionID == item.versionID && editor.state == .ready ? editor.adjustments : nil
        Task {
            let values: Adjustments
            if let loaded {
                values = loaded
            } else {
                values = Adjustments(stack: (try? await catalog.version(id: item.versionID)?.decodedEditStack()) ?? .identity)
            }
            do {
                _ = try await catalog.saveAdjustmentPreset(AdjustmentPreset(name: name, adjustments: values))
            } catch {
                statusMessage = String(localized: "Could not save the preset: \(error.localizedDescription)")
            }
            await refreshAdjustmentPresets()
        }
    }

    func applyAdjustmentPreset(_ preset: AdjustmentPreset) {
        applyAdjustments(preset.adjustments, toVersions: actionTargetVersionIDs,
                         actionName: String(localized: "Apply Preset \(preset.name)", comment: "Undo action name"))
    }

    func deleteAdjustmentPreset(_ preset: AdjustmentPreset) {
        guard let id = preset.id else { return }
        let catalog = self.catalog
        Task {
            try? await catalog.deleteAdjustmentPreset(id: id)
            await refreshAdjustmentPresets()
        }
    }

    /// Asks for a name, then saves a preset.
    func promptForAdjustmentPreset() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Preset")
        alert.informativeText = String(localized: "The photo's adjustments are saved under this name. A preset with the same name is replaced.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = String(localized: "Preset name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        saveAdjustmentPreset(named: field.stringValue)
    }

    // MARK: Applying to many photos

    /// Replaces the adjustments of `ids` (keeping operations this build does not
    /// know), as one undo step.
    func applyAdjustments(_ values: Adjustments, toVersions ids: [Int64], actionName: String) {
        guard !ids.isEmpty else { return }
        let change = Pending<(before: [Int64: EditStack], after: [Int64: EditStack])>()
        let catalog = self.catalog
        persist {
            let before = try await catalog.editStacks(forVersions: ids)
            let after = before.mapValues { values.pasted(onto: Adjustments(stack: $0)).editStack }
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
