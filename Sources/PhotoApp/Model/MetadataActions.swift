import Foundation
import PhotoCore

extension LibraryModel {
    /// Sets a descriptive field on `versionIDs` (and their pair partners) as
    /// one undo step; nil or blank text clears it.
    func setDescriptiveField(_ field: DescriptiveField, to value: String?, for versionIDs: [Int64]) {
        guard !versionIDs.isEmpty else { return }
        let change = Pending<DescriptiveChange>()
        let catalog = self.catalog
        persist { change.value = try await catalog.setDescriptiveField(field, to: value, forVersions: versionIDs) }
        afterPendingWrites { $0.descriptionRevision += 1 }
        registerDescriptiveUndo(change, actionName: String(
            localized: "Change \(DescriptiveFieldText.name(field))",
            comment: "Undo action name; the argument is a metadata field such as Title"))
    }

    /// Undo and redo both put back the values the last step replaced, and
    /// keep the ones they replace for the next step.
    private func registerDescriptiveUndo(_ change: Pending<DescriptiveChange>, actionName: String) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist {
                guard let previous = change.value else { return }
                change.value = try await catalog.restoreDescriptiveField(previous)
            }
            model.afterPendingWrites { $0.descriptionRevision += 1 }
            model.registerDescriptiveUndo(change, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
