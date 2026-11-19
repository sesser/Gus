import CoreImage
import CoreImage.CIFilterBuiltins

/// A conversion to gray steered like colored filters on a lens for black and
/// white film (docs/features/bw-module, issue #218).
///
/// Five filters, Yellow, Orange, Red, Green and Blue, each 0 … 100: how much
/// of that filter is "on the lens". With every filter at 0 the result is the
/// photo's luminance by the Rec. 709 weights (PRD R3). Each filter has a
/// transmittance per channel of the working space (`Filter.transmittance`);
/// an amount `a` is that filter's density times `a / 100` (transmittance to
/// the power `a / 100`, as dye in gelatin, Beer–Lambert), filters on together
/// multiply, and the weights `luminance × transmittance` are normalized to sum
/// to 1, so a neutral gray keeps its level whatever the filters say (R4).
///
/// The module has an explicit on state, `isOn`, because "on with every filter
/// at 0" (an edit: the photo goes gray) must differ from "never used" (R1,
/// R12). Off by default and left out of the stack then, so a stack without
/// the module renders exactly as before (R13). Turned off from its check box
/// it keeps its values in `Adjustments.disabled`, as every group does.
///
/// Persisted as kind `blackAndWhite`: `on` (a boolean, default false) and one
/// number per filter, named after it (default 0).
public struct BlackAndWhite: AdjustmentModule {
    public static let kind: EditOperationKind = "blackAndWhite"

    /// The filters, in the order the Adjust tab lists them (warm to cool).
    public enum Filter: String, CaseIterable, Sendable {
        case yellow, orange, red, green, blue

        /// The share of each working-space channel (linear Rec. 2020 red,
        /// green, blue) the filter lets through at full strength: the
        /// engineer's estimates from the published pass bands of the classic
        /// black and white filters (yellow: long-pass from about 465 nm;
        /// orange: from about 530 to 560 nm; red: from about 580 to 600 nm;
        /// green: a band about 490 to 580 nm; blue: a band about 415 to 480
        /// nm), over the channels' approximate spectral bands. Only ratios
        /// within a filter and between filters matter: the mix is normalized.
        /// Recorded in docs/features/bw-module/status.md; not confirmed by
        /// the owner. Every value is above 0, so the mix never divides by 0.
        public var transmittance: SIMD3<Double> {
            switch self {
            case .yellow: SIMD3(1.00, 0.95, 0.25)
            case .orange: SIMD3(1.00, 0.50, 0.04)
            case .red: SIMD3(0.85, 0.08, 0.01)
            case .green: SIMD3(0.10, 0.80, 0.12)
            case .blue: SIMD3(0.04, 0.20, 0.85)
            }
        }
    }

    /// Every filter's range.
    public static let amountRange: ClosedRange<Double> = 0...100
    /// What a quick-set gives its filter: the filter itself (design §4).
    public static let quickSetAmount: Double = 100
    /// Rec. 709 luminance weights, applied to working-space values (PRD R3):
    /// the mix with every filter at 0.
    public static let luminanceWeights = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    /// The conversion applies (while the group is not turned off).
    public var isOn = false
    private var amounts: [Double] = Array(repeating: 0, count: Filter.allCases.count)

    public init(isOn: Bool = false, _ amounts: [Filter: Double] = [:]) {
        self.isOn = isOn
        for (filter, amount) in amounts { self[filter] = amount }
    }

    init(_ values: ParameterValues) {
        isOn = values.bool("on", default: false)
        // Stored values are kept as they are; the mix clamps what it uses.
        for (index, filter) in Filter.allCases.enumerated() {
            amounts[index] = values.number(filter.rawValue, default: 0)
        }
    }

    /// A filter's amount, 0 … 100. A value outside that range, or not a
    /// number, is refused: the amount stays as it was (PRD R2, AC5).
    public subscript(filter: Filter) -> Double {
        get { amounts[Self.index(filter)] }
        set {
            guard newValue.isFinite, Self.amountRange.contains(newValue) else { return }
            amounts[Self.index(filter)] = newValue
        }
    }

    private static func index(_ filter: Filter) -> Int {
        Filter.allCases.firstIndex(of: filter)!
    }

    /// Every filter at 0: the plain luminance mix.
    public var hasNoFilter: Bool {
        Filter.allCases.allSatisfy { abs(self[$0]) < Self.tolerance }
    }

    /// The filter whose quick-set the values are: that filter at
    /// `quickSetAmount`, the others at 0, compared as the sliders round them
    /// (design §3.2). Nil for any other mix. Says nothing about whether the
    /// conversion applies.
    public var quickSet: Filter? {
        let set = Filter.allCases.filter { abs(self[$0]) >= Self.tolerance }
        guard set.count == 1, let filter = set.first,
              abs(self[filter] - Self.quickSetAmount) < Self.tolerance else { return nil }
        return filter
    }

    /// Half a slider step (1).
    private static let tolerance = 0.5

    /// One filter at `quickSetAmount`, the others at 0, and on (PRD R6).
    public mutating func choose(_ filter: Filter) {
        for other in Filter.allCases { self[other] = other == filter ? Self.quickSetAmount : 0 }
        isOn = true
    }

    /// Every filter at 0, and on: the luminance as gray (Adjust ▸ Black &
    /// White ▸ No Filter).
    public mutating func clearFilters() {
        for filter in Filter.allCases { self[filter] = 0 }
        isOn = true
    }

    /// True when the filters' values differ from `other`'s (on or off aside).
    public func filtersDiffer(from other: BlackAndWhite) -> Bool {
        amounts != other.amounts
    }

    /// The channel weights of the gray mix: luminance times the filters'
    /// transmittance, normalized to sum to 1 (PRD R4). Amounts outside 0 …
    /// 100 count as their nearest end.
    public var weights: SIMD3<Double> {
        var transmittance = SIMD3<Double>(repeating: 1)
        for filter in Filter.allCases {
            let strength = min(max(self[filter], Self.amountRange.lowerBound), Self.amountRange.upperBound) / 100
            guard strength > 0 else { continue }
            let t = filter.transmittance
            transmittance *= SIMD3(pow(t.x, strength), pow(t.y, strength), pow(t.z, strength))
        }
        let weighted = Self.luminanceWeights * transmittance
        return weighted / (weighted.x + weighted.y + weighted.z)
    }

    public var parameters: [String: EditParameter] {
        var out = ParameterBuilder()
        out.set("on", isOn, default: false)
        for filter in Filter.allCases {
            out.set(filter.rawValue, self[filter], default: 0)
        }
        return out.values
    }
}

extension AdjustmentRenderer {
    /// The gray mix over `image` in the working space: every channel becomes
    /// the same weighted sum of red, green and blue. A color matrix, so
    /// nothing is clamped: values above 1 (and below 0) pass through (PRD R8),
    /// and the three output channels are the same computation, so equal.
    static func blackAndWhite(_ image: CIImage, _ settings: BlackAndWhite) -> CIImage {
        let w = settings.weights
        let row = CIVector(x: CGFloat(w.x), y: CGFloat(w.y), z: CGFloat(w.z), w: 0)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = row
        filter.gVector = row
        filter.bVector = row
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return filter.outputImage ?? image
    }
}
