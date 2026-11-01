import Foundation

/// Masks and the local adjustments they carry (docs/PHASE6_PLAN.md).
///
/// One operation of kind `localAdjustments` holds every mask, in order, as a
/// list of objects (schema version 2). Shapes are stored in unit coordinates
/// of the mask frame (the oriented decoded image, before turns, straightening
/// and crop); sizes are fractions of its long edge.
///
/// Reading is strict, unlike the global modules: a value of the wrong type, an
/// unknown key, shape or operation, or a stack over `MaskLimits`, makes the
/// whole stack unreadable (`EditStack.DecodingFailure`), so nothing ever writes
/// back a copy with part of a mask missing. A new key or shape needs a new
/// `kindVersion`, whose operations older builds keep untouched. Numbers out of
/// range are clamped, as the modules do.
public struct LocalAdjustments: Hashable, Sendable {
    public static let kind: EditOperationKind = "localAdjustments"

    public var masks: [Mask] = []

    public init(masks: [Mask] = []) {
        self.masks = masks
    }

    public var isIdentity: Bool { masks.isEmpty }

    /// Masks that change the picture: turned on, with components and local values.
    public var renderedMasks: [Mask] {
        masks.filter { $0.isEnabled && !$0.components.isEmpty && !$0.adjustments.isDefault && $0.amount > 0 }
    }

    public var parameters: [String: EditParameter] {
        guard !masks.isEmpty else { return [:] }
        return ["masks": .list(masks.map { .object($0.parameters) })]
    }

    init(_ parameters: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(parameters, allowed: ["masks"])
        try reader.checkKeys()
        masks = try reader.objects("masks").map { values throws(MaskReadError) in try Mask(values) }
        try MaskLimits.check(self)
    }

    /// Checks a stored operation of this kind, as `EditStack.decode` does.
    static func validate(_ operation: EditOperation) throws(MaskReadError) {
        guard operation.kind == kind, operation.kindVersion == 1 else { return }
        _ = try LocalAdjustments(operation.parameters)
    }
}

/// Why stored masks cannot be read.
public enum MaskReadError: Error, Equatable, Sendable {
    /// A key, type, shape or operation this build does not know.
    case invalid(String)
    /// More masks, components, samples or brush points than `MaskLimits` allows.
    case exceedsLimits(String)
}

/// Bounds on what a stack may hold, so that no stack (from `photocli`, a
/// damaged file or a newer build) can stall a render. Enforced when masks are
/// created; a stored stack over them is unreadable, never truncated.
public enum MaskLimits {
    public static let masks = 32
    public static let componentsPerMask = 16
    public static let colorSamples = 8
    public static let brushPointsPerMask = 200_000

    static func check(_ local: LocalAdjustments) throws(MaskReadError) {
        guard local.masks.count <= masks else { throw .exceedsLimits("\(local.masks.count) masks") }
        for mask in local.masks {
            guard mask.components.count <= componentsPerMask else {
                throw .exceedsLimits("\(mask.components.count) components in one mask")
            }
            if let samples = mask.components.lazy.compactMap({ $0.shape.colorRange?.samples.count }).max(),
               samples > colorSamples {
                throw .exceedsLimits("\(samples) color samples")
            }
            guard mask.brushPointCount <= brushPointsPerMask else {
                throw .exceedsLimits("\(mask.brushPointCount) brush points in one mask")
            }
        }
    }

    /// Whether `local` may be saved: the check the editor and commands make
    /// before adding to a mask.
    public static func allows(_ local: LocalAdjustments) -> Bool {
        (try? check(local)) != nil
    }
}

