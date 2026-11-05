import AppKit
import PhotoCore
import PhotoUI

/// What VoiceOver says about a photo in the grid or the loupe, and what it
/// can do to it (section 10 of docs/UI_REDESIGN.md).
@MainActor
enum PhotoAccessibility {
    /// "DSC00231, RAW plus JPEG"; "DSC00400, video, 0:42".
    static func label(for item: CatalogItem) -> String {
        if item.isVideo {
            return AccessibilityText.list([item.baseName, String(localized: "video", comment: "VoiceOver: a video's type, as in “DSC00400, video, 0:42”"),
                                           item.duration.map(FileKindText.duration) ?? ""])
        }
        var kinds = item.fileKind.map { [$0] } ?? []
        if item.representsPair, let partner = item.partnerKind { kinds.append(partner) }
        return AccessibilityText.list([item.baseName, AccessibilityText.fileType(kinds)])
    }

    /// "3 stars, Picked, Red label, Offline"; empty for a photo nobody culled.
    static func value(for item: CatalogItem, offline: Bool) -> String {
        AccessibilityText.list(parts(item, offline: offline).map { text($0) })
    }

    /// The loupe's value: the photo's, notes on what is shown, then where it
    /// is ("Picked, Machine learning not applied, 13 of 87").
    static func loupeValue(for item: CatalogItem, offline: Bool, notes: [String] = [], index: Int, count: Int) -> String {
        AccessibilityText.list([value(for: item, offline: offline)] + notes + [position(index, of: count)])
    }

    /// Said on moving to another photo in the loupe: "DSC00232, RAW, 3 stars,
    /// Picked, 13 of 87".
    static func loupeMove(to item: CatalogItem, offline: Bool, index: Int, count: Int) -> String {
        AccessibilityText.list([label(for: item), loupeValue(for: item, offline: offline, index: index, count: count)])
    }

    /// "13 of 87".
    static func position(_ index: Int, of count: Int) -> String {
        String(localized: "\(index + 1) of \(count)", comment: "A position in a list (“13 of 87”), or how many of the selected photos have a keyword")
    }

    private static func parts(_ item: CatalogItem, offline: Bool) -> [CullingDescription.Part] {
        CullingDescription.value(rating: item.rating, flag: item.flag, colorLabel: item.colorLabel, offline: offline)
    }

    /// One part in words. Mid-sentence, "no rating" is lowercase.
    static func text(_ part: CullingDescription.Part, midSentence: Bool = false) -> String {
        switch part {
        case .rating(let rating) where rating == .unrated:
            midSentence ? String(localized: "no rating", comment: "VoiceOver: an unrated photo, inside a sentence (“DSC00232, no rating”)")
                        : String(localized: "No rating", comment: "VoiceOver: a photo's rating was removed")
        case .rating(let rating): String(localized: "\(rating.rawValue) stars", comment: "VoiceOver: a photo's star rating")
        case .flag(.picked): String(localized: "Picked")
        case .flag(.rejected): String(localized: "Rejected")
        case .flag(.none): String(localized: "Unflagged")
        case .colorLabel(.none): String(localized: "No label", comment: "VoiceOver: a photo's color label was removed")
        case .colorLabel(let label):
            String(localized: "\(ColorLabelText.name(label)) label", comment: "VoiceOver: a photo's color label, as in “Red label”")
        case .offline: String(localized: "Offline")
        }
    }

    /// "Picked"; "Picked, 12 photos"; "Rating raised, 12 photos".
    static func text(_ announcement: CullingDescription.Announcement) -> String {
        switch announcement {
        case .value(let part, let count) where count <= 1: text(part)
        case .value(let part, let count):
            AccessibilityText.list([text(part), String(localized: "\(count) photos")])
        case .ratingAdjusted(true, let count):
            String(localized: "Rating raised, \(count) photos", comment: "VoiceOver: Raise Rating on photos with different ratings")
        case .ratingAdjusted(false, let count):
            String(localized: "Rating lowered, \(count) photos", comment: "VoiceOver: Lower Rating on photos with different ratings")
        }
    }

    /// The result of an action, then the photo Advance After Rating moved to,
    /// as one announcement: "3 stars. DSC00232, no rating".
    static func advanced(_ result: String, to item: CatalogItem, offline: Bool) -> String {
        let parts = CullingDescription.advancedTo(rating: item.rating, flag: item.flag, colorLabel: item.colorLabel,
                                                  offline: offline)
        let next = AccessibilityText.list([item.baseName] + parts.map { text($0, midSentence: true) })
        return String(localized: "\(result). \(next)", comment: "VoiceOver: a culling result, then the photo shown next (“3 stars. DSC00232, no rating”)")
    }

    // MARK: Actions

    /// Builds a custom action. AppKit runs handlers on the main thread.
    static func action(_ name: String, _ body: @escaping @MainActor @Sendable () -> Void) -> NSAccessibilityCustomAction {
        NSAccessibilityCustomAction(name: name) { @Sendable in
            MainActor.assumeIsolated { body() }
            return true
        }
    }

    /// Raise / Lower Rating, Pick, Reject, Clear Flag on one photo, applied
    /// the way a context menu would (`LibraryModel.performAccessibilityAction`).
    static func cullingActions(forVersion versionID: Int64, model: LibraryModel) -> [NSAccessibilityCustomAction] {
        let culling: [(String, CullingAction)] = [
            (String(localized: "Raise Rating"), .adjustRating(1)),
            (String(localized: "Lower Rating"), .adjustRating(-1)),
            (String(localized: "Pick"), .setFlag(.picked)),
            (String(localized: "Reject"), .setFlag(.rejected)),
            (String(localized: "Clear Flag"), .setFlag(.none)),
        ]
        return culling.map { name, cullingAction in
            action(name) { [weak model] in model?.performAccessibilityAction(cullingAction, onVersion: versionID) }
        }
    }

    /// A grid cell's actions: Open in Loupe, then culling.
    static func gridActions(forVersion versionID: Int64, model: LibraryModel) -> [NSAccessibilityCustomAction] {
        [action(String(localized: "Open in Loupe")) { [weak model] in model?.openLoupe(onVersion: versionID) }]
            + cullingActions(forVersion: versionID, model: model)
    }

    static func showGrid(_ model: LibraryModel) -> NSAccessibilityCustomAction {
        action(String(localized: "Show Grid")) { [weak model] in model?.closeLoupe() }
    }
}
