import AppKit
import PhotoCore

/// What the loupe shows of a gain-map photo (issue #282), for the debug
/// script's `print hdr` (design §14): whether the visit wants HDR, the
/// version on screen and how often it changed, the badge, the headroom the
/// picture was rendered for, what the screen allows and could give.
struct LoupeGainMapReport {
    /// The photo's choice is on and the display and View setting allow HDR.
    var wantsHDR = false
    /// A gain-map rendition or frame has been shown in this visit.
    var isGainMap = false
    var visit = GainMapVisit()
    /// The headroom the shown photo is fitted to now, nil when shown SDR.
    var displayHeadroom: Float?
    /// What the loupe takes the screen to allow now (its potential until a
    /// reading says less, or the debug override), whatever the photo's choice.
    var allowedHeadroom: Float?
    /// The limit remembered for the screen (`DisplayHeadroomReading.estimate`),
    /// what it allows now as far as known, and the headroom the layer asks for.
    var settledReading: Float?
    var allowedNow: Float?
    var requestedHeadroom: Float?
    /// The file's own HDR headroom and the photo's ceiling, once known.
    var fileHeadroom: Float?
    var ceiling: Float?
    /// Settled renditions made again for a new display headroom in this visit.
    var refits = 0
    /// The HDR version failed in this visit, and how often.
    var failed = false
    var failures = 0
    /// The version badge (`HDRVersionBadge.name`).
    var badge = "none"
    /// The versions put on screen in this visit, in order ("sdr", "hdr"; maps not counted).
    var shownVersions: [ShownVersion] = []
}

/// The display number of a screen, the key of `DisplayHeadroomMemory`.
enum HDRScreens {
    static func number(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
