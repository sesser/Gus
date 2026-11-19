import PhotoCore

/// The words of the Distortion and Lens Vignetting groups
/// (docs/features/lens-corrections/design.md §4, §5, §6, §14).
enum LensCorrectionText {
    typealias Group = LensCorrectionStatus.Group

    static func title(_ group: Group) -> String {
        AdjustText.title(group.adjustmentGroup)
    }

    static let sourceTitle = String(localized: "Source", comment: "Row label in the Distortion and Lens Vignetting groups: where a lens correction comes from, Auto or Manual")
    static let auto = String(localized: "Auto", comment: "Source choice of a lens correction group: the camera's table in the file")
    static let manual = String(localized: "Manual", comment: "Source choice of a lens correction group: set by hand")
    static let autoHelp = String(localized: "Use the correction table the camera stored in this file.",
                                 comment: "Tooltip of the Auto segment of a lens correction group's Source")
    static let manualHelp = String(localized: "Set the correction by hand.",
                                   comment: "Tooltip of the Manual segment of a lens correction group's Source")
    static let amountTitle = String(localized: "Amount", comment: "Slider label: the strength of an adjustment (a mask's amount, a lens correction's manual amount)")
    static let constrainTitle = String(localized: "Constrain to image",
                                       comment: "Check box under Distortion: zoom so the corrected photo has no empty edge")
    static let constrainHelp = String(localized: "Zoom in slightly so the corrected photo has no empty edges.",
                                      comment: "Tooltip and VoiceOver help of Constrain to image")
    static let readingLabel = String(localized: "Reading the camera's table",
                                     comment: "Spinner tooltip and VoiceOver label while a lens correction table is read; no visible label")

    /// The Auto segment's tooltip when it is dimmed, by reason (design §5).
    static func autoUnavailableHelp(_ reason: LensCorrectionStatus.AutoUnavailable) -> String {
        switch reason {
        case .notRaw:
            String(localized: "Auto isn't available: this file has no camera correction table.",
                   comment: "Tooltip of the dimmed Auto segment of a lens correction group, on a file that is not a raw")
        case .decoderCorrects:
            String(localized: "Auto isn't available: the camera decoder already corrects this photo.",
                   comment: "Tooltip of the dimmed Auto segment, on a raw the system decoder corrects")
        case .builtInCorrection:
            String(localized: "Auto isn't available: this photo is already corrected by the camera's own table.",
                   comment: "Tooltip of the dimmed Auto segment, on a Fujifilm raw with its built-in correction")
        }
    }

    static func sourceLabel(_ group: Group) -> String {
        switch group {
        case .distortion: String(localized: "Distortion source", comment: "VoiceOver: the Source control of Distortion")
        case .vignetting: String(localized: "Lens vignetting source", comment: "VoiceOver: the Source control of Lens Vignetting")
        }
    }

    static func amountLabel(_ group: Group) -> String {
        switch group {
        case .distortion: String(localized: "Distortion amount", comment: "VoiceOver: the Amount slider of Distortion")
        case .vignetting: String(localized: "Lens vignetting amount", comment: "VoiceOver: the Amount slider of Lens Vignetting")
        }
    }

    static func amountValueLabel(_ group: Group) -> String {
        switch group {
        case .distortion: String(localized: "Distortion amount value", comment: "VoiceOver: the Amount field of Distortion")
        case .vignetting: String(localized: "Lens vignetting amount value", comment: "VoiceOver: the Amount field of Lens Vignetting")
        }
    }

    /// The Amount row's tooltip and VoiceOver help: what the sign does.
    static func amountHelp(_ group: Group) -> String {
        switch group {
        case .distortion:
            String(localized: "Positive values straighten lines that bow outward; negative values straighten lines that bow inward.",
                   comment: "Tooltip and VoiceOver help of Distortion's Amount")
        case .vignetting:
            String(localized: "Positive values lighten the corners; negative values darken them.",
                   comment: "Tooltip and VoiceOver help of Lens Vignetting's Amount")
        }
    }

    // MARK: Undo names

    static func sourceUndoName(_ group: Group) -> String {
        switch group {
        case .distortion: String(localized: "Distortion Source", comment: "Undo action name")
        case .vignetting: String(localized: "Lens Vignetting Source", comment: "Undo action name")
        }
    }

    static func amountUndoName(_ group: Group) -> String {
        switch group {
        case .distortion: String(localized: "Distortion Amount", comment: "Undo action name")
        case .vignetting: String(localized: "Lens Vignetting Amount", comment: "Undo action name")
        }
    }

    static func constrainUndoName(_ isOn: Bool) -> String {
        isOn ? String(localized: "Turn On Constrain to Image", comment: "Undo action name")
            : String(localized: "Turn Off Constrain to Image", comment: "Undo action name")
    }

    // MARK: Captions (design §4)