/// One mask: components combined into an alpha, an amount, and the local values.
public struct Mask: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// 0 … 100: scales the combined alpha.
    public var amount: Double
    public var components: [MaskComponent]
    public var adjustments: LocalValues

    public static let amountRange: ClosedRange<Double> = 0...100

    public init(id: UUID = UUID(), name: String = "", isEnabled: Bool = true, amount: Double = 100,
                components: [MaskComponent] = [], adjustments: LocalValues = LocalValues()) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.amount = amount
        self.components = components
        self.adjustments = adjustments
    }

    var brushPointCount: Int {
        components.reduce(0) { $0 + ($1.shape.brush?.strokes.reduce(0) { $0 + $1.points.count } ?? 0) }
    }

    var parameters: [String: EditParameter] {
        var out: [String: EditParameter] = ["id": .string(id.uuidString)]
        if !name.isEmpty { out["name"] = .string(name) }
        if !isEnabled { out["isEnabled"] = .bool(false) }
        if amount != 100 { out["amount"] = .number(amount) }
        if !components.isEmpty { out["components"] = .list(components.map { .object($0.parameters) }) }
        let local = adjustments.parameters
        if !local.isEmpty { out["adjustments"] = .object(local) }
        return out
    }

    init(_ values: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(values, allowed: ["id", "name", "isEnabled", "amount", "components", "adjustments"])
        try reader.checkKeys()
        guard let id = UUID(uuidString: try reader.string("id") ?? "") else { throw .invalid("a mask without an id") }
        self.id = id
        name = try reader.string("name") ?? ""
        isEnabled = try reader.bool("isEnabled") ?? true
        amount = try reader.number("amount", Self.amountRange, default: 100)
        components = try reader.objects("components").map { values throws(MaskReadError) in try MaskComponent(values) }
        adjustments = try LocalValues(reader.object("adjustments") ?? [:])
    }
}

/// How a component's alpha c joins the alpha a of the components before it.
public enum MaskOperation: String, CaseIterable, Sendable {
    /// a ← max(a, c)
    case add
    /// a ← a · (1 − c)
    case subtract
    /// a ← a · c
    case intersect
}

public struct MaskComponent: Hashable, Sendable {
    public var operation: MaskOperation
    /// c becomes 1 − c before it is combined.
    public var invert: Bool
    public var shape: MaskShape

    public init(_ shape: MaskShape, operation: MaskOperation = .add, invert: Bool = false) {
        self.shape = shape
        self.operation = operation
        self.invert = invert
    }

    var parameters: [String: EditParameter] {
        var out = shape.parameters
        out["shape"] = .string(shape.name)
        if operation != .add { out["operation"] = .string(operation.rawValue) }
        if invert { out["invert"] = .bool(true) }
        return out
    }

    init(_ values: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(values, allowed: [])
        guard let name = try reader.string("shape") else { throw .invalid("a component without a shape") }
        shape = try MaskShape(name: name, values)
        let operationName = try reader.string("operation") ?? MaskOperation.add.rawValue
        guard let operation = MaskOperation(rawValue: operationName) else {
            throw .invalid("mask operation \(operationName)")
        }
        self.operation = operation
        invert = try reader.bool("invert") ?? false
    }
}

/// A point in unit coordinates of the mask frame, rounded to 10⁻⁶ (0.006 px
/// on a 6000 px edge), so stored strokes stay short and repeat exactly.
public struct MaskPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = Self.rounded(x)
        self.y = Self.rounded(y)
    }

    static func rounded(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}

public enum MaskShape: Hashable, Sendable {
    case linear(LinearGradient)
    case radial(RadialGradient)
    case brush(Brush)
    case luminanceRange(LuminanceRange)
    case colorRange(ColorRange)

    /// The stored name.
    public var name: String {
        switch self {
        case .linear: "linear"
        case .radial: "radial"
        case .brush: "brush"
        case .luminanceRange: "luminanceRange"
        case .colorRange: "colorRange"
        }
    }

    public static let names = ["linear", "radial", "brush", "luminanceRange", "colorRange"]

    var brush: Brush? {
        if case .brush(let brush) = self { return brush }
        return nil
    }

    var colorRange: ColorRange? {
        if case .colorRange(let range) = self { return range }
        return nil
    }

    var parameters: [String: EditParameter] {
        switch self {
        case .linear(let shape): shape.parameters
        case .radial(let shape): shape.parameters
        case .brush(let shape): shape.parameters
        case .luminanceRange(let shape): shape.parameters
        case .colorRange(let shape): shape.parameters
        }
    }

