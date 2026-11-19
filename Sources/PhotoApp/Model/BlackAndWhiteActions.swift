import PhotoCore

/// The Black & White heading's changes and the Adjust ▸ Black & White ▸
/// items (docs/features/bw-module/design.md §3, §8, §9). Each is one undo
/// step; a change that also switches the group on is the same step (B10).
extension AdjustmentEditor {
    /// The quick-set the segmented control and the menu show: only while the
    /// conversion applies (design §3.2).
    var blackAndWhiteQuickSet: BlackAndWhite.Filter? {
        adjustments.blackAndWhiteApplies ? adjustments.blackAndWhite.quickSet : nil
    }

    /// No Filter is in effect: the conversion applies with every filter at 0.
    var blackAndWhiteHasNoFilter: Bool {
        adjustments.blackAndWhiteApplies && adjustments.blackAndWhite.hasNoFilter
    }

    /// The heading's check box and Adjust ▸ Turn On / Off Black & White.
    func toggleBlackAndWhite() {
        setEnabled(Adjustments.Group.blackAndWhite, !adjustments.blackAndWhiteApplies)
    }

    /// A slider or its field. Switches the group on (B10).
    func setBlackAndWhite(_ filter: BlackAndWhite.Filter, _ value: Double, phase: EditPhase) {
        change(BlackAndWhiteText.filterChange, phase: phase) {
            $0.blackAndWhite[filter] = value
            $0.blackAndWhite.isOn = true
        }
    }

    /// A segment or a menu item: that filter at the quick-set value, the
    /// others at 0, on. The one in effect again changes nothing (no undo step).
    func chooseBlackAndWhite(_ filter: BlackAndWhite.Filter) {
        guard blackAndWhiteQuickSet != filter else { return }
        change(BlackAndWhiteText.filterChange, phase: .committed) {
            $0.blackAndWhite.choose(filter)
            $0.setEnabled(Adjustments.Group.blackAndWhite, true)
        }
    }

    /// Adjust ▸ Black & White ▸ No Filter: every filter at 0, on.
    func clearBlackAndWhiteFilters() {
        guard !blackAndWhiteHasNoFilter else { return }
        change(BlackAndWhiteText.filterChange, phase: .committed) {
            $0.blackAndWhite.clearFilters()
            $0.setEnabled(Adjustments.Group.blackAndWhite, true)
        }
    }
}
