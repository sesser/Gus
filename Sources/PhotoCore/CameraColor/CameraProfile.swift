import Foundation

/// How a camera's colors are turned into the working space: what the color
/// step after a LibRaw decode takes its inputs from (issue #170, R8).
///
/// The fields are those of a DNG camera profile (Adobe DNG Specification
/// 1.7.1, chapter 6, "Mapping Camera Color Space to CIE XYZ Space"), so an
/// Adobe `.dcp` file can be read into one later (#89). Today's only profile
/// is the built-in one, made from what LibRaw knows about the camera
/// (`CameraColor.builtIn`): its matrix or the DNG's own, and the baseline
/// look of `BaselineLook`. Nothing reads, stores or lists profiles yet.
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

    /// The temperature of an EXIF `LightSource` value, as a DNG's
    /// `CalibrationIlluminant` tags give it; nil for one that names no
    /// temperature (unknown, "other"). The fluorescent kinds are the middle
    /// of the ranges the EXIF specification gives them.
    public static func kelvin(ofLightSource code: Int) -> Double? {
        switch code {
        case 3, 17: 2850         // tungsten, standard light A
        case 24: 3200            // ISO studio tungsten
        case 23: 5000            // D50
        case 1, 4, 9, 18, 20: 5500 // daylight, flash, fine weather, standard light B, D55
        case 10, 19, 21: 6500    // cloudy, standard light C, D65
        case 11, 22: 7500        // shade, D75
        case 12: (5700 + 7100) / 2 // daylight fluorescent
        case 13: (4600 + 5500) / 2 // day white fluorescent
        case 2, 14: (3800 + 4500) / 2 // fluorescent, cool white fluorescent
        case 15: (3250 + 3800) / 2 // white fluorescent
        case 16: (2600 + 3250) / 2 // warm white fluorescent
        default: nil
        }
    }
}