    init(name: String, _ values: [String: EditParameter]) throws(MaskReadError) {
        let common: Set<String> = ["shape", "operation", "invert"]
        switch name {
        case "linear":
            let reader = ObjectReader(values, allowed: common.union(LinearGradient.keys))
            try reader.checkKeys()
            self = .linear(try LinearGradient(reader))
        case "radial":
            let reader = ObjectReader(values, allowed: common.union(RadialGradient.keys))
            try reader.checkKeys()
            self = .radial(try RadialGradient(reader))
        case "brush":
            let reader = ObjectReader(values, allowed: common.union(["strokes"]))
            try reader.checkKeys()
            self = .brush(try Brush(reader))
        case "luminanceRange":
            let reader = ObjectReader(values, allowed: common.union(LuminanceRange.keys))
            try reader.checkKeys()
            self = .luminanceRange(try LuminanceRange(reader))
        case "colorRange":
            let reader = ObjectReader(values, allowed: common.union(ColorRange.keys))
            try reader.checkKeys()
            self = .colorRange(try ColorRange(reader))
        default:
            throw .invalid("mask shape \(name)")
        }
    }
}

/// Full effect on the start side, none past the end. Feather 0 … 100 spreads
/// the transition over that share of the distance, centered between them; 0
/// is a hard edge at the middle.
public struct LinearGradient: Hashable, Sendable {
    public var start: MaskPoint
    public var end: MaskPoint
    public var feather: Double

    public static let featherRange: ClosedRange<Double> = 0...100
    /// Ends may lie off the frame.
    public static let coordinateRange: ClosedRange<Double> = -2...3
    static let keys: Set<String> = ["startX", "startY", "endX", "endY", "feather"]

    public init(start: MaskPoint, end: MaskPoint, feather: Double = 100) {
        self.start = start
        self.end = end
        self.feather = feather
    }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("startX", start.x)
        out.set("startY", start.y)
        out.set("endX", end.x)
        out.set("endY", end.y)
        out.set("feather", feather, default: 100)
        return out.values
    }

    init(_ reader: ObjectReader) throws(MaskReadError) {
        let range = Self.coordinateRange
        start = MaskPoint(x: try reader.number("startX", range, default: 0.5),
                          y: try reader.number("startY", range, default: 0.25))
        end = MaskPoint(x: try reader.number("endX", range, default: 0.5),
                        y: try reader.number("endY", range, default: 0.75))
        feather = try reader.number("feather", Self.featherRange, default: 100)
    }
}

/// An ellipse: 1 inside, falling off over its outer `feather` percent.
public struct RadialGradient: Hashable, Sendable {
    public var center: MaskPoint
    /// Fractions of the mask frame's long edge.
    public var radiusX: Double
    public var radiusY: Double
    /// Degrees, clockwise, in the mask frame.
    public var rotation: Double
    public var feather: Double

    public static let radiusRange: ClosedRange<Double> = 0.001...2
    public static let rotationRange: ClosedRange<Double> = -180...180
    public static let featherRange: ClosedRange<Double> = 0...100
    static let keys: Set<String> = ["centerX", "centerY", "radiusX", "radiusY", "rotation", "feather"]

    public init(center: MaskPoint, radiusX: Double, radiusY: Double, rotation: Double = 0, feather: Double = 50) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.rotation = rotation
        self.feather = feather
    }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("centerX", center.x)
        out.set("centerY", center.y)
        out.set("radiusX", radiusX)
        out.set("radiusY", radiusY)
        out.set("rotation", rotation, default: 0)
        out.set("feather", feather, default: 50)
        return out.values
    }

    init(_ reader: ObjectReader) throws(MaskReadError) {
        let range = LinearGradient.coordinateRange
        center = MaskPoint(x: try reader.number("centerX", range, default: 0.5),
                           y: try reader.number("centerY", range, default: 0.5))
        radiusX = try reader.number("radiusX", Self.radiusRange, default: 0.25)
        radiusY = try reader.number("radiusY", Self.radiusRange, default: 0.25)
        rotation = try reader.number("rotation", Self.rotationRange, default: 0)
        feather = try reader.number("feather", Self.featherRange, default: 50)
    }
}

/// Painted strokes, each a list of points laid down as dabs.
public struct Brush: Hashable, Sendable {
    public var strokes: [BrushStroke]

