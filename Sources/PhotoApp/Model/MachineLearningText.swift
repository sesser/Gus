import PhotoCore

/// What the interface says about machine learning noise reduction
/// (ml-denoise design §9). The interface never says "ML" or names the
/// decoder's internal version.
enum MachineLearningText {
    static let checkBoxTitle = String(
        localized: "Use machine learning",
        comment: "Check box in Details ▸ Noise Reduction. Decodes the raw file with the macOS raw decoder's machine learning model, which reduces noise. Sentence-style: it is a check box")

    /// The check box's tooltip and VoiceOver help: S1 and S2, otherwise the caption.
    static func checkBoxHelp(_ state: MachineLearningNoiseReduction.Status.State) -> String {
        if let caption = caption(state) { return caption }
        return String(localized: "Reduce noise with the machine learning model in the macOS raw decoder. Luminance sets the amount; Color isn't used.",
                      comment: "Tooltip and VoiceOver help of the Use machine learning check box")
    }

    /// The note under the check box (design §3); nil in S1. With the group
    /// off (S7) it is the caption the group would have on.
    static func caption(_ state: MachineLearningNoiseReduction.Status.State) -> String? {
        switch state {
        case .notOffered, .off, .unknown: nil
        case .applied:
            String(localized: "Luminance sets the amount. Color is kept but not used while this is on.",
                   comment: "Caption under the Use machine learning check box while it applies")
        case .unavailable(.notOnThisMac):
            String(localized: "Not available on this Mac: it needs macOS 27 or later.",
                   comment: "Caption and help of the dimmed Use machine learning check box")
        case .unavailable(.cameraNotSupported):
            String(localized: "Not available for this camera.",
                   comment: "Caption and help of the dimmed Use machine learning check box: the macOS raw decoder's machine learning version doesn't list the camera")
        case .unavailable(.failed):
            nil
        case .notApplied(.notOnThisMac):
            String(localized: "Not applied on this Mac: it needs macOS 27 or later. Luminance and Color apply instead.",
                   comment: "Caption and check box help: the photo asks for machine learning noise reduction; the setting is kept")
        case .notApplied(.cameraNotSupported):
            String(localized: "Not applied: this camera isn't supported. Luminance and Color apply instead.",
                   comment: "Caption and check box help: the photo asks for machine learning noise reduction; the setting is kept")
        case .notApplied(.failed):
            String(localized: "Not applied: it could not be applied to this photo. Luminance and Color apply instead.",
                   comment: "Caption and check box help: the machine learning decode failed for this file; the setting is kept")
        case .groupOff(let on):
            caption(on)
        }
    }

    /// The caption starts with the "not applied" triangle (S5, S6, S8, and S7 over one of them).
    static func showsTriangle(_ state: MachineLearningNoiseReduction.Status.State) -> Bool {
        switch state {
        case .notApplied: true
        case .groupOff(let on): showsTriangle(on)
        default: false
        }
    }

    static let colorHelp = String(
        localized: "Not used with machine learning. Your value is kept and applies again when you turn off Use machine learning.",
        comment: "Tooltip and VoiceOver help of the dimmed Color row; “Use machine learning” is the check box title")

    /// The Decoder pop-up's item for the machine learning version.
    static func decoderItem(_ version: String) -> String {
        String(localized: "\(version) (machine learning)",
               comment: "Decoder pop-up item for the RAW decoder's machine learning version; the argument is the version, e.g. “9.dng”. Pattern of “%@ (default)”")
    }

    static let decoderDimmedHelp = String(
        localized: "Turn off Use machine learning to choose another decoder.",
        comment: "Tooltip of the dimmed Decoder pop-up while machine learning noise reduction is asked for and not applied")

    static let spinner = String(
        localized: "Applying machine learning noise reduction",
        comment: "Tooltip and VoiceOver label of the loupe caption's spinner while a machine learning frame renders")

    static let badge = String(localized: "Machine Learning Not Applied",
                              comment: "Loupe caption badge. Title-style, as the other badges")

    static func badgeHelp(_ reason: MachineLearningNoiseReduction.Reason) -> String {
        switch reason {
        case .notOnThisMac:
            String(localized: "This photo is set to use machine learning noise reduction, which needs macOS 27 or later. It's shown with Luminance and Color instead.",
                   comment: "Tooltip of the Machine Learning Not Applied badge: this Mac")
        case .cameraNotSupported:
            String(localized: "This photo is set to use machine learning noise reduction, which doesn't support its camera. It's shown with Luminance and Color instead.",
                   comment: "Tooltip of the Machine Learning Not Applied badge: this camera")
        case .failed:
            String(localized: "This photo is set to use machine learning noise reduction, but it could not be applied to this photo. It's shown with Luminance and Color instead.",
                   comment: "Tooltip of the Machine Learning Not Applied badge: the decode failed for this file")
        }
    }

    static let canvasValue = String(
        localized: "Machine learning not applied",
        comment: "VoiceOver: one part of the loupe canvas's value, like “Offline” (“Picked, Machine learning not applied, 13 of 87”)")

    static func leftOffForNonRaw(_ count: Int) -> String {
        String(localized: "Machine learning noise reduction was left off for \(count) photos that aren't raw files.",
               comment: "Activity information row after a batch command that carried machine learning noise reduction on. Plural. Follows “%lld videos were left unchanged.”")
    }

    /// One Activity information row after an export, per reason (design §7).
    static func exportedWithout(_ reason: MachineLearningNoiseReduction.Reason, count: Int) -> String {
        switch reason {
        case .notOnThisMac:
            String(localized: "\(count) photos were exported without machine learning noise reduction: this Mac needs macOS 27 or later.",
                   comment: "Activity information row after an export. Plural")
        case .cameraNotSupported:
            String(localized: "\(count) photos were exported without machine learning noise reduction: their cameras aren't supported.",
                   comment: "Activity information row after an export. Plural")
        case .failed:
            String(localized: "\(count) photos were exported without machine learning noise reduction: it could not be applied to these photos.",
                   comment: "Activity information row after an export. Plural. The “one” variation ends “…: it could not be applied to this photo.” (AC7a)")
        }
    }
}
