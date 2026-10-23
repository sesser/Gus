import Foundation
import PhotoCore

extension LibraryModel {
    // MARK: Analysis

    /// Queues the masters behind `versionIDs` for on-device analysis. Masters
    /// analyzed before are skipped; ones whose thumbnail cannot be produced
    /// (offline and never cached) stay queued for a later request.
    func suggestKeywords(for versionIDs: [Int64]) {
        guard !versionIDs.isEmpty else { return }
        pendingAnalysis += versionIDs
        startAnalysisIfNeeded()
    }

    private func startAnalysisIfNeeded() {
        guard analysisTask == nil, !pendingAnalysis.isEmpty else { return }
        let catalog = self.catalog
        let previews = self.previews
        let suggester = self.suggester
        analysisTask = Task {
            var done = 0
            var total = 0
            while !pendingAnalysis.isEmpty, !Task.isCancelled {
                let batch = pendingAnalysis
                pendingAnalysis = []
                let targets = (try? await catalog.analysisTargets(forVersions: batch,
                                                                  analysisVersion: suggester.analysisVersion)) ?? []
                total += targets.count
                for item in targets {
                    guard !Task.isCancelled else { break }
                    if let request = previewRequest(for: item, tier: .thumbnail),
                       let image = try? await previews.image(for: request, maxPixelSize: 512, priority: .background),
                       let suggestions = try? await suggester.suggestions(for: image) {
                        try? await catalog.storeSuggestions(suggestions, forImage: item.imageID,
                                                            analysisVersion: suggester.analysisVersion)
                    }
                    done += 1
                    if done.isMultiple(of: 16) || done == total {
                        suggestionProgress = (done, total)
                        suggestionRevision += 1
                    }
                }
            }
            suggestionProgress = nil
            suggestionRevision += 1
            analysisTask = nil
            // Requests that arrived while the last batch finished.
            startAnalysisIfNeeded()
        }
    }

    // MARK: Accepting and dismissing

    /// Adds a suggested keyword to the selected photos it was suggested for.
    func acceptSuggestion(_ name: String) {
        let ids = actionTargetVersionIDs
        guard !ids.isEmpty else { return }
        let acceptance = Pending<SuggestionAcceptance>()
        let catalog = self.catalog
        persist { acceptance.value = try await catalog.acceptSuggestion(name, forVersions: ids) }
        afterPendingWrites { await $0.suggestionsChanged() }
        registerAcceptanceUndo(acceptance, name: name, isUndo: true)
    }

    private func registerAcceptanceUndo(_ acceptance: Pending<SuggestionAcceptance>, name: String, isUndo: Bool) {
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist {
                guard let value = acceptance.value else { return }
                if isUndo {
                    try await catalog.undoSuggestionAcceptance(value, name: name)
                } else {
                    try await catalog.redoSuggestionAcceptance(value, name: name)
                }
            }
            model.afterPendingWrites { await $0.suggestionsChanged() }
            model.registerAcceptanceUndo(acceptance, name: name, isUndo: !isUndo)
        }
        undoManager.setActionName(String(localized: "Add Suggested Keyword", comment: "Undo action name"))
    }

    /// Stops suggesting `name` for the selected photos.
    func dismissSuggestion(_ name: String) {
        let ids = actionTargetVersionIDs
        guard !ids.isEmpty else { return }
        let images = Pending<[Int64]>()
        let catalog = self.catalog
        persist { images.value = try await catalog.dismissSuggestion(name, forVersions: ids) }
        afterPendingWrites { await $0.suggestionsChanged() }
        registerDismissalUndo(images, name: name, ids: ids)
    }

    private func registerDismissalUndo(_ images: Pending<[Int64]>, name: String, ids: [Int64]) {
        let actionName = String(localized: "Hide Suggestion", comment: "Undo action name")
        undoManager.registerUndo(withTarget: self) { model in
            let catalog = model.catalog
            model.persist { try await catalog.reopenSuggestion(name, images: images.value ?? []) }
            model.afterPendingWrites { await $0.suggestionsChanged() }
            model.undoManager.registerUndo(withTarget: model) { model in
                model.persist { _ = try await catalog.dismissSuggestion(name, forVersions: ids) }
                model.afterPendingWrites { await $0.suggestionsChanged() }
                model.registerDismissalUndo(images, name: name, ids: ids)
            }
            model.undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func suggestionsChanged() async {
        suggestionRevision += 1
        await refreshKeywords()
    }
}