    public init(strokes: [BrushStroke] = []) {
        self.strokes = strokes
    }

    var parameters: [String: EditParameter] {
        strokes.isEmpty ? [:] : ["strokes": .list(strokes.map { .object($0.parameters) })]
    }

    init(_ reader: ObjectReader) throws(MaskReadError) {
        strokes = try reader.objects("strokes").map { values throws(MaskReadError) in try BrushStroke(values) }
    }
}

public struct BrushStroke: Hashable, Sendable {
    public var points: [MaskPoint]
    /// Radius, as a fraction of the mask frame's long edge.
    public var size: Double
    /// 0 … 100: the share of the radius that falls off.
    public var feather: Double
    /// 1 … 100: how much one dab adds.
    public var flow: Double
    /// 1 … 100: the most the stroke reaches.
    public var density: Double
    /// Takes coverage away instead of adding it.
    public var erase: Bool

    public static let sizeRange: ClosedRange<Double> = 0.0005...0.5
    public static let percentRange: ClosedRange<Double> = 0...100
    public static let flowRange: ClosedRange<Double> = 1...100
    static let keys: Set<String> = ["points", "size", "feather", "flow", "density", "erase"]

    public init(points: [MaskPoint] = [], size: Double = 0.03, feather: Double = 50, flow: Double = 100,
                density: Double = 100, erase: Bool = false) {
        self.points = points
        self.size = size
        self.feather = feather
        self.flow = flow
        self.density = density
        self.erase = erase
    }

    /// Adds a sample as it is recorded, unless it lies within a tenth of the
    /// radius (in long-edge units of a frame of `aspect` width over height) of
    /// the last kept point. Dabs fall a quarter of the radius apart, so a
    /// dropped sample moves no dab by more than that. Returns whether it was
    /// kept; `finish` keeps the stroke's last sample whatever its distance.
    @discardableResult
    public mutating func record(_ point: MaskPoint, aspect: Double) -> Bool {
        guard let last = points.last else {
            points.append(point)
            return true
        }
        // Unit coordinates to long-edge units.
        let (sx, sy) = aspect >= 1 ? (1.0, 1 / aspect) : (aspect, 1.0)
        let distance = hypot((point.x - last.x) * sx, (point.y - last.y) * sy)
        guard distance >= size / 10 else { return false }
        points.append(point)
        return true
    }

    /// Ends a recorded stroke with its last sample.
    public mutating func finish(_ point: MaskPoint) {
        if points.last != point { points.append(point) }
    }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.values["points"] = .list(points.flatMap { [EditParameter.number($0.x), .number($0.y)] })
        out.set("size", size, default: 0.03)
        out.set("feather", feather, default: 50)
        out.set("flow", flow, default: 100)
        out.set("density", density, default: 100)
        if erase { out.values["erase"] = .bool(true) }
        return out.values
    }

    init(_ values: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(values, allowed: Self.keys)
        try reader.checkKeys()
        let numbers = try reader.numbers("points")
        guard numbers.count.isMultiple(of: 2) else { throw .invalid("a brush stroke with an odd number of values") }
        let range = LinearGradient.coordinateRange
        points = stride(from: 0, to: numbers.count, by: 2).map {
            MaskPoint(x: min(max(numbers[$0], range.lowerBound), range.upperBound),
                      y: min(max(numbers[$0 + 1], range.lowerBound), range.upperBound))
        }
        size = try reader.number("size", Self.sizeRange, default: 0.03)
        feather = try reader.number("feather", Self.percentRange, default: 50)
        flow = try reader.number("flow", Self.flowRange, default: 100)
        density = try reader.number("density", Self.flowRange, default: 100)
        erase = try reader.bool("erase") ?? false
    }
}

/// Luminance in the perceptual encoding (Rec. 2020 Y, sRGB curve) between
/// `lower` and `upper`, falling off over `smoothness` on either side.
public struct LuminanceRange: Hashable, Sendable {
    public var lower: Double
    public var upper: Double
    public var smoothness: Double

    public static let range: ClosedRange<Double> = 0...1
    static let keys: Set<String> = ["lower", "upper", "smoothness"]

