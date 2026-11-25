import Foundation
import PhotoCore

/// The words of a gain-map photo's HDR choice and version badge (issue
/// #282, design §2, §4, §5, §12). The rule is `HDRVersionBadge`'s.
enum HDRText {
    static let checkboxTitle = String(localized: "HDR", comment: "Adjust tab header check box: the photo's HDR choice")
    static let checkboxHelp = String(localized: "Show and edit this photo in HDR, using the brightness information in its file. Exports are SDR.",
                                     comment: "Help tag and VoiceOver hint of the Adjust tab's HDR check box")
    static let turnOn = String(localized: "Turn On HDR", comment: "Adjust menu item: the photo's HDR choice")
    static let turnOff = String(localized: "Turn Off HDR", comment: "Adjust menu item: the photo's HDR choice")

    /// The badge's text, full form; nil for no badge.
    static func badge(_ status: HDRVersionBadge) -> String? {
        switch status {
        case .none: nil
        case .hdr: String(localized: "HDR", comment: "Loupe caption badge: the HDR version of the photo is on screen")
        case .sdr, .loading, .blocked(.offline):
            String(localized: "SDR", comment: "Loupe caption badge: the SDR version of a gain-map photo is on screen")
        case .blocked(.hidden): String(localized: "SDR: HDR Hidden", comment: "Loupe caption badge: HDR is on for the photo but hidden in the View menu")
        case .blocked(.noHDRDisplay): String(localized: "SDR: No HDR Display", comment: "Loupe caption badge: HDR is on for the photo but the display has no extended range")
        case .blocked(.failed): String(localized: "SDR: HDR Failed", comment: "Loupe caption badge: HDR is on for the photo but its HDR version couldn't be made")
        }
    }

    /// The short form a narrow caption uses (design §5): the reason goes to
    /// the help tag and VoiceOver.
    static func shortBadge(_ status: HDRVersionBadge) -> String? {
        if case .blocked = status { return String(localized: "SDR", comment: "Loupe caption badge: the SDR version of a gain-map photo is on screen") }
        return badge(status)
    }

    /// The warning mark: HDR was asked for and isn't on screen (design §4).
    static func hasWarning(_ status: HDRVersionBadge) -> Bool {
        if case .blocked = status { return true }
        return false
    }

    static func help(_ status: HDRVersionBadge) -> String? {
        switch status {
        case .none: return nil
        case .hdr(let file, let allowed):
            if status.isFitted, let file, let allowed {
                return String(localized: "Showing the HDR version, fitted to this display. The file brightens up to \(number(file))× SDR white; the display allows \(number(allowed))× now. The histogram shows the whole HDR version.",
                              comment: "Help tag of the loupe's HDR badge when the picture is fitted to the display. The arguments are numbers such as 3.7 and 1.3")
            }
            if let file {
                return String(localized: "Showing the HDR version. This file brightens up to \(number(file))× SDR white.",
                              comment: "Help tag of the loupe's HDR badge. The argument is a number such as 2.6")
            }
            return String(localized: "Showing the HDR version.", comment: "Help tag of the loupe's HDR badge before the file's headroom is known")
        case .sdr(offline: false):
            return String(localized: "Showing the SDR version. This file also has an HDR version. To use it, choose Adjust ▸ Turn On HDR.",
                          comment: "Help tag of the loupe's SDR badge for a gain-map photo with HDR off")
        case .sdr(offline: true):
            // Turn On HDR is dimmed while the original is offline: the tag doesn't send people there (design §19.1).
            return String(localized: "Showing the cached SDR preview. This file also has an HDR version, which needs the original.",
                          comment: "Help tag of the loupe's SDR badge for a gain-map photo with HDR off whose original is offline")
        case .loading:
            return loading
        case .blocked(let reason):
            switch reason {
            case .offline:
                return String(localized: "HDR is on for this photo, but its original is offline, so the cached SDR preview is shown.",
                              comment: "Help tag of the loupe's SDR badge")
            case .hidden:
                return String(localized: "HDR is on for this photo. To see it, choose View ▸ Show HDR.", comment: "Help tag of the loupe's SDR badge")
            case .noHDRDisplay:
                return String(localized: "HDR is on for this photo, but this display can't show HDR, or HDR is turned off for it in System Settings.",
                              comment: "Help tag of the loupe's SDR badge")
            case .failed:
                return String(localized: "HDR is on for this photo, but its HDR version couldn't be made. Open the photo again to retry.",
                              comment: "Help tag of the loupe's SDR badge")
            }
        }
    }

    /// The Export sheet's notice (design §10).
    static func exportNotice(_ count: Int) -> String {
        String(localized: "\(count) photos have HDR on. Exports are SDR.",
               comment: "Export sheet header: how many of the exported photos have their HDR choice on; plural variations")
    }

    static let loading = String(localized: "Loading the HDR version", comment: "Help tag and VoiceOver label of the loupe's SDR badge and spinner while the HDR version loads")

    /// The badge's VoiceOver label, which stands alone (design §12).
    static func accessibilityLabel(_ status: HDRVersionBadge) -> String? {
        switch status {
        case .none: return nil
        case .hdr:
            return status.isFitted
                ? String(localized: "Showing the HDR version, fitted to this display", comment: "VoiceOver: the loupe's version badge")
                : String(localized: "Showing the HDR version", comment: "VoiceOver: the loupe's version badge")
        case .sdr: return String(localized: "Showing the SDR version", comment: "VoiceOver: the loupe's version badge")
        case .loading: return loading
        case .blocked(let reason):
            let why = switch reason {
            case .offline: String(localized: "original offline", comment: "VoiceOver: why a photo with HDR on shows SDR")
            case .hidden: String(localized: "HDR is hidden in the View menu", comment: "VoiceOver: why a photo with HDR on shows SDR")
            case .noHDRDisplay: String(localized: "this display can't show HDR", comment: "VoiceOver: why a photo with HDR on shows SDR")
            case .failed: String(localized: "the HDR version couldn't be made", comment: "VoiceOver: why a photo with HDR on shows SDR")
            }
            return String(localized: "HDR is on, showing the SDR version: \(why)",
                          comment: "VoiceOver: the loupe's version badge when HDR is on but SDR is shown; the reason follows")
        }
    }

    private static func number(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// The HDR histogram's words (issue #282, design §7.1, §7.2).
enum HistogramText {
    static let hdrMark = String(localized: "HDR", comment: "Top trailing corner of the inspector's histogram while it shows the HDR version")
    static let hdrHelp = String(localized: "The whole photo's HDR version. Right of the line is brighter than SDR white, up to 3 stops; anything brighter collects at the right edge. A picture fitted to the display can differ.",
                                comment: "Help tag of the inspector's histogram while it shows the HDR version")
    static let hdrLabel = String(localized: "Histogram, HDR version", comment: "VoiceOver label of the inspector's histogram while it shows the HDR version")

    static func hdrValue(_ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        return String(localized: "\(percent) percent of the photo is brighter than SDR white",
                      comment: "VoiceOver value of the HDR histogram: the share of the photo above SDR white, by luminance")
    }
}
