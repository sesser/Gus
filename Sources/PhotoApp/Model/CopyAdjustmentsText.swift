import Foundation
import PhotoCore

/// The Copy Adjustments sheet's words (copy-adjustments-selective design §10).
enum CopyAdjustmentsText {
    static let title = String(localized: "Copy Adjustments")
    static let menuItem = String(localized: "Copy Adjustments…",
                                 comment: "Adjust menu, the context menus and the Adjust tab's ⋯ menu: opens the sheet that asks what to copy")
    static let toolbarHelp = String(localized: "Choose which adjustments to copy",
                                    comment: "Tooltip of the toolbar's Copy Adjustments item")
    static let checkAll = String(localized: "Check All", comment: "Copy Adjustments sheet: checks every box")
    static let uncheckAll = String(localized: "Uncheck All", comment: "Copy Adjustments sheet: unchecks every box")
    static let copyButton = String(localized: "Copy", comment: "Copy Adjustments sheet: the default button")
    static let checkSomething = String(localized: "Check something to copy.",
                                       comment: "Copy Adjustments sheet: beside the dimmed Copy button while nothing is checked, and its VoiceOver hint")
    static let noAdjustments = String(localized: "This photo has no adjustments. Checking a group resets it on the photos you paste onto.",
                                      comment: "Copy Adjustments sheet: under the title when the photo has no adjustments at all")
    static let listName = String(localized: "Adjustments to copy", comment: "Copy Adjustments sheet: VoiceOver name of the list of check boxes")
    static let masksNote = String(localized: "Presets and Paste Adjustments leave masks out.")
    static let cropCaption = String(localized: "Pasted as it is, whatever a photo's size or shape.",
                                    comment: "Copy Adjustments sheet: under Crop & Straighten, and its VoiceOver hint")
    static let spotsCaption = String(localized: "Pasted only onto photos of the same size.",
                                     comment: "Copy Adjustments sheet: under Spots, and its VoiceOver hint")
    static let cropTitle = String(localized: "Crop & Straighten")

    static func source(_ name: String) -> String {
        String(localized: "From \(name)")
    }

    /// A row's name: the Adjust tab's.
    static func title(_ row: CopyRow) -> String {
        switch row {
        case .crop: cropTitle
        case .section(let section): AdjustText.title(section)
        }
    }

    static func title(_ item: CopyItem) -> String {
        switch item {
        case .crop: cropTitle
        case .group(let group): AdjustText.title(group)
        }
    }

    /// The trailing text of a row (design §3.3).
    static func note(_ note: CopyNote) -> String {
        switch note {
        case .noChanges:
            String(localized: "No changes", comment: "Copy Adjustments sheet: the photo has not changed this group")
        case .resetsOnPaste:
            String(localized: "Resets on paste", comment: "Copy Adjustments sheet: a checked group the photo has not changed")
        case .turnedOff:
            String(localized: "Turned off", comment: "Copy Adjustments sheet: a group the photo has changed but turned off")
        case .spots(let count, false):
            String(localized: "\(count) spots", comment: "Copy Adjustments sheet: the Spots row, how many the photo has")
        case .spots(let count, true):
            String(localized: "\(count) spots, turned off",
                   comment: "Copy Adjustments sheet: the Spots row, how many the photo has, with the group turned off")
        }
    }

    /// What was copied, as the announcement and the Paste tooltip name it:
    /// five names or fewer joined with ", ", more read as a count. One
    /// function for both, so they can't drift (design §15 DQ-2).
    static func list(_ entries: [CopySummaryEntry]) -> String {
        entries.count > 5
            ? String(localized: "\(entries.count) items",
                     comment: "Copy Adjustments: the list of what was copied when it is long, in the announcement and the toolbar Paste item's tooltip")
            : entries.map(name).joined(separator: ", ")
    }

    /// "Copied Light, Color Grading." for VoiceOver once Copy is pressed.
    static func announcement(_ entries: [CopySummaryEntry]) -> String {
        String(localized: "Copied \(list(entries)).", comment: "VoiceOver, after Copy in the Copy Adjustments sheet; %@ is what was copied")
    }

    /// The toolbar Paste Adjustments item's tooltip (design §15 DQ-2):
    /// "Paste Adjustments: Light, Color Grading", no period; the item's own
    /// name with nothing copied.
    static func pasteHelp(_ entries: [CopySummaryEntry]?) -> String {
        guard let entries else { return String(localized: "Paste Adjustments") }
        return String(localized: "Paste Adjustments: \(list(entries))",
                      comment: "Tooltip of the toolbar's Paste Adjustments item; %@ is what was copied (the Copy Adjustments announcement's list)")
    }

    private static func name(_ entry: CopySummaryEntry) -> String {
        switch entry {
        case .row(let row): title(row)
        case .item(let item): title(item)
        }
    }

    /// Activity, after a paste whose spots some photos kept (design §5.1).
    static func spotsOtherSize(_ count: Int) -> String {
        String(localized: "Spots were not pasted onto \(count) photos: their size differs from the photo the spots were copied from.",
               comment: "Activity, after Paste Adjustments with Spots: photos whose size differs kept their own spots")
    }

    /// Activity, after a paste with Spots onto photos whose size could not
    /// be read (an offline or unreadable original, or the source's; design
    /// §15 DQ-1).
    static func spotsUnknownSize(_ count: Int) -> String {
        String(localized: "Spots were not pasted onto \(count) photos: their size, or the size of the photo they were copied from, could not be read.",
               comment: "Activity, after Paste Adjustments with Spots: photos whose original, or the original of the photo the spots were copied from, could not be read kept their own spots")
    }
}