    public init(lower: Double = 0.5, upper: Double = 1, smoothness: Double = 0.1) {
        self.lower = lower
        self.upper = upper
        self.smoothness = smoothness
    }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("lower", lower, default: 0.5)
        out.set("upper", upper, default: 1)
        out.set("smoothness", smoothness, default: 0.1)
        return out.values
    }

    init(_ reader: ObjectReader) throws(MaskReadError) {
        lower = try reader.number("lower", Self.range, default: 0.5)
        upper = try reader.number("upper", Self.range, default: 1)
        smoothness = try reader.number("smoothness", Self.range, default: 0.1)
    }
}

/// Colors near sampled ones, in OkLab.
public struct ColorRange: Hashable, Sendable {
    /// OkLab (L, a, b) of each sample.
    public var samples: [SIMD3<Double>]
    /// 0 … 100.
    public var tolerance: Double

    public static let toleranceRange: ClosedRange<Double> = 0...100
    static let keys: Set<String> = ["samples", "tolerance"]

    public init(samples: [SIMD3<Double>] = [], tolerance: Double = 30) {
        self.samples = samples
        self.tolerance = tolerance
    }

    /// OkLab of a linear Rec. 2020 color (clamped to 0 … 1), as the range compares.
    public static func okLab(linearRec2020 rgb: SIMD3<Double>) -> SIMD3<Double> {
        let c = SIMD3(min(max(rgb.x, 0), 1), min(max(rgb.y, 0), 1), min(max(rgb.z, 0), 1))
        let m = MaskRenderer.rec2020ToLMS, lab = MaskRenderer.lmsToLab
        let lms = (0..<3).map { cbrt(m[$0][0] * c.x + m[$0][1] * c.y + m[$0][2] * c.z) }
        let out = (0..<3).map { lab[$0][0] * lms[0] + lab[$0][1] * lms[1] + lab[$0][2] * lms[2] }
        return SIMD3(out[0], out[1], out[2])
    }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.values["samples"] = .list(samples.map { .list([.number($0.x), .number($0.y), .number($0.z)]) })
        out.set("tolerance", tolerance, default: 30)
        return out.values
    }

    init(_ reader: ObjectReader) throws(MaskReadError) {
        samples = try reader.lists("samples").map { values throws(MaskReadError) in
            let numbers = try ObjectReader.numbers(values, "a color sample")
            guard numbers.count == 3 else { throw .invalid("a color sample of \(numbers.count) values") }
            return SIMD3(min(max(numbers[0], 0), 1), min(max(numbers[1], -0.5), 0.5), min(max(numbers[2], -0.5), 0.5))
        }
        tolerance = try reader.number("tolerance", Self.toleranceRange, default: 30)
    }
}

/// The local sliders of one mask. Each drives the global module of the same
/// name over the masked area; exposure is applied exactly, as a gain map.
public struct LocalValues: Hashable, Sendable {
    public var exposure: Double = 0
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var whites: Double = 0
    public var blacks: Double = 0
    public var temperature: Double = 0
    public var tint: Double = 0
    public var vibrance: Double = 0
    public var saturation: Double = 0
    public var clarity: Double = 0
    public var dehaze: Double = 0
    public var sharpen: Double = 0

    public init() {}

    public static let exposureRange: ClosedRange<Double> = -4...4
    public static let sharpenRange: ClosedRange<Double> = 0...100
    public static let signedRange: ClosedRange<Double> = -100...100

    /// One local slider: its stored name, its range and where it lives.
    public struct Control: Sendable {
        public var name: String
        public var range: ClosedRange<Double>
        public var keyPath: WritableKeyPath<LocalValues, Double> & Sendable
    }

