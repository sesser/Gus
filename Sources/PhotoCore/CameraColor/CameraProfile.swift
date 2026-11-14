import Foundation

/// How a camera's colors are turned into the working space: what the color
/// step after a LibRaw decode takes its inputs from (issue #170, R8).
///
/// The fields are those of a DNG camera profile (Adobe, "Digital Negative
/// (DNG) Specification", the camera profile tags and chapter 6, "Mapping
/// Camera Color Space to CIE XYZ Space"; read in version 1.6.0.0), so an
/// Adobe `.dcp` file can be read into one later (#89). The specification
/// gives no temperatures for calibration lights; those are this file's own,
/// and `kelvin(ofLightSource:)` says where each is from
/// (`THIRD_PARTY_NOTICES.md`).
///
/// Today's only profile is the built-in one, made from what LibRaw knows
/// about the camera (`CameraColor.builtIn`): its matrix or the DNG's own,
/// and the baseline look of `BaselineLook`. Nothing reads, stores or lists
/// profiles yet.
public struct CameraProfile: Sendable, Hashable {
    /// The camera's response under one light.
    public struct Calibration: Sendable, Hashable {
        /// The light's correlated color temperature in Kelvin
        /// (`CameraProfile.kelvin(ofLightSource:)` for a DNG's `CalibrationIlluminant`).
        public var illuminant: Double
        /// XYZ to camera RGB under that light (`ColorMatrix1`, `ColorMatrix2`).
        public var colorMatrix: Matrix3x3
        /// White-balanced camera RGB to XYZ with a D50 white
        /// (`ForwardMatrix1`, `ForwardMatrix2`). Used in place of the color
        /// matrix's inverse when every calibration has one.
        public var forwardMatrix: Matrix3x3?
        /// `ProfileHueSatMapData1`, `ProfileHueSatMapData2`: kept, not yet applied (`HueSaturationTable`).
        public var hueSaturationMap: HueSaturationTable?

        public init(illuminant: Double, colorMatrix: Matrix3x3, forwardMatrix: Matrix3x3? = nil,
                    hueSaturationMap: HueSaturationTable? = nil) {
            self.illuminant = illuminant
            self.colorMatrix = colorMatrix
            self.forwardMatrix = forwardMatrix
            self.hueSaturationMap = hueSaturationMap
        }
    }

    /// A DNG hue, saturation and value table (`ProfileHueSatMapData`,
    /// `ProfileLookTableData`): for each cell a hue shift in degrees, a
    /// saturation factor and a value factor.
    ///
    /// The profile value carries these so a `.dcp` file loses nothing when
    /// it is read (#89). **The color step does not apply them yet**: no
    /// profile this build can make has one (`CameraColorTransform`).
    public struct HueSaturationTable: Sendable, Hashable {
        public var hueDivisions: Int
        public var saturationDivisions: Int
        public var valueDivisions: Int
        /// Three values a cell, value by value, then hue, then saturation, as a DNG stores them.
        public var samples: [Float]
        /// `ProfileHueSatMapEncoding`, `ProfileLookTableEncoding`: the value axis is sRGB-encoded.
        public var valueIsEncoded: Bool

        public init(hueDivisions: Int, saturationDivisions: Int, valueDivisions: Int, samples: [Float],
                    valueIsEncoded: Bool = false) {
            self.hueDivisions = hueDivisions
            self.saturationDivisions = saturationDivisions
            self.valueDivisions = valueDivisions
            self.samples = samples
            self.valueIsEncoded = valueIsEncoded
        }
    }

    /// One point of a tone curve: linear light in, linear light out, 0 … 1 (`ProfileToneCurve`).
    public struct TonePoint: Sendable, Hashable {
        public var input: Double
        public var output: Double

        public init(_ input: Double, _ output: Double) {
            self.input = input
            self.output = output
        }
    }

    public var name: String
    /// One calibration, or two for different lights; the color step reads
    /// between two by the white point's temperature.
    public var calibrations: [Calibration]
    /// `ProfileLookTableData`: kept, not yet applied (`HueSaturationTable`).
    public var lookTable: HueSaturationTable?
    /// Applied after the baseline exposure, to each channel of the working
    /// space. Nil leaves the image linear.
    public var toneCurve: [TonePoint]?
    /// Stops added to the file's own baseline exposure (`BaselineExposureOffset`).
    public var baselineExposure: Double

    public init(name: String, calibrations: [Calibration], lookTable: HueSaturationTable? = nil,
                toneCurve: [TonePoint]? = nil, baselineExposure: Double = 0) {
        self.name = name
        self.calibrations = calibrations.sorted { $0.illuminant < $1.illuminant }
        self.lookTable = lookTable
        self.toneCurve = toneCurve
        self.baselineExposure = baselineExposure
    }

