import Foundation

/// One parameter of an adjustment module as scripts see it: its persisted
/// name, its type, its range and its default. The modules' own readers and
/// writers stay the source of truth; `AdjustmentParameterTests` checks that
/// every parameter a module writes is described and the other way round.
public struct AdjustmentParameter: Hashable, Sendable {
    public enum ValueType: Hashable, Sendable {
        case number(ClosedRange<Double>)
        case integer(ClosedRange<Int>)
        /// One of a fixed set of strings.
        case choice([String])
        case text
        /// A curve: a flat list `[x0, y0, x1, y1, …]`, each 0 … 1, at least two points.
        case points
    }

    public var name: String
    public var type: ValueType
    /// Nil when the parameter is left out by default (the decoder's or the
    /// camera's own value applies).
    public var defaultValue: EditParameter?

    public init(_ name: String, _ type: ValueType, default defaultValue: EditParameter?) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }

    static func number(_ name: String, _ range: ClosedRange<Double>, default value: Double?) -> AdjustmentParameter {
        AdjustmentParameter(name, .number(range), default: value.map(EditParameter.number))
    }

    /// −100 … +100, default 0: most sliders.
    static func signed(_ name: String) -> AdjustmentParameter {
        number(name, -100...100, default: 0)
    }

    /// 0 … 100.
    static func percent(_ name: String, default value: Double?) -> AdjustmentParameter {
        number(name, 0...100, default: value)
    }

    static func choice<Value: RawRepresentable & CaseIterable>(_ name: String, _ type: Value.Type,
                                                                 default value: Value) -> AdjustmentParameter
    where Value.RawValue == String {
        AdjustmentParameter(name, .choice(Value.allCases.map(\.rawValue)), default: .string(value.rawValue))
    }
}

/// A module as scripts see it.
public struct AdjustmentModuleDescription: Sendable {
    public var kind: EditOperationKind
    /// The group that turns it on and off and that presets carry; nil for crop.
    public var group: Adjustments.Group?
    public var parameters: [AdjustmentParameter]
}

extension Adjustments {
    /// Every module, in render order.
    public static let moduleDescriptions: [AdjustmentModuleDescription] = {
        func describe<Module: AdjustmentModule>(_ module: Module.Type) -> AdjustmentModuleDescription {
            AdjustmentModuleDescription(kind: Module.kind,
                                        group: Group.allCases.first { $0.kinds.contains(Module.kind) },
                                        parameters: Module.parameterDescriptions)
        }
        return [describe(Crop.self), describe(RawDecode.self), describe(WhiteBalance.self), describe(Exposure.self),
                describe(Tone.self), describe(Presence.self), describe(ToneCurve.self), describe(ColorMixer.self),
                describe(ColorGrade.self), describe(LookTable.self), describe(Vignette.self),
                describe(NoiseReduction.self), describe(Sharpen.self), describe(Grain.self)]
    }()

    public static func moduleDescription(_ kind: EditOperationKind) -> AdjustmentModuleDescription? {
        moduleDescriptions.first { $0.kind == kind }
    }
}

extension Crop {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        // The kept rectangle, in unit coordinates of the turned frame; all four or none.
        .number("x", 0...1, default: nil), .number("y", 0...1, default: nil),
        .number("width", 0...1, default: nil), .number("height", 0...1, default: nil),
        AdjustmentParameter("quarterTurns", .integer(0...3), default: .number(0)),
        .number("angle", angleRange, default: 0),
    ]
}

extension RawDecode {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        .choice("look", Look.self, default: .standard),
        AdjustmentParameter("decoderVersion", .text, default: nil),
    ]
}

extension WhiteBalance {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        .choice("preset", Preset.self, default: .asShot),
        .number("temperature", temperatureRange, default: nil),
        .number("tint", tintRange, default: nil),
        .signed("relativeTemperature"),
        .signed("relativeTint"),
    ]
}

extension Exposure {
    public static let parameterDescriptions: [AdjustmentParameter] = [.number("ev", range, default: 0)]
}

extension Tone {
    public static let parameterDescriptions: [AdjustmentParameter] =
        ["contrast", "highlights", "shadows", "whites", "blacks"].map(AdjustmentParameter.signed)
}

extension Presence {
    public static let parameterDescriptions: [AdjustmentParameter] =
        ["clarity", "dehaze", "vibrance", "saturation"].map(AdjustmentParameter.signed)
}

extension ToneCurve {
    public static let parameterDescriptions: [AdjustmentParameter] = Channel.allCases.map {
        AdjustmentParameter($0.rawValue, .points, default: .list([.number(0), .number(0), .number(1), .number(1)]))
    }
}

extension ColorMixer {
    public static let parameterDescriptions: [AdjustmentParameter] = Band.allCases.flatMap { band in
        ["Hue", "Saturation", "Luminance"].map { AdjustmentParameter.signed(band.rawValue + $0) }
    }
}

extension ColorGrade {
    public static let parameterDescriptions: [AdjustmentParameter] = Range.allCases.flatMap { range in
        [AdjustmentParameter.number(range.rawValue + "Hue", 0...360, default: 0),
         .percent(range.rawValue + "Amount", default: 0),
         .signed(range.rawValue + "Luminance")]
    } + [.signed("balance"), .percent("blending", default: 50)]
}

extension LookTable {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        // SHA-256 of a table in the library's look-up table folder.
        AdjustmentParameter("identifier", .text, default: nil),
        AdjustmentParameter("name", .text, default: .string("")),
        .percent("intensity", default: 100),
        .choice("colorSpace", ColorSpace.self, default: .sRGB),
    ]
}

extension Vignette {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        .signed("amount"), .percent("size", default: 50), .signed("roundness"),
    ]
}

extension NoiseReduction {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        .percent("luminance", default: nil), .percent("color", default: nil),
    ]
}

extension Sharpen {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        .number("amount", amountRange, default: 0), .number("radius", radiusRange, default: 1),
        .percent("detail", default: 25), .percent("masking", default: 0),
    ]
}

extension Grain {
    public static let parameterDescriptions: [AdjustmentParameter] = [
        .number("strength", strengthRange, default: 0),
        .percent("shadows", default: 30), .percent("midtones", default: 40), .percent("highlights", default: 15),
        .percent("roughness", default: 50), .percent("color", default: 0),
        .number("size", sizeRange, default: 1),
    ]
}
