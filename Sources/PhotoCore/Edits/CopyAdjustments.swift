import CoreGraphics
import Foundation

/// Copy Adjustments with a choice of what to copy
/// (docs/features/copy-adjustments-selective, issue #243).
///
/// The sheet lists `CopyRow.all`; each row holds one or more `CopyItem`s,
/// which is what a person checks and what the clipboard records. Paste
/// applies exactly the copied items (`CopiedAdjustments.pasted`).

/// One thing Copy Adjustments can copy: the crop, or one Adjust tab group.
/// The crop is not an `Adjustments.Group` (presets never carry it), so it is
/// an item of its own beside the groups.
public enum CopyItem: Hashable, Sendable {
    case crop
    case group(Adjustments.Group)

    /// Every item, in the sheet's order.
    public static var all: [CopyItem] { CopyRow.all.flatMap(\.items) }

    /// The debug script's and the tests' name: `crop`, or the group's stored
    /// name (`colorGrade`, `spots`, …).
    public var name: String {
        switch self {
        case .crop: "crop"
        case .group(let group): group.rawValue
        }
    }

    public init?(name: String) {
        if name == "crop" {
            self = .crop
        } else if let group = Adjustments.Group(rawValue: name) {
            self = .group(group)
        } else {
            return nil
        }
    }

    /// Never checked when the sheet opens (PRD R3): Crop & Straighten, Spots
    /// and the Lens heading's groups belong to one photo more than to a series.
    public var isUncheckedByDefault: Bool {
        switch self {
        case .crop: true
        case .group(let group): group == .spots || Adjustments.Section.lens.groups.contains(group)
        }
    }
}

/// One row of the sheet: Crop & Straighten, or an Adjust tab heading. A
/// heading with one group is a single row; one with several has its groups
/// under it (design §3.2). Masks and Presets have no row.
public enum CopyRow: Hashable, Sendable {
    case crop
    case section(Adjustments.Section)

    /// The Adjust tab's headings in the order the tab shows them
    /// (`AdjustView`), Presets and Masks left out.
    public static let tabOrder: [Adjustments.Section] = [
        .spots, .develop, .tone, .colorMixer, .blackAndWhite, .colorGrading, .details, .lens, .effects,
    ]

    /// Every row, in order: the one list the sheet, the debug script and the
    /// tests read (#92 will add masks here).
    public static let all: [CopyRow] = [.crop] + tabOrder.map(CopyRow.section)

    public var items: [CopyItem] {
        switch self {
        case .crop: [.crop]
        case .section(let section): section.groups.map(CopyItem.group)
        }
    }

    /// A bold row with its own box over indented groups.
    public var isHeading: Bool { items.count > 1 }
}

/// A check box's state; a heading's is derived from its groups.
public enum CopyCheck: Hashable, Sendable {
    case on, off, mixed
}

/// The secondary text at a row's trailing edge (design §3.3).
public enum CopyNote: Hashable, Sendable {
    /// The source has not changed it, and it is not checked.
    case noChanges
    /// The source has not changed it, and it is checked: a paste resets the target's.
    case resetsOnPaste
    /// Changed in the source but turned off there: pasted turned off.
    case turnedOff
    /// The source's spots, and whether the group is turned off.
    case spots(count: Int, turnedOff: Bool)
}

/// The sheet's state: the source's values, frozen when it opened, and what
/// is checked. Defaults are worked out from the source every time (R3, R10).
public struct CopySheetState: Hashable, Sendable {
    public let source: Adjustments
    public private(set) var checked: Set<CopyItem>

    public init(source: Adjustments) {
        self.source = source
        checked = Self.defaults(for: source)
    }

    /// Changed groups, except Crop & Straighten, Spots and the Lens groups.
    public static func defaults(for source: Adjustments) -> Set<CopyItem> {
        Set(CopyItem.all.filter { !$0.isUncheckedByDefault && isChanged($0, in: source) })
    }

    /// The source holds values for it, turned on or off (`isModified`).
    public static func isChanged(_ item: CopyItem, in source: Adjustments) -> Bool {
        switch item {
        case .crop: !source.crop.isIdentity
        case .group(let group): source.isModified(group)
        }
    }

    public func isChanged(_ item: CopyItem) -> Bool { Self.isChanged(item, in: source) }

    /// Nothing at all to copy but resets (design §3.1's note).
    public var sourceHasNoChanges: Bool { !CopyItem.all.contains(where: isChanged) }

    public func isChecked(_ item: CopyItem) -> Bool { checked.contains(item) }

    public func state(of row: CopyRow) -> CopyCheck {
        let count = row.items.filter(checked.contains).count
        return count == 0 ? .off : count == row.items.count ? .on : .mixed
    }

    /// A click on a row's box: an item flips; a heading that is checked
    /// unchecks all its groups, unchecked or mixed checks them all (design
    /// §3.4, the Adjust tab heading boxes' rule).
    public mutating func click(_ row: CopyRow) {
        set(row.items, state(of: row) != .on)
    }

    public mutating func toggle(_ item: CopyItem) {
        set([item], !checked.contains(item))
    }