    /// The profile can turn camera colors into the working space: it has a
    /// calibration, and every color matrix has an inverse.
    public var isUsable: Bool {
        !calibrations.isEmpty && calibrations.allSatisfy {
            $0.illuminant > 0 && $0.colorMatrix.isFinite && $0.colorMatrix.inverse != nil
                && ($0.forwardMatrix?.isFinite ?? true)
        }
    }

    /// The weight of the cooler-light calibration (the first) for a white
    /// point of `kelvin`: linear in reciprocal temperature between the two
    /// lights, and all of the nearer one outside them (DNG Specification,
    /// "Camera to XYZ (D50) Transform"). 1 with a single calibration.
    public func weightOfFirst(at kelvin: Double) -> Double {
        guard calibrations.count >= 2, let low = calibrations.first, let high = calibrations.last,
              high.illuminant > low.illuminant else { return 1 }
        if kelvin <= low.illuminant { return 1 }
        if kelvin >= high.illuminant { return 0 }
        return (1 / kelvin - 1 / high.illuminant) / (1 / low.illuminant - 1 / high.illuminant)
    }

    /// XYZ to camera for a white point of `kelvin`.
    public func colorMatrix(at kelvin: Double) -> Matrix3x3 {
        guard let low = calibrations.first, let high = calibrations.last else { return .identity }
        let weight = weightOfFirst(at: kelvin)
        return weight * low.colorMatrix + (1 - weight) * high.colorMatrix
    }

    /// The forward matrix for a white point of `kelvin`; nil unless every calibration has one.
    public func forwardMatrix(at kelvin: Double) -> Matrix3x3? {
        guard let low = calibrations.first?.forwardMatrix, let high = calibrations.last?.forwardMatrix,
              calibrations.allSatisfy({ $0.forwardMatrix != nil }) else { return nil }
        let weight = weightOfFirst(at: kelvin)
        return weight * low + (1 - weight) * high
    }

    /// The correlated color temperature of the light an EXIF `LightSource`
    /// value names, which is what a DNG's `CalibrationIlluminant` tags hold
    /// ("The legal values for this tag are the same as the legal values for
    /// the LightSource EXIF tag"); nil for a value that names no light
    /// (0, unknown; 255, other, which a DNG 1.6 file describes in a tag of
    /// its own that is not read; anything reserved).
    ///
    /// The DNG specification asks for "the correlated color temperature for
    /// … the two calibration illuminants" and gives no figures. These are
    /// this file's, from three places, one table for each.
    public static func kelvin(ofLightSource code: Int) -> Double? {
        if let mode = namedLights[code] { return mode.neutral?.temperature }
        if let range = fluorescentLamps[code] { return (range.lowerBound + range.upperBound) / 2 }
        return standardLights[code]
    }

    /// Kinds of light EXIF names without a temperature (1 daylight, 2
    /// fluorescent, 3 tungsten, 4 flash, 9 fine weather, 10 cloudy weather,
    /// 11 shade): each is the light the White Balance mode of that name
    /// stands for, so the two cannot disagree.
    static let namedLights: [Int: WhiteBalance.Preset] = [
        1: .daylight, 2: .fluorescent, 3: .tungsten, 4: .flash, 9: .daylight, 10: .cloudy, 11: .shade,
    ]

    /// Fluorescent lamps by kind (12 daylight, 13 day white, 14 cool white,
    /// 15 white, 16 warm white): EXIF 2.3 (CIPA DC-008-2012) gives each a
    /// range of temperatures, restated here; the light is taken as the
    /// middle of its range.
    static let fluorescentLamps: [Int: ClosedRange<Double>] = [
        12: 5700...7100, 13: 4600...5500, 14: 3800...4500, 15: 3250...3800, 16: 2600...3250,
    ]

    /// Standard lights, in the round numbers they are known by. The D
    /// illuminants (20 D55, 21 D65, 22 D75, 23 D50) have their temperature
    /// in their name; the CIE's present figures for them are 3 or 4 K
    /// higher (D65: 6504 K). Standard lights A, B and C (17, 18, 19) are
    /// the CIE's 2856 K, 4874 K and 6774 K to the nearest 50 K, like the
    /// rest. ISO studio tungsten (24) is a 3200 K lamp.
    static let standardLights: [Int: Double] = [
        17: 2850, 18: 4850, 19: 6750, 20: 5500, 21: 6500, 22: 7500, 23: 5000, 24: 3200,
    ]
}
