import Foundation

/// The Presets heading's button row: Save…, Import… and Manage… (push
/// buttons that never shrink) and the view switch, right-aligned
/// (preset-list-view design §3). The first arrangement that fits is used:
///
/// 1. one line: Save, Import, Manage, then the switch;
/// 2. Save, Import and the switch, with Manage under them;
/// 3. Save and Import, with Manage and the switch under them.
///
/// The switch never sits on a push button, and the items keep the order
/// Save, Import, Manage, switch for VoiceOver and the keyboard whatever the
/// arrangement.
public enum PresetsBarGeometry {
    /// Between two push buttons on a line.
    public static let buttonSpacing: CGFloat = 6
    /// Between the two lines when the row wraps.
    public static let lineSpacing: CGFloat = 6
    /// The least space between the last push button on a line and the switch.
    public static let minimumSwitchGap: CGFloat = 8

    public enum Arrangement: Int, CaseIterable, Sendable {
        case oneLine = 1
        case switchBesideImport = 2
        case switchBesideManage = 3
    }

    /// The sizes of the four items, in their order: Save, Import, Manage, switch.
    public struct Sizes: Equatable, Sendable {
        public var save: CGSize
        public var importButton: CGSize
        public var manage: CGSize
        public var viewSwitch: CGSize

        public init(save: CGSize, importButton: CGSize, manage: CGSize, viewSwitch: CGSize) {
            self.save = save
            self.importButton = importButton
            self.manage = manage
            self.viewSwitch = viewSwitch
        }

        var all: [CGSize] { [save, importButton, manage, viewSwitch] }
    }

    /// The width the arrangement needs, with the switch at its least gap.
    public static func neededWidth(_ arrangement: Arrangement, _ sizes: Sizes) -> CGFloat {
        let saveAndImport = sizes.save.width + buttonSpacing + sizes.importButton.width
        let switchPart = minimumSwitchGap + sizes.viewSwitch.width
        return switch arrangement {
        case .oneLine: saveAndImport + buttonSpacing + sizes.manage.width + switchPart
        case .switchBesideImport: max(saveAndImport + switchPart, sizes.manage.width)
        case .switchBesideManage: max(saveAndImport, sizes.manage.width + switchPart)
        }
    }

    /// The first arrangement that fits `width`; the last when none does (it
    /// then overflows, as the push buttons alone did before the switch).
    /// Without a width (an ideal-size query) the one-line arrangement.
    public static func arrangement(forWidth width: CGFloat?, _ sizes: Sizes) -> Arrangement {
        guard let width, width.isFinite else { return .oneLine }
        return Arrangement.allCases.first { neededWidth($0, sizes) <= width + 0.001 } ?? .switchBesideManage
    }

    /// The row's size in `width` (or its needed width when there is none or
    /// it is narrower: the row never squeezes its push buttons).
    public static func size(forWidth width: CGFloat?, _ sizes: Sizes) -> CGSize {
        let arrangement = arrangement(forWidth: width, sizes)
        let needed = neededWidth(arrangement, sizes)
        let lines = lineHeights(arrangement, sizes)
        let height = lines.reduce(0, +) + lineSpacing * CGFloat(lines.count - 1)
        let finite = width.flatMap { $0.isFinite ? $0 : nil } ?? needed
        return CGSize(width: max(finite, needed), height: height)
    }

    /// Each item's frame (Save, Import, Manage, switch) in a row of `width`,
    /// origin at the top left, y down. Items are centered on their line; the
    /// switch is at the right edge.
    public static func frames(forWidth width: CGFloat?, _ sizes: Sizes) -> [CGRect] {
        let arrangement = arrangement(forWidth: width, sizes)
        let rowWidth = size(forWidth: width, sizes).width
        let lines = lineHeights(arrangement, sizes)
        // Which line each item is on, and its x.
        let saveX = 0.0
        let importX = sizes.save.width + buttonSpacing
        let switchX = rowWidth - sizes.viewSwitch.width
        let placement: [(line: Int, x: CGFloat)] = switch arrangement {
        case .oneLine:
            [(0, saveX), (0, importX), (0, importX + sizes.importButton.width + buttonSpacing), (0, switchX)]
        case .switchBesideImport:
            [(0, saveX), (0, importX), (1, 0), (0, switchX)]
        case .switchBesideManage:
            [(0, saveX), (0, importX), (1, 0), (1, switchX)]
        }
        return zip(sizes.all, placement).map { size, place in
            let lineTop = place.line == 0 ? 0 : lines[0] + lineSpacing
            let y = lineTop + (lines[place.line] - size.height) / 2
            return CGRect(x: place.x, y: y, width: size.width, height: size.height)
        }
    }

    private static func lineHeights(_ arrangement: Arrangement, _ sizes: Sizes) -> [CGFloat] {
        switch arrangement {
        case .oneLine:
            [sizes.all.map(\.height).max() ?? 0]
        case .switchBesideImport:
            [max(sizes.save.height, sizes.importButton.height, sizes.viewSwitch.height), sizes.manage.height]
        case .switchBesideManage:
            [max(sizes.save.height, sizes.importButton.height), max(sizes.manage.height, sizes.viewSwitch.height)]
        }
    }
}
