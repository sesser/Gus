import PhotoCore
import PhotoUI
import SwiftUI

/// The Spots commands of the menu bar, the loupe's context menu, keys and
/// the toolbar (docs/features/healing/design.md §6).
extension LibraryModel {
    /// Edit Spots can act: an editable photo in the loupe, no crop session,
    /// not reviewing, not comparing (design §6, §8).
    var canEditSpots: Bool {
        mode == .loupe && focusedItem?.isVideo == false && editor.canEditSpots && !isReviewing && !isComparing
    }

    /// The tool on or off. From a menu, a key or the context menu, turning
    /// it on shows the inspector on Adjust with the Spots heading open (design §2).
    func toggleEditingSpots(revealing: Bool = true) {
        if editor.isEditingSpots {
            editor.setEditingSpots(false)
            return
        }
        guard canEditSpots else { return }
        editor.setEditingSpots(true)
        guard editor.isEditingSpots, revealing else { return }
        showsInspector = true
        inspectorTab = .adjust
        InspectorExpansion.shared.set(SpotsSection.key, true)
    }

    func toggleSpotOverlay() {
        guard editor.isEditingSpots else { return }
        editor.showsSpotOverlay.toggle()
    }

    /// A direction of the option-arrow keys and the Move Spot ▸ and Move Source ▸ items.
    enum SpotNudge: CaseIterable {
        case left, right, up, down

        var vector: (dx: Double, dy: Double) {
            switch self {
            case .left: (-1, 0)
            case .right: (1, 0)
            case .up: (0, -1)
            case .down: (0, 1)
            }
        }
    }

    /// One screen point at the loupe's zoom, or ten with Shift (design §6).
    func nudgeSpot(_ direction: SpotNudge, source: Bool, large: Bool) {
        guard canEditSpots, editor.selectedSpotID != nil else { return }
        let step = editor.spotNudgeStep, factor = large ? 10.0 : 1.0
        editor.nudgeSelectedSpot(dx: direction.vector.dx * Double(step.width) * factor,
                                 dy: direction.vector.dy * Double(step.height) * factor, source: source)
    }
}