    public mutating func set(_ items: [CopyItem], _ isOn: Bool) {
        if isOn { checked.formUnion(items) } else { checked.subtract(items) }
    }

    public mutating func checkAll() { checked = Set(CopyItem.all) }

    public mutating func uncheckAll() { checked = [] }

    /// Copy is offered only with something checked (R4).
    public var canCopy: Bool { !checked.isEmpty }

    /// The text at an item's row, first rule that applies (design §3.3).
    public func note(for item: CopyItem) -> CopyNote? {
        guard isChanged(item) else { return checked.contains(item) ? .resetsOnPaste : .noChanges }
        guard case .group(let group) = item else { return nil }
        if group == .spots { return .spots(count: source.spots.spots.count, turnedOff: !source.isEnabled(.spots)) }
        return source.isEnabled(group) ? nil : .turnedOff
    }

    /// What Copy stores.
    public func copied(from url: URL? = nil) -> CopiedAdjustments {
        CopiedAdjustments(source, items: checked, sourceURL: url)
    }

    /// The checked items for the announcement "Copied …": a heading whose
    /// groups are all checked stands for them; in row order.
    public var summary: [CopySummaryEntry] {
        CopySummaryEntry.entries(for: checked)
    }
}

/// One name in the summary of what was copied.
public enum CopySummaryEntry: Hashable, Sendable {
    /// A heading with all its groups.
    case row(CopyRow)
    case item(CopyItem)

    static func entries(for items: Set<CopyItem>) -> [CopySummaryEntry] {
        CopyRow.all.flatMap { row -> [CopySummaryEntry] in
            let chosen = row.items.filter(items.contains)
            if row.isHeading, chosen.count == row.items.count { return [.row(row)] }
            return chosen.map(CopySummaryEntry.item)
        }
    }
}

/// The clipboard of Copy Adjustments: what was checked, and the values of
/// those items from the source (every other module at its default).
public struct CopiedAdjustments: Hashable, Sendable {
    /// The copied items' values; nothing else.
    public let values: Adjustments
    public let items: Set<CopyItem>
    /// The master the values came from: spots are pasted only onto photos
    /// whose frame has its size (R8). Nil when it is not known (tests).
    public let sourceURL: URL?

    public init(_ source: Adjustments, items: Set<CopyItem>, sourceURL: URL? = nil) {
        var values = Adjustments.none
        values.take(items, from: source)
        self.values = values
        self.items = items
        self.sourceURL = sourceURL
    }

    public var includesSpots: Bool { items.contains(.group(.spots)) }

    /// The summary of what was copied, as `CopySheetState.summary`.
    public var summary: [CopySummaryEntry] { CopySummaryEntry.entries(for: items) }

    /// `target` with the copied items replaced, values and on/off state
    /// (R5): an item at its defaults here resets the target's. Everything
    /// else stays as the target has it, the crop included unless it was
    /// copied; masks, the stored decode and unknown operations are never
    /// touched. `pastingSpots` false keeps the target's spots and their
    /// on/off state, for a photo whose frame differs in size (R8).
    public func pasted(onto target: Adjustments, pastingSpots: Bool = true) -> Adjustments {
        var result = target
        result.take(pastingSpots ? items : items.subtracting([.group(.spots)]), from: values)
        return result
    }

    /// Whether spots copied from a frame of `sourceFrame` go onto a photo
    /// whose frame is `targetFrame` (R8): both known and the same size,
    /// in whole pixels. No remapping to another size or orientation.
    public static func pastesSpots(sourceFrame: CGSize?, targetFrame: CGSize?) -> Bool {
        guard let sourceFrame, let targetFrame else { return false }
        return sourceFrame.width.rounded() == targetFrame.width.rounded()
            && sourceFrame.height.rounded() == targetFrame.height.rounded()
    }
}

/// Which photos of a paste get the copied spots (R8), and how many keep
/// their own and why.
public struct SpotPastePlan: Hashable, Sendable {
    public let matching: Set<Int64>
    /// Photos whose frame has another size than the source's.
    public let otherSize: Int
    /// Photos whose frame, or the source's, could not be read (an offline or
    /// unreadable master).
    public let unknownSize: Int

    /// - Parameters:
    ///   - ids: The photos the paste reaches.
    ///   - sourceFrame: The frame the spots were copied from, nil when unknown.
    ///   - frames: Each photo's frame; a missing one is unknown.
    public init(ids: [Int64], sourceFrame: CGSize?, frames: [Int64: CGSize]) {
        let matching = Set(ids.filter { CopiedAdjustments.pastesSpots(sourceFrame: sourceFrame, targetFrame: frames[$0]) })
        self.matching = matching
        let known = sourceFrame == nil ? [] : ids.filter { frames[$0] != nil }
        otherSize = known.filter { !matching.contains($0) }.count
        unknownSize = ids.count - matching.count - otherSize
    }
}

extension Adjustments {
    /// These adjustments with `items` taken from `source`, values and on/off.
    mutating func take(_ items: Set<CopyItem>, from source: Adjustments) {
        for item in items {
            switch item {
            case .crop: copyModule(Crop.kind, from: source)
            case .group(let group): for kind in group.kinds { copyModule(kind, from: source) }
            }
        }
    }
}
