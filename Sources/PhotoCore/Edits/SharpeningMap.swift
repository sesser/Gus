/// What the sharpening map says about sharpening, beside the picture
/// (docs/features/sharpen-mask-preview/design.md §7): whether the photo is
/// sharpened at all, and why the global sharpening is not.
///
/// One rule, read by the caption badge, the inspector legend, the loupe's
/// VoiceOver value and its announcements.
public struct SharpeningMapStatus: Equatable, Sendable {
    /// Why the global sharpening sharpens nothing.
    public enum Reason: Equatable, Sendable {
        /// The Sharpening group is turned off (wins over an Amount of 0).
        case turnedOff
        /// The group is on and its Amount is 0.
        case amountZero
    }

    /// Nil when the global sharpening sharpens.
    public var reason: Reason?
    /// A mask in effect (one the renderer draws) has Sharpness above 0.
    public var masksSharpen: Bool

    public init(reason: Reason?, masksSharpen: Bool) {
        self.reason = reason
        self.masksSharpen = masksSharpen
    }

    public init(_ values: Adjustments) {
        if !values.isEnabled(.sharpening) {
            reason = .turnedOff
        } else if values.sharpen.amount <= 0 {
            reason = .amountZero
        } else {
            reason = nil
        }
        // The masks the renderer draws: turned on, with shapes, values and an
        // amount, and the Masks group itself not turned off.
        masksSharpen = values.effective.local.renderedMasks.contains { $0.adjustments.sharpen > 0 }
    }

    /// Nothing at all is sharpened, global or local (owner ruling RI-1): the
    /// "Not Applied" state.
    public var isNotApplied: Bool { reason != nil && !masksSharpen }

    /// The legend adds that masks still sharpen: the global sharpening is
    /// off or at 0, and a mask in effect sharpens.
    public var notesMaskSharpening: Bool { reason != nil && masksSharpen }
}

/// The sharpening map's place among the loupe's alternate views (design §6):
/// at most one of Show Original, the map, the mask overlay and a crop
/// session is on screen. Showing the map suspends the overlay and Show
/// Original; hiding it gives them back, except Show Original once a value
/// changed (any change ends Show Original). Never stored.
public struct SharpeningMapState: Equatable, Sendable {
    public private(set) var isShown = false
    /// The overlay was on when the map was shown: its preference, kept.
    public private(set) var suspendedOverlay = false
    /// Show Original was on when the map was shown, and no value has changed since.
    public private(set) var suspendedOriginal = false

    /// What to turn back on when the map goes away.
    public struct Restore: Equatable, Sendable {
        public var overlay: Bool
        public var original: Bool

        public init(overlay: Bool, original: Bool) {
            self.overlay = overlay
            self.original = original
        }
    }

    public init() {}

    /// Shows the map over a loupe showing the overlay and Show Original as
    /// given; the caller turns both off while the map is shown.
    public mutating func show(overlay: Bool, original: Bool) {
        guard !isShown else { return }
        isShown = true
        suspendedOverlay = overlay
        suspendedOriginal = original
    }

    /// The person hid the map: the loupe goes back to what it showed.
    public mutating func hide() -> Restore {
        guard isShown else { return Restore(overlay: false, original: false) }
        let restore = Restore(overlay: suspendedOverlay, original: suspendedOriginal)
        self = SharpeningMapState()
        return restore
    }

    /// Something that needs the photo ended the map (Show Original, Crop,
    /// a mask tool, another photo): the overlay's preference comes back,
    /// Show Original does not.
    public mutating func end() -> Restore {
        guard isShown else { return Restore(overlay: false, original: false) }
        let restore = Restore(overlay: suspendedOverlay, original: false)
        self = SharpeningMapState()
        return restore
    }

    /// A value changed while the map was shown: Show Original no longer
    /// comes back with it.
    public mutating func valuesChanged() {
        suspendedOriginal = false
    }
}