    /// Every control, in the Adjust tab's order.
    public static let controls: [Control] = [
        Control(name: "exposure", range: exposureRange, keyPath: \.exposure),
        Control(name: "contrast", range: signedRange, keyPath: \.contrast),
        Control(name: "highlights", range: signedRange, keyPath: \.highlights),
        Control(name: "shadows", range: signedRange, keyPath: \.shadows),
        Control(name: "whites", range: signedRange, keyPath: \.whites),
        Control(name: "blacks", range: signedRange, keyPath: \.blacks),
        Control(name: "temperature", range: signedRange, keyPath: \.temperature),
        Control(name: "tint", range: signedRange, keyPath: \.tint),
        Control(name: "vibrance", range: signedRange, keyPath: \.vibrance),
        Control(name: "saturation", range: signedRange, keyPath: \.saturation),
        Control(name: "clarity", range: signedRange, keyPath: \.clarity),
        Control(name: "dehaze", range: signedRange, keyPath: \.dehaze),
        Control(name: "sharpen", range: sharpenRange, keyPath: \.sharpen),
    ]

    public var isDefault: Bool { self == LocalValues() }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        for control in Self.controls {
            out.set(control.name, self[keyPath: control.keyPath], default: 0)
        }
        return out.values
    }

    init(_ values: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(values, allowed: Set(Self.controls.map(\.name)))
        try reader.checkKeys()
        for control in Self.controls {
            self[keyPath: control.keyPath] = try reader.number(control.name, control.range, default: 0)
        }
    }

    /// The global modules these values drive, other than exposure (applied as a
    /// gain map) and sharpening (applied at the sharpening step).
    var modules: Adjustments {
        var adjustments = Adjustments()
        adjustments.whiteBalance.relativeTemperature = temperature
        adjustments.whiteBalance.relativeTint = tint
        adjustments.tone = Tone(contrast: contrast, highlights: highlights, shadows: shadows, whites: whites,
                                blacks: blacks)
        adjustments.presence = Presence(clarity: clarity, dehaze: dehaze, vibrance: vibrance, saturation: saturation)
        return adjustments
    }
}

/// Strict typed reads from a stored object.
struct ObjectReader {
    let values: [String: EditParameter]
    /// Keys that may appear; empty to skip the check.
    let allowed: Set<String>

    init(_ values: [String: EditParameter], allowed: Set<String>) {
        self.values = values
        self.allowed = allowed
    }

    func checkKeys() throws(MaskReadError) {
        if let unknown = values.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw .invalid("unknown key \(unknown)")
        }
    }

    func number(_ key: String, _ range: ClosedRange<Double>, default value: Double) throws(MaskReadError) -> Double {
        guard let stored = values[key] else { return value }
        guard case .number(let number) = stored, number.isFinite else { throw .invalid("\(key) is not a number") }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    func string(_ key: String) throws(MaskReadError) -> String? {
        guard let stored = values[key] else { return nil }
        guard case .string(let string) = stored else { throw .invalid("\(key) is not text") }
        return string
    }

    func bool(_ key: String) throws(MaskReadError) -> Bool? {
        guard let stored = values[key] else { return nil }
        guard case .bool(let bool) = stored else { throw .invalid("\(key) is not true or false") }
        return bool
    }

    func object(_ key: String) throws(MaskReadError) -> [String: EditParameter]? {
        guard let stored = values[key] else { return nil }
        guard case .object(let object) = stored else { throw .invalid("\(key) is not an object") }
        return object
    }

    func lists(_ key: String) throws(MaskReadError) -> [[EditParameter]] {
        try list(key).map { item throws(MaskReadError) in
            guard case .list(let list) = item else { throw .invalid("\(key) holds something other than lists") }
            return list
        }
    }

    func objects(_ key: String) throws(MaskReadError) -> [[String: EditParameter]] {
        try list(key).map { item throws(MaskReadError) in
            guard case .object(let object) = item else { throw .invalid("\(key) holds something other than objects") }
            return object
        }
    }

    func numbers(_ key: String) throws(MaskReadError) -> [Double] {
        try Self.numbers(list(key), key)
    }

    private func list(_ key: String) throws(MaskReadError) -> [EditParameter] {
        guard let stored = values[key] else { return [] }
        guard case .list(let list) = stored else { throw .invalid("\(key) is not a list") }
        return list
    }

    static func numbers(_ list: [EditParameter], _ what: String) throws(MaskReadError) -> [Double] {
        try list.map { item throws(MaskReadError) in
            guard case .number(let number) = item, number.isFinite else { throw .invalid("\(what) holds a non-number") }
            return number
        }
    }
}
