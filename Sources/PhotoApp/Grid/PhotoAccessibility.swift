import AppKit
import PhotoCore
import PhotoUI

/// What VoiceOver says about a photo in the grid or the loupe, and what it
/// can do to it (section 10 of docs/UI_REDESIGN.md).
@MainActor
enum PhotoAccessibility {
    /// "DSC00231, RAW plus JPEG".
    static func label(for item: CatalogItem) -> String {
        var kinds = item.fileKind.map { [$0] } ?? []
        if item.representsPair, let partner = item.partnerKind { kinds.append(partner) }
        return AccessibilityText.list([item.baseName, AccessibilityText.fileType(kinds)])
    }

    /// "3 stars, Picked, Red label, Offline"; empty for a photo nobody culled.
    static func value(for item: CatalogItem, offline: Bool) -> String {
        AccessibilityText.list(CullingDescription.value(rating: item.rating, flag: item.flag, colorLabel: item.colorLabel,
                                                        offline: offline).map(text))
    }

    static func text(_ part: CullingDescription.Part) -> String {
        switch part {
        case .rating(let rating) where rating == .unrated: String(localized: "No Rating")
        case .rating(let rating): String(localized: "\(rating.rawValue) stars", comment: "VoiceOver: a photo's star rating")
        case .flag(.picked): String(localized: "Picked")
        case .flag(.rejected): String(localized: "Rejected")
        case .flag(.none): String(localized: "Unflagged")
        case .colorLabel(.none): String(localized: "No Label")
        case .colorLabel(let label):
            String(localized: "\(ColorLabelText.name(label)) label", comment: "VoiceOver: a photo's color label, as in “Red label”")
        case .offline: String(localized: "Offline")
        }
    }

    /// What a culling action announces, read from the photo it changed.
    static func announcement(for action: CullingAction, item: CatalogItem) -> String {
        let change: CullingDescription.Change = switch action {
        case .setRating, .adjustRating: .rating
        case .setFlag: .flag
        case .setColorLabel: .colorLabel
        }
        return text(CullingDescription.announcement(of: change, rating: item.rating, flag: item.flag,
                                                    colorLabel: item.colorLabel))
    }

    /// The culling actions VoiceOver offers on a photo, applied the way a
    /// context menu would (`LibraryModel.performAccessibilityAction`). The grid
    /// adds Open in Loupe.
    static func actions(forVersion versionID: Int64, model: LibraryModel, opensLoupe: Bool) -> [NSAccessibilityCustomAction] {
        var actions: [NSAccessibilityCustomAction] = []
        if opensLoupe {
            actions.append(NSAccessibilityCustomAction(name: String(localized: "Open in Loupe")) { @Sendable [weak model] in
                MainActor.assumeIsolated { model?.openLoupe(onVersion: versionID) }
                return true
            })
        }
        let culling: [(String, CullingAction)] = [
            (String(localized: "Raise Rating"), .adjustRating(1)),
            (String(localized: "Lower Rating"), .adjustRating(-1)),
            (String(localized: "Pick"), .setFlag(.picked)),
            (String(localized: "Reject"), .setFlag(.rejected)),
            (String(localized: "Clear Flag"), .setFlag(.none)),
        ]
        for (name, action) in culling {
            actions.append(NSAccessibilityCustomAction(name: name) { @Sendable [weak model] in
                MainActor.assumeIsolated { model?.performAccessibilityAction(action, onVersion: versionID) }
                return true
            })
        }
        return actions
    }
}