    static func caption(_ caption: LensCorrectionStatus.Caption, group: Group) -> String {
        switch caption {
        case .decoderCorrectsAuto:
            String(localized: "Applied by the camera decoder, so Auto does nothing here. Choose Manual to add your own correction.",
                   comment: "Lens correction caption: a raw the system decoder corrects, Auto stored")
        case .decoderCorrectsManual:
            String(localized: "Applied by the camera decoder. Auto does nothing here; your amount is added on top of it.",
                   comment: "Lens correction caption: a raw the system decoder corrects, Manual chosen")
        case .builtInAuto:
            String(localized: "Applied by the camera's own table, so Auto does nothing here. Choose Manual to add your own correction.",
                   comment: "Lens correction caption: a Fujifilm raw with its built-in correction, Auto stored")
        case .builtInManual:
            String(localized: "Applied by the camera's own table. Auto does nothing here; your amount is added on top of it.",
                   comment: "Lens correction caption: a Fujifilm raw with its built-in correction, Manual chosen")
        case .kernelsUnavailable:
            String(localized: "Lens correction could not be set up on this Mac, so this group changes nothing.",
                   comment: "Lens correction caption, with a warning symbol: the correction can't run")
        case .tableUnreadable:
            String(localized: "The camera's table in this file could not be read, so nothing is corrected. Choose Manual to set the amount by hand.",
                   comment: "Lens correction caption, with a warning symbol: the file's table is damaged or not understood")
        case .usingTable:
            switch group {
            case .distortion: String(localized: "Using the camera's correction table from this file.",
                                     comment: "Distortion caption: Auto uses the file's table")
            case .vignetting: String(localized: "Using the camera's vignetting table from this file.",
                                     comment: "Lens Vignetting caption: Auto uses the file's table")
            }
        case .tableAvailable:
            switch group {
            case .distortion: String(localized: "This file has a camera correction table. Turn on Distortion to use it.",
                                     comment: "Distortion caption: the group is off and the file has a table")
            case .vignetting: String(localized: "This file has a camera vignetting table. Turn on Lens Vignetting to use it.",
                                     comment: "Lens Vignetting caption: the group is off and the file has a table")
            }
        case .noTable:
            switch group {
            case .distortion: String(localized: "No distortion table was found in this file. Choose Manual to set the amount by hand.",
                                     comment: "Distortion caption: Auto on a raw with no table")
            case .vignetting: String(localized: "No vignetting table was found in this file. Choose Manual to set the amount by hand.",
                                     comment: "Lens Vignetting caption: Auto on a raw with no table")
            }
        case .autoUnavailableNotRaw:
            String(localized: "This file has no camera correction table, so Auto isn't available. Choose Manual to set the amount by hand.",
                   comment: "Lens correction caption: Auto stored on a file that is not a raw")
        case .manual:
            switch group {
            case .distortion: String(localized: "Set by hand. Positive values straighten lines that bow outward, negative values lines that bow inward.",
                                     comment: "Distortion caption: Manual")
            case .vignetting: String(localized: "Set by hand. Positive values lighten the corners, negative values darken them.",
                                     comment: "Lens Vignetting caption: Manual")
            }
        }
    }

    /// The caption's first sentence, announced once when a status becomes
    /// known after the person acts (design §11).
    static func announcement(_ caption: LensCorrectionStatus.Caption, group: Group) -> String? {
        switch (caption, group) {
        case (.noTable, .distortion):
            String(localized: "No distortion table was found in this file.", comment: "VoiceOver announcement after turning on Distortion")
        case (.noTable, .vignetting):
            String(localized: "No vignetting table was found in this file.", comment: "VoiceOver announcement after turning on Lens Vignetting")
        case (.tableUnreadable, _), (.kernelsUnavailable, _), (.decoderCorrectsAuto, _), (.builtInAuto, _),
             (.autoUnavailableNotRaw, _):
            Self.caption(caption, group: group)
        default:
            nil
        }
    }

    // MARK: The frame question (design §6)

    static let frameQuestionTitle = String(localized: "Change distortion on a photo with masks or spots?",
                                           comment: "Alert title before a lens correction that moves the frame of a photo with masks or spots")
    static let frameQuestionTitleMany = String(localized: "Change distortion on photos with masks or spots?",
                                               comment: "Alert title before a paste or preset that moves the frame of photos with masks or spots")
    static let frameQuestionMessage = String(localized: "Masks and spots are placed in the corrected frame, so this photo's can move away from what they cover now. You can undo the change.",
                                             comment: "Alert message before a lens correction that moves the frame of a photo with masks or spots")

    static func frameQuestionMessage(affected: Int, of total: Int) -> String {
        String(localized: "\(affected) of the \(total) photos have masks or spots. They are placed in the corrected frame, so they can move away from what they cover now. You can undo the change.",
               comment: "Alert message before a paste or preset: photos whose frame would move and that hold masks or spots, over the photos receiving it")
    }

    static let change = String(localized: "Change", comment: "Alert button: confirms a lens correction change on photos with masks or spots")
    static let cancel = String(localized: "Cancel")

    /// The pixel magnifier plate's second line while Distortion applies (design §10).
    static let afterLensCorrection = String(localized: "After lens correction",
                                            comment: "Pixel magnifier plate, line 2, when Distortion applies: the magnifier shows the photo after lens correction")
}
