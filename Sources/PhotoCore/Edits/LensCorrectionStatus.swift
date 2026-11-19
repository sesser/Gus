import Foundation

/// What the Adjust tab shows for the Distortion or Lens Vignetting group
/// (docs/features/lens-corrections/design.md §4, §5): the caption row that
/// applies first, whether Auto is available here and why not, and which
/// segment of Source is selected. One rule for the controls, their captions,
/// VoiceOver and the debug script's `lens print`.
public struct LensCorrectionStatus: Equatable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case distortion, vignetting

        public var adjustmentGroup: Adjustments.Group {
            self == .distortion ? .distortion : .lensVignetting
        }
    }

    /// Why Auto does nothing on this file (design L9): its segment is dimmed,
    /// and a group checked here starts in Manual.
    public enum AutoUnavailable: String, Sendable {
        case notRaw, decoderCorrects, builtInCorrection
    }

    /// The caption rows of design §4, by number.
    public enum Caption: String, Sendable {
        /// 1a, 1b: the system decoder corrects this raw.
        case decoderCorrectsAuto, decoderCorrectsManual
        /// 2a, 2b: Fujifilm's built-in correction.
        case builtInAuto, builtInManual
        /// 3: the kernels can't run and the group would need them.
        case kernelsUnavailable
        /// 5: Auto, the table is damaged or not understood.
        case tableUnreadable
        /// 6: Auto, the table is used.
        case usingTable
        /// 7: Auto, a table is there, the group is off.
        case tableAvailable
        /// 8: Auto, a raw with no table.
        case noTable
        /// 9: Auto stored on a file that is not a raw.
        case autoUnavailableNotRaw
        /// 10: Manual.
        case manual

        /// Rows 3 and 5 carry the warning symbol.
        public var isWarning: Bool { self == .kernelsUnavailable || self == .tableUnreadable }
    }

    public var caption: Caption
    public var autoUnavailable: AutoUnavailable?
    /// 0 Auto, 1 Manual; nil shows no segment selected (Auto stored where it
    /// is not available).
    public var selectedSegment: Int?
    /// The Amount row is shown (Manual).
    public var showsAmount: Bool
    /// The group's check box is checked: on and not turned off.
    public var isChecked: Bool

    /// - Parameters:
    ///   - values: The photo's adjustments (not the effective ones: a group
    ///     turned off keeps its source and amount).
    ///   - lens: The file's state; nil while it is not known (not a raw).
    ///   - kernelsAvailable: `LensKernels.isAvailable`.
    public init(_ group: Group, values: Adjustments, lens: CameraLensState?, kernelsAvailable: Bool) {
        let source: LensCorrectionSource, amount: Double, tableExists: Bool
        switch group {
        case .distortion:
            source = values.distortion.source
            amount = values.distortion.amount
            isChecked = values.distortionApplies
            tableExists = lens?.tables?.distortion != nil
        case .vignetting:
            source = values.lensVignetting.source
            amount = values.lensVignetting.amount
            isChecked = values.lensVignettingApplies
            tableExists = lens?.tables?.vignetting != nil
        }
        switch lens {
        case .decoderCorrects: autoUnavailable = .decoderCorrects
        case .builtInCorrection: autoUnavailable = .builtInCorrection
        case .notRaw, nil: autoUnavailable = .notRaw
        case .tables, .unreadable: autoUnavailable = nil
        }
        let manual = source == .manual
        showsAmount = manual
        selectedSegment = manual ? 1 : (autoUnavailable == nil ? 0 : nil)
        let needsKernels = manual ? amount != 0 : (tableExists && autoUnavailable == nil)
        let kernelsFail = needsKernels && !kernelsAvailable
        switch autoUnavailable {
        case .decoderCorrects:
            caption = manual ? (kernelsFail ? .kernelsUnavailable : .decoderCorrectsManual) : .decoderCorrectsAuto
            return
        case .builtInCorrection:
            caption = manual ? (kernelsFail ? .kernelsUnavailable : .builtInManual) : .builtInAuto
            return
        case .notRaw, nil:
            break
        }
        if kernelsFail {
            caption = .kernelsUnavailable
        } else if manual {
            caption = .manual
        } else if autoUnavailable == .notRaw {
            caption = .autoUnavailableNotRaw
        } else if case .unreadable = lens {
            caption = .tableUnreadable
        } else if tableExists {
            caption = isChecked ? .usingTable : .tableAvailable
        } else {
            caption = .noTable
        }
    }

    /// Checking the group on this file starts it in Manual (design §3.2, RI-5).
    public var startsInManual: Bool { autoUnavailable != nil }
}
