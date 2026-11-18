import Foundation

/// Circular heal and clone spots (docs/features/healing).
///
/// One operation of kind `spots` holds every spot, in placement order, as a
/// list of objects (schema version 2, as masks). Positions are unit
/// coordinates of the mask frame (the oriented decoded image, before turns,
/// straightening and crop, `LocalAdjustments`); sizes are fractions of its
/// long edge. Spots render first, after the Lens heading's steps and before
/// every other module and the crop, so they stay on the same picture content
/// whatever the crop does (`SpotRenderer`).
///
/// Reading is strict, as for masks: a value of the wrong type, an unknown key
/// or mode, or more than `SpotLimits.spots` spots makes the whole stack
/// unreadable (`EditStack.DecodingFailure`), so nothing ever writes back a
/// copy with a spot missing. A new key or mode needs a new `kindVersion`.
/// Numbers out of range are clamped.
public struct Spots: Hashable, Sendable {
    public static let kind: EditOperationKind = "spots"

    public var spots: [Spot] = []

    public init(spots: [Spot] = []) {
        self.spots = spots
    }

    public var isIdentity: Bool { spots.isEmpty }

    /// Spots that change the picture.
    public var renderedSpots: [Spot] {
        spots.filter { $0.opacity > 0 }
    }

    public var parameters: [String: EditParameter] {
        guard !spots.isEmpty else { return [:] }
        return ["spots": .list(spots.map { .object($0.parameters) })]
    }

    init(_ parameters: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(parameters, allowed: ["spots"])
        try reader.checkKeys()
        spots = try reader.objects("spots").map { values throws(MaskReadError) in try Spot(values) }
        try SpotLimits.check(self)
    }

    /// Checks a stored operation of this kind, as `EditStack.decode` does.
    /// The errors are `MaskReadError`'s: the same strict reading of stored objects.
    static func validate(_ operation: EditOperation) throws(MaskReadError) {
        guard operation.kind == kind, operation.kindVersion == 1 else { return }
        _ = try Spots(operation.parameters)
    }
}

/// Bounds on what a stack may hold (PRD R10). Enforced when spots are added;
/// a stored stack over them is unreadable, never truncated.
public enum SpotLimits {
    /// The PRD's proposed cap. A heal is one small kernel pass over its own
    /// square, so 100 spots render in a few milliseconds more than none at
    /// the loupe's size (status.md, "Measurements").
    public static let spots = 100

    static func check(_ spots: Spots) throws(MaskReadError) {
        guard spots.spots.count <= Self.spots else { throw .exceedsLimits("\(spots.spots.count) spots") }
    }

    /// A click can add a spot: the photo has room for one more.
    public static func canAddSpot(to spots: Spots) -> Bool {
        spots.spots.count < Self.spots
    }

    /// Whether `spots` may be saved.
    public static func allows(_ spots: Spots) -> Bool {
        spots.spots.count <= Self.spots
    }
}

/// How a spot fills its circle.
public enum SpotMode: String, CaseIterable, Sendable {
    /// The source's texture, its tone and color matched to the spot's
    /// surroundings (a membrane over the circle, `SpotRenderer`).
    case heal
    /// The source copied as it is.
    case clone
}

/// One spot: a circle, the circle it copies from, and how.
public struct Spot: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var mode: SpotMode
    /// The circle's center, unit coordinates of the mask frame (y down).
    public var center: MaskPoint
    /// The radius, as a fraction of the mask frame's long edge.
    public var size: Double
    /// The source circle's center (same radius), unit coordinates of the mask frame.
    public var source: MaskPoint
    /// 0 … 100: the share of the radius over which the fix fades out.
    public var feather: Double
    /// 0 … 100: how much of the fix shows.
    public var opacity: Double

    /// What a stored size is clamped to: from half a pixel on a 1000 px edge
    /// to a quarter of the long edge (the inspector offers 0.1 % … 10 %).
    public static let sizeRange: ClosedRange<Double> = 0.0005...0.25
    public static let percentRange: ClosedRange<Double> = 0...100
    public static let coordinateRange: ClosedRange<Double> = 0...1
    static let keys: Set<String> = ["id", "mode", "x", "y", "size", "sourceX", "sourceY", "feather", "opacity"]

    public static let defaultFeather = 50.0
    public static let defaultOpacity = 100.0

    public init(id: UUID = UUID(), mode: SpotMode = .heal, center: MaskPoint, size: Double, source: MaskPoint,
                feather: Double = Spot.defaultFeather, opacity: Double = Spot.defaultOpacity) {
        self.id = id
        self.mode = mode
        self.center = center
        self.size = size
        self.source = source
        self.feather = feather
        self.opacity = opacity
    }

    var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("id", id.uuidString)
        out.set("mode", mode.rawValue, default: SpotMode.heal.rawValue)
        out.set("x", center.x)
        out.set("y", center.y)
        out.set("size", size)
        out.set("sourceX", source.x)
        out.set("sourceY", source.y)
        out.set("feather", feather, default: Self.defaultFeather)
        out.set("opacity", opacity, default: Self.defaultOpacity)
        return out.values
    }

    init(_ values: [String: EditParameter]) throws(MaskReadError) {
        let reader = ObjectReader(values, allowed: Self.keys)
        try reader.checkKeys()
        guard let id = UUID(uuidString: try reader.string("id") ?? "") else { throw .invalid("a spot without an id") }
        self.id = id
        let modeName = try reader.string("mode") ?? SpotMode.heal.rawValue
        guard let mode = SpotMode(rawValue: modeName) else { throw .invalid("spot mode \(modeName)") }
        self.mode = mode
        // Position, size and source have no default: a spot without them is damaged.
        for key in ["x", "y", "size", "sourceX", "sourceY"] where values[key] == nil {
            throw .invalid("a spot without \(key)")
        }
        let range = Self.coordinateRange
        center = MaskPoint(x: try reader.number("x", range, default: 0.5), y: try reader.number("y", range, default: 0.5))
        size = try reader.number("size", Self.sizeRange, default: 0.003)
        source = MaskPoint(x: try reader.number("sourceX", range, default: 0.5),
                           y: try reader.number("sourceY", range, default: 0.5))
        feather = try reader.number("feather", Self.percentRange, default: Self.defaultFeather)
        opacity = try reader.number("opacity", Self.percentRange, default: Self.defaultOpacity)
    }
}
