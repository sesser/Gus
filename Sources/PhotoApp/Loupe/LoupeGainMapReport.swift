import PhotoCore

/// What the loupe shows of a gain-map photo in HDR (issue #282), for the
/// debug script's `print hdr`: whether the visit wants HDR, the version on
/// screen and how often it changed, the headroom the picture was rendered
/// for and the one the display offers.
struct LoupeGainMapReport {
    /// The temporary switch is on and the display and View setting allow HDR.
    var wantsHDR = false
    /// A gain-map rendition or frame has been shown in this visit.
    var isGainMap = false
    var visit = GainMapVisit()
    /// The headroom the loupe fits to now (the screen's potential, or the debug override).
    var displayHeadroom: Float?
    /// What the display is known to give now (`DisplayHeadroomReading`),
    /// and the headroom the layer asks for.
    var settledReading: Float?
    var requestedHeadroom: Float?
    /// The file's own HDR headroom, once known.
    var fileHeadroom: Float?
    /// Settled renditions made again for a new display headroom in this visit.
    var refits = 0
    /// The versions put on screen in this visit, in order ("sdr", "hdr"; maps not counted).
    var shownVersions: [ShownVersion] = []
}
