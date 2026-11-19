import Foundation

/// Where a lens correction group takes its correction from (docs/features/
/// lens-corrections/design.md §3.2): the table the camera stored in the file,
/// read when the photo renders (`CameraLensState`), or the person's Amount.
public enum LensCorrectionSource: String, CaseIterable, Sendable {
    case auto, manual
}

/// Straightens the lines a lens bends (the Distortion group, issue #87).
///
/// The module has an explicit on state, as Black & White does (RI-4): "on,
/// with Auto and nothing else" is an edit with no other representation, since
/// Auto is the default and defaults are left out. Off by default and left out
/// of the stack then, so a stack without the module renders exactly as before
/// (R1, R14). Turned off from its check box it keeps its values in
/// `Adjustments.disabled`, as every group does.
///
/// `amount` is kept whatever the source, and applies only in Manual (RI-5).
/// `constrain` (Constrain to image, on by default) scales the corrected
/// picture so that it exactly fills its frame (`LensWarp.fillScale`).
///
/// Persisted as kind `lensDistortion`: `on` (boolean, default false), `source`
/// (`auto` or `manual`, default `auto`), `amount` (−100 … +100, default 0) and
/// `constrain` (boolean, default true).
public struct LensDistortion: AdjustmentModule {
    public static let kind: EditOperationKind = "lensDistortion"
    public static let amountRange: ClosedRange<Double> = -100...100

    public var isOn = false
    public var source = LensCorrectionSource.auto
    /// −100 … +100: positive straightens lines that bow outward (barrel),
    /// negative lines that bow inward (pincushion).
    public private(set) var amount: Double = 0
    public var constrain = true

    public init(isOn: Bool = false, source: LensCorrectionSource = .auto, amount: Double = 0, constrain: Bool = true) {
        self.isOn = isOn
        self.source = source
        self.constrain = constrain
        setAmount(amount)
    }

    init(_ values: ParameterValues) {
        isOn = values.bool("on", default: false)
        source = values.string("source").flatMap(LensCorrectionSource.init(rawValue:)) ?? .auto
        amount = values.number("amount", default: 0)
        constrain = values.bool("constrain", default: true)
    }

    /// A value outside the range, or not a number, is refused: the amount
    /// stays as it was (design §3.3).
    public mutating func setAmount(_ value: Double) {
        guard value.isFinite, Self.amountRange.contains(value) else { return }
        amount = value
    }

    /// True when the values other than `on` differ from `other`'s.
    func valuesDiffer(from other: LensDistortion) -> Bool {
        source != other.source || amount != other.amount || constrain != other.constrain
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("on", isOn, default: false)
        out.set("source", source.rawValue, default: LensCorrectionSource.auto.rawValue)
        out.set("amount", amount, default: 0)
        out.set("constrain", constrain, default: true)
        return out.values
    }
}

/// Lifts (or darkens) the corners a lens makes darker (the Lens Vignetting
/// group, issue #87); not Effects' creative Vignette. The same explicit on
/// state and the same Source and Amount rules as `LensDistortion`.
///
/// Persisted as kind `lensVignetting`: `on`, `source` and `amount`, with the
/// same defaults.
public struct LensVignetting: AdjustmentModule {
    public static let kind: EditOperationKind = "lensVignetting"
    public static let amountRange: ClosedRange<Double> = -100...100

    public var isOn = false
    public var source = LensCorrectionSource.auto
    /// −100 … +100: positive lightens the corners, negative darkens them.
    public private(set) var amount: Double = 0

    public init(isOn: Bool = false, source: LensCorrectionSource = .auto, amount: Double = 0) {
        self.isOn = isOn
        self.source = source
        setAmount(amount)
    }

    init(_ values: ParameterValues) {
        isOn = values.bool("on", default: false)
        source = values.string("source").flatMap(LensCorrectionSource.init(rawValue:)) ?? .auto
        amount = values.number("amount", default: 0)
    }

    public mutating func setAmount(_ value: Double) {
        guard value.isFinite, Self.amountRange.contains(value) else { return }
        amount = value
    }

    func valuesDiffer(from other: LensVignetting) -> Bool {
        source != other.source || amount != other.amount
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("on", isOn, default: false)
        out.set("source", source.rawValue, default: LensCorrectionSource.auto.rawValue)
        out.set("amount", amount, default: 0)
        return out.values
    }
}

extension LensDistortion {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        AdjustmentParameter("on", .boolean, default: .bool(false)),
        .choice("source", LensCorrectionSource.self, default: .auto),
        .number("amount", amountRange, default: 0),
        AdjustmentParameter("constrain", .boolean, default: .bool(true)),
    ]
}

extension LensVignetting {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        AdjustmentParameter("on", .boolean, default: .bool(false)),
        .choice("source", LensCorrectionSource.self, default: .auto),
        .number("amount", amountRange, default: 0),
    ]
}

extension Adjustments {
    /// These values after a Source segment is chosen (design §3.2, PRD R15): that
    /// source, and the group on (a group that is off is turned on, also by its
    /// selected segment). Nil when nothing changes: the group is on with that
    /// source already, so no undo step is recorded.
    public func choosingLensSource(_ group: Group, _ source: LensCorrectionSource) -> Adjustments? {
        var next = self
        switch group {
        case .distortion: next.distortion.source = source
        case .lensVignetting: next.lensVignetting.source = source
        default: return nil
        }
        next.setEnabled(group, true)
        return next == self ? nil : next
    }

    /// Distortion renders: switched on and not turned off. Says nothing about
    /// whether this photo's file lets Auto apply (`LensCorrectionPlan`).
    public var distortionApplies: Bool {
        distortion.isOn && isEnabled(.distortion)
    }

    /// Lens Vignetting renders: switched on and not turned off.
    public var lensVignettingApplies: Bool {
        lensVignetting.isOn && isEnabled(.lensVignetting)
    }
}
