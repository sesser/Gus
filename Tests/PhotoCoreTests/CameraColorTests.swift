import CoreImage
import Foundation
import PhotoFixtures
import Testing
@testable import PhotoCore

/// Kelvin and tint against chromaticity (issue #170, R1 and R4): the numbers
/// of the White Balance group must mean the same light to both decoders.
@Suite("Color temperature")
struct ColorTemperatureTests {
    /// CIE standard illuminants, from their published chromaticities (CIE
    /// 15:2004, 2° observer). Illuminant A is a black body at 2856 K, so
    /// its tint is 0; the D series lie 0.003 above the black body's colors
    /// in (u, v), which the tint scale of 3000 shows as about +10.
    /// Robertson's table reads temperatures to a few Kelvin.
    @Test("Known illuminants have their temperatures", arguments: [
        ("A", 0.44757, 0.40745, 2856.0, 0.0), ("D50", 0.34567, 0.35850, 5003.0, 10.0),
        ("D65", 0.31271, 0.32902, 6504.0, 10.0), ("D75", 0.29902, 0.31485, 7504.0, 10.0),
    ])
    func knownIlluminants(name: String, x: Double, y: Double, kelvin: Double, tint: Double) {
        let measured = ColorTemperature(Chromaticity(x: x, y: y))
        #expect(abs(measured.kelvin - kelvin) < 12, "\(name): \(measured.kelvin) K")
        #expect(abs(measured.tint - tint) < 2, "\(name): tint \(measured.tint)")
    }

    @Test("A temperature and tint's chromaticity reads back as the same temperature and tint")
    func roundTrip() {
        var worstKelvin = 0.0, worstTint = 0.0
        for mired in stride(from: 20.0, through: 500, by: 7) {
            for tint in [-150.0, -40, 0, 25, 150] {
                let asked = ColorTemperature(kelvin: 1_000_000 / mired, tint: tint)
                let read = ColorTemperature(asked.chromaticity)
                worstKelvin = max(worstKelvin, abs(read.kelvin / asked.kelvin - 1))
                worstTint = max(worstTint, abs(read.tint - asked.tint))
            }
        }
        // Reading back interpolates between the same two lines by distance instead of by
        // reciprocal temperature: the two agree to a part in a thousand, a few Kelvin.
        #expect(worstKelvin < 2e-3, "\(worstKelvin)")
        #expect(worstTint < 0.5, "\(worstTint)")
    }

    @Test("Warmer light has more red in it, and a positive tint is toward green")
    func directions() {
        let warm = ColorTemperature(kelvin: 3000).chromaticity, cool = ColorTemperature(kelvin: 8000).chromaticity
        #expect(warm.x > cool.x)
        let neutral = ColorTemperature(kelvin: 5500, tint: 0).chromaticity
        let green = ColorTemperature(kelvin: 5500, tint: 60).chromaticity
        // Green is up in the chromaticity diagram.
        #expect(green.y > neutral.y)
    }

    /// One stored Kelvin and tint must be the same light for the system's
    /// RAW decoder and for LibRaw's color step. `CIRAWFilter` says which
    /// chromaticity it takes a temperature and tint for; it is ours, to
    /// single precision (its properties are floats). Needs a raw the
    /// system decoder reads: the 1536 x 1152 synthetic DNG on this Mac.
    @Test("The system RAW decoder gives the same chromaticity for a Kelvin and tint")
    func matchesTheSystemDecoder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try LibRawDecoderTests.dng(in: folder, "large", width: 1536, height: 1152)
            guard SystemRAWDecoder.reads(url), let raw = CIRAWFilter(imageURL: url) else {
                print("ColorTemperatureTests: the system RAW decoder does not read the 1536 x 1152 DNG here; not compared")
                return
            }
            var worst = 0.0
            for mired in stride(from: 20.0, through: 500, by: 5) {
                for tint in [-150.0, -60, 0, 24, 80, 150] {
                    raw.neutralTemperature = Float(1_000_000 / mired)
                    raw.neutralTint = Float(tint)
                    let theirs = raw.neutralChromaticity
                    let ours = ColorTemperature(kelvin: Double(raw.neutralTemperature), tint: Double(raw.neutralTint)).chromaticity
                    worst = max(worst, abs(ours.x - theirs.x), abs(ours.y - theirs.y))
                    // And back: its reading of a chromaticity is ours.
                    let read = ColorTemperature(Chromaticity(x: theirs.x, y: theirs.y))
                    #expect(abs(read.kelvin / Double(raw.neutralTemperature) - 1) < 2e-3)
                    #expect(abs(read.tint - Double(raw.neutralTint)) < 0.5)
                }
            }
            // Single precision holds a chromaticity to 2⁻²⁴ of its value (6 × 10⁻⁸ of 1); ten times that.
            #expect(worst < 1e-6, "largest difference in x or y: \(worst)")
        }
    }

    /// Where `ColorTemperature`'s figures come from: the measurement its
    /// comment describes, repeated. Each of the 31 lines is where the
    /// system decoder has it (the black body's color at tint 0, the line's
    /// direction at a tint either way), the misprinted one included; below
    /// the coolest line it continues the last two; and it reads a
    /// chromaticity beyond the lines as the nearest of those it reads
    /// between, with the tint we give it.
    @Test("Every line of the table, and what lies beyond them, is the system RAW decoder's")
    func linesAreTheSystemDecoders() async throws {
        try await RepositoryFiles.withTemporaryDirectory { folder in
            let url = try LibRawDecoderTests.dng(in: folder, "large", width: 1536, height: 1152)
            guard SystemRAWDecoder.reads(url), let raw = CIRAWFilter(imageURL: url) else {
                print("ColorTemperatureTests: the system RAW decoder does not read the 1536 x 1152 DNG here; lines not compared")
                return
            }
            // The table's temperatures (the first is infinite), then two below its last, 1667 K.
            let temperatures = ColorTemperature.lines.map { Float(1_000_000 / $0.mired) } + [1500, 1000]
            #expect(temperatures.count == 33 && temperatures[0] == .infinity)
            for kelvin in temperatures {
                for tint: Float in [-150, 0, 150] {
                    raw.neutralTemperature = kelvin
                    raw.neutralTint = tint
                    let theirs = raw.neutralChromaticity
                    let ours = ColorTemperature(kelvin: Double(kelvin), tint: Double(tint)).chromaticity
                    #expect(abs(ours.x - theirs.x) < 1e-6 && abs(ours.y - theirs.y) < 1e-6, "\(kelvin) K, tint \(tint)")
                }
            }
            // Hotter than 100,000 K and cooler than 1667 K, read back.
            for kelvin in [400_000.0, 150_000, 1500, 1200] {
                for tint in [-60.0, 0, 60] {
                    let light = ColorTemperature(kelvin: kelvin, tint: tint).chromaticity
                    raw.neutralChromaticity = CGPoint(x: light.x, y: light.y)
                    let ours = ColorTemperature(light)
                    #expect(abs(ours.kelvin / Double(raw.neutralTemperature) - 1) < 1e-5, "\(kelvin) K: \(ours.kelvin) against \(raw.neutralTemperature)")
                    #expect(abs(ours.tint - Double(raw.neutralTint)) < 0.01, "\(kelvin) K, tint \(tint): \(ours.tint) against \(raw.neutralTint)")
                }
            }
        }
    }

    @Test("Light beyond the lines reads as the nearest line, and every reading is a number")
    func beyondTheLines() {
        // Nothing reads hotter than the second line or cooler than the last, as the system decoder has it.
        #expect(ColorTemperature(ColorTemperature(kelvin: 400_000, tint: 20).chromaticity).kelvin == 100_000)
        #expect(ColorTemperature(ColorTemperature(kelvin: .infinity).chromaticity).kelvin == 100_000)
        #expect(abs(ColorTemperature(ColorTemperature(kelvin: 1200, tint: -20).chromaticity).kelvin - 1_000_000 / 600) < 1e-9)
        // At the ends themselves nothing jumps.
        #expect(abs(ColorTemperature(ColorTemperature(kelvin: 99_999).chromaticity).kelvin - 99_999) < 1)
        #expect(abs(ColorTemperature(ColorTemperature(kelvin: 1667).chromaticity).kelvin - 1667) < 0.01)
        // A temperature that is none still has a chromaticity, and a chromaticity that is none a temperature.
        for kelvin in [0.0, -40, .nan] {
            let light = ColorTemperature(kelvin: kelvin).chromaticity
            #expect(light.x.isFinite && light.y.isFinite, "\(kelvin) K")
        }
        for light in [Chromaticity(x: .nan, y: 0.3), Chromaticity(x: 1.5, y: 0), Chromaticity(x: .infinity, y: .infinity)] {
            #expect(ColorTemperature(light) == ColorTemperature(kelvin: 6500, tint: 0), "\(light)")
        }
        #expect(ColorTemperature(Chromaticity(x: 0, y: 0)).kelvin.isFinite)
    }

    @Test("The table is the one the system decoder uses, its misprint included")
    func table() {
        let lines = ColorTemperature.lines
        #expect(lines.count == 31 && lines.first?.mired == 0 && lines.last?.mired == 600)
        #expect(zip(lines, lines.dropFirst()).allSatisfy { $0.mired < $1.mired })
        // Toward green is up and to the left on every line, at length one.
        #expect(lines.allSatisfy { $0.green.x < 0 && $0.green.y > 0 && abs(($0.green * $0.green).sum() - 1) < 1e-12 })
        // 325 mired: where its neighbors put the black body (0.2479) is not where the table has it.
        // Correcting it would make 2857 K to 3333 K another light here than in the system decoder.
        #expect(lines.first { $0.mired == 325 }?.locus.x == 0.24702)
    }
}

/// The camera color math (issue #170, R3 and R8), without Core Image:
/// `CameraColor` against the DNG specification's steps written again
/// (`CameraColorReference`).
@Suite("Camera color")
struct CameraColorTests {
    /// A Fujifilm X-E3's matrix as LibRaw has it (for D65), a made-up one
    /// for tungsten light, and made-up forward matrices whose rows sum to
    /// the D50 white (0.9643, 1, 0.8251), as a forward matrix's do.
    static let daylightMatrix: [Double] = [1.1434, -0.4948, -0.1210, -0.3746, 1.2042, 0.1903, -0.0666, 0.1479, 0.5235]
    static let tungstenMatrix: [Double] = [1.2200, -0.5600, -0.0700, -0.4300, 1.1900, 0.2600, -0.0500, 0.1200, 0.7100]
    static let daylightForward: [Double] = [0.6800, 0.1500, 0.1343, 0.2800, 0.6600, 0.0600, 0.0400, 0.0900, 0.6951]
    static let tungstenForward: [Double] = [0.7300, 0.1100, 0.1243, 0.3100, 0.6400, 0.0500, 0.0300, 0.0600, 0.7351]
    static let neutral: [Double] = [0.5, 1, 0.6]
    /// A camera unit's own calibration for each light (`CameraCalibration1`,
    /// `CameraCalibration2`) and its analog balance, as Adobe's converter
    /// writes them for some cameras: made up, near identity, and different
    /// from each other so that pairing one with the other light shows.
    static let daylightCalibration: [Double] = [1.0200, 0.0100, 0.0000, 0.0000, 1.0000, 0.0200, 0.0100, 0.0000, 0.9700]
    static let tungstenCalibration: [Double] = [0.9500, 0.0000, 0.0200, 0.0100, 1.0300, 0.0000, 0.0000, 0.0200, 1.0600]
    static let analogBalance: [Double] = [1.25, 1, 0.8]

    enum Kind: String, CaseIterable, Sendable {
        /// One matrix, as a file that is not a DNG has.
        case single
        /// Two matrices for two lights, read between by temperature.
        case dual
        /// Two matrices and two forward matrices.
        case forward
        /// Two matrices, a camera calibration for each and an analog
        /// balance (code review C3). The file names the daylight
        /// calibration first: each camera calibration must stay with its
        /// own light when the two are put in order of temperature.
        case calibrated
        /// The same with forward matrices, where the calibration is undone
        /// before the forward matrix (the reference neutral).
        case calibratedForward

        var hasForwardMatrices: Bool { self == .forward || self == .calibratedForward }
        var hasCalibration: Bool { self == .calibrated || self == .calibratedForward }

        var tags: SyntheticDNG.Color {
            switch self {
            case .single: .init(matrix1: CameraColorTests.daylightMatrix, illuminant1: 21, asShotNeutral: CameraColorTests.neutral)
            case .dual: .init(matrix1: CameraColorTests.tungstenMatrix, illuminant1: 17, matrix2: CameraColorTests.daylightMatrix,
                              illuminant2: 21, asShotNeutral: CameraColorTests.neutral)
            case .forward: .init(matrix1: CameraColorTests.tungstenMatrix, illuminant1: 17, matrix2: CameraColorTests.daylightMatrix,
                                 illuminant2: 21, forward1: CameraColorTests.tungstenForward,
                                 forward2: CameraColorTests.daylightForward, asShotNeutral: CameraColorTests.neutral)
            // Daylight first in the file, tungsten second.
            case .calibrated, .calibratedForward:
                .init(matrix1: CameraColorTests.daylightMatrix, illuminant1: 21, matrix2: CameraColorTests.tungstenMatrix,
                      illuminant2: 17,
                      forward1: self == .calibratedForward ? CameraColorTests.daylightForward : nil,
                      forward2: self == .calibratedForward ? CameraColorTests.tungstenForward : nil,
                      asShotNeutral: CameraColorTests.neutral, analogBalance: CameraColorTests.analogBalance,
                      calibration1: CameraColorTests.daylightCalibration, calibration2: CameraColorTests.tungstenCalibration)
            }
        }

        /// The camera as PhotoCore's types hold it, without a look.
        var color: CameraColor {
            func matrix(_ values: [Double]) -> Matrix3x3 { Matrix3x3(values) }
            let calibrations: [CameraProfile.Calibration] = switch self {
            case .single: [.init(illuminant: 6500, colorMatrix: matrix(CameraColorTests.daylightMatrix))]
            case .dual: [.init(illuminant: 2850, colorMatrix: matrix(CameraColorTests.tungstenMatrix)),
                         .init(illuminant: 6500, colorMatrix: matrix(CameraColorTests.daylightMatrix))]
            case .forward, .calibratedForward:
                [.init(illuminant: 2850, colorMatrix: matrix(CameraColorTests.tungstenMatrix),
                       forwardMatrix: matrix(CameraColorTests.tungstenForward)),
                 .init(illuminant: 6500, colorMatrix: matrix(CameraColorTests.daylightMatrix),
                       forwardMatrix: matrix(CameraColorTests.daylightForward))]
            case .calibrated: [.init(illuminant: 2850, colorMatrix: matrix(CameraColorTests.tungstenMatrix)),
                               .init(illuminant: 6500, colorMatrix: matrix(CameraColorTests.daylightMatrix))]
            }
            // Analog balance × camera calibration, the cooler light's first, as the profile has its calibrations.
            let balance = Matrix3x3.diagonal(SIMD3(CameraColorTests.analogBalance[0], CameraColorTests.analogBalance[1],
                                                   CameraColorTests.analogBalance[2]))
            let calibration = hasCalibration
                ? [balance * matrix(CameraColorTests.tungstenCalibration), balance * matrix(CameraColorTests.daylightCalibration)] : []
            return CameraColor(profile: CameraProfile(name: "test", calibrations: calibrations),
                               asShotNeutral: SIMD3(CameraColorTests.neutral[0], CameraColorTests.neutral[1], CameraColorTests.neutral[2]),
                               calibration: calibration)
        }

        /// The same camera for the reference: the tags' values, and the
        /// temperatures the EXIF light sources stand for (17, standard
        /// light A: 2850 K; 21, D65: 6500 K).
        var reference: CameraColorReference.Camera {
            func rows(_ values: [Double]) -> [[Double]] { [Array(values[0..<3]), Array(values[3..<6]), Array(values[6..<9])] }
            let daylight = rows(CameraColorTests.daylightMatrix), tungsten = rows(CameraColorTests.tungstenMatrix)
            let calibrations: [(kelvin: Double, colorMatrix: [[Double]], forwardMatrix: [[Double]]?)] = switch self {
            case .single: [(6500, daylight, nil)]
            case .dual: [(2850, tungsten, nil), (6500, daylight, nil)]
            case .forward, .calibratedForward: [(2850, tungsten, rows(CameraColorTests.tungstenForward)),
                                                (6500, daylight, rows(CameraColorTests.daylightForward))]
            case .calibrated: [(2850, tungsten, nil), (6500, daylight, nil)]
            }
            var camera = CameraColorReference.Camera(calibrations: calibrations, asShotNeutral: CameraColorTests.neutral)
            if hasCalibration {
                camera.cameraCalibrations = [rows(CameraColorTests.tungstenCalibration), rows(CameraColorTests.daylightCalibration)]
                camera.analogBalance = CameraColorTests.analogBalance
            }
            return camera
        }
    }

    /// White balances to render with: nil is As Shot.
    static let balances: [ColorTemperature?] = [
        nil, ColorTemperature(kelvin: 2850, tint: 0), ColorTemperature(kelvin: 4000, tint: -30),
        ColorTemperature(kelvin: 5500, tint: 0), ColorTemperature(kelvin: 7500, tint: 20),
    ]

    static func kelvin(of white: (x: Double, y: Double)) -> Double {
        ColorTemperature(Chromaticity(x: white.x, y: white.y)).kelvin
    }

    /// The reference, prepared for one camera and white balance.
    static func reference(kind: Kind, balance: ColorTemperature?, exposure: Double = 0) -> CameraColorReference.Prepared {
        var camera = kind.reference
        camera.exposure = exposure
        let white: (x: Double, y: Double)
        if let balance {
            let chromaticity = balance.chromaticity
            white = (chromaticity.x, chromaticity.y)
        } else {
            white = CameraColorReference.white(camera, ofNeutral: camera.asShotNeutral, kelvinOf: kelvin(of:))
        }
        return CameraColorReference.prepare(camera, white: white, kelvin: kelvin(of: white), asShot: balance == nil)
    }

    @Test("Between two calibrations the weight is linear in reciprocal temperature, and all of the nearer one outside them")
    func interpolationWeight() {
        let profile = Kind.dual.color.profile
        #expect(profile.weightOfFirst(at: 2000) == 1)
        #expect(profile.weightOfFirst(at: 2850) == 1)
        #expect(profile.weightOfFirst(at: 6500) == 0)
        #expect(profile.weightOfFirst(at: 9000) == 0)
        // (1/4000 − 1/6500) / (1/2850 − 1/6500)
        #expect(abs(profile.weightOfFirst(at: 4000) - 0.488012) < 1e-5)
        #expect(Kind.single.color.profile.weightOfFirst(at: 3000) == 1)
        // Given in either order, the cooler light's calibration is the first.
        let reversed = CameraProfile(name: "reversed", calibrations: profile.calibrations.reversed())
        #expect(reversed.calibrations.map(\.illuminant) == [2850, 6500])
        // A forward matrix is used only when every calibration has one.
        #expect(profile.forwardMatrix(at: 4000) == nil)
        #expect(Kind.forward.color.profile.forwardMatrix(at: 4000) != nil)
        var half = Kind.forward.color.profile
        half.calibrations[0].forwardMatrix = nil
        #expect(half.forwardMatrix(at: 4000) == nil)
    }

    @Test("EXIF light sources have the temperatures a DNG's calibration illuminants stand for")
    func lightSources() {
        #expect(CameraProfile.kelvin(ofLightSource: 17) == 2850)
        #expect(CameraProfile.kelvin(ofLightSource: 21) == 6500)
        #expect(CameraProfile.kelvin(ofLightSource: 23) == 5000)
        #expect(CameraProfile.kelvin(ofLightSource: 20) == 5500)
        #expect(CameraProfile.kelvin(ofLightSource: 22) == 7500)
        #expect(CameraProfile.kelvin(ofLightSource: 24) == 3200)
        #expect(CameraProfile.kelvin(ofLightSource: 0) == nil)
        #expect(CameraProfile.kelvin(ofLightSource: 255) == nil)
    }

    /// The three tables `CameraProfile.kelvin(ofLightSource:)` reads, by where each comes from.
    @Test("A named kind of light is its White Balance mode's, a fluorescent lamp the middle of EXIF's range, a standard light its round number")
    func lightSourceTables() {
        // EXIF names these without a temperature; the White Balance group has one for each.
        let named: [(Int, WhiteBalance.Preset)] = [(1, .daylight), (2, .fluorescent), (3, .tungsten), (4, .flash),
                                                   (9, .daylight), (10, .cloudy), (11, .shade)]
        for (code, mode) in named {
            let kelvin = CameraProfile.kelvin(ofLightSource: code)
            #expect(kelvin != nil && kelvin == mode.neutral?.temperature, "light source \(code)")
        }
        // EXIF 2.3: D 5700 to 7100 K, N 4600 to 5500 K, W 3800 to 4500 K, WW 3250 to 3800 K, L 2600 to 3250 K.
        let lamps: [(Int, Double)] = [(12, 6400), (13, 5050), (14, 4150), (15, 3525), (16, 2925)]
        for (code, kelvin) in lamps {
            #expect(CameraProfile.kelvin(ofLightSource: code) == kelvin, "light source \(code)")
        }
        // Standard lights B and C: the CIE's 4874 K and 6774 K to the nearest 50 K, as A's 2856 K is 2850.
        #expect(CameraProfile.kelvin(ofLightSource: 18) == 4850)
        #expect(CameraProfile.kelvin(ofLightSource: 19) == 6750)
        // Values EXIF reserves name no light.
        for code in [-1, 5, 8, 25, 100, 254, 256] {
            #expect(CameraProfile.kelvin(ofLightSource: code) == nil, "light source \(code)")
        }
    }

    @Test("A neutral's white point and a white point's neutral are each other's inverse", arguments: Kind.allCases)
    func neutralAndWhite(kind: Kind) throws {
        let color = kind.color
        #expect(color.isUsable)
        let white = try #require(color.asShotWhite)
        let back = try #require(color.neutral(for: white))
        #expect((back - color.asShotNeutral).max() < 1e-6 && (color.asShotNeutral - back).max() < 1e-6)
        // The reference finds the same white point.
        let theirs = CameraColorReference.white(kind.reference, ofNeutral: Self.neutral, kelvinOf: Self.kelvin(of:))
        #expect(abs(white.x - theirs.x) < 1e-6 && abs(white.y - theirs.y) < 1e-6)
        // A believable light: this neutral is daylight to the X-E3's matrix. (With the made-up
        // analog balance and calibration it is another light, but still one.)
        let asShot = try #require(color.asShot)
        #expect((kind.hasCalibration ? 2000...12000 : 4500...7000).contains(asShot.kelvin), "\(asShot)")
        for balance in Self.balances.compactMap({ $0 }) {
            let neutral = try #require(color.neutral(for: balance.chromaticity))
            #expect(neutral.max() == 1 && neutral.min() > 0)
            let read = try #require(color.white(ofNeutral: neutral))
            #expect(abs(read.x - balance.chromaticity.x) < 1e-5 && abs(read.y - balance.chromaticity.y) < 1e-5, "\(balance)")
        }
    }

    /// The specification's guessing ("iterate until the xy values converge")
    /// need not settle. Here the daylight calibration takes the neutral for
    /// candle light and the tungsten calibration takes it for blue sky, so
    /// each guess sends the next to the other light, for ever. A white point
    /// whose own temperature picks the matrix that gives it still exists
    /// between the two, and is found.
    @Test("A white point is found when the specification's guesses do not settle")
    func whitePointWithoutSettling() throws {
        let base = Matrix3x3(Self.daylightMatrix)
        func neutral(at kelvin: Double) -> SIMD3<Double> { base * ColorTemperature(kelvin: kelvin).chromaticity.xyz }
        let shot = neutral(at: 4000)
        let color = CameraColor(profile: CameraProfile(name: "unsettled", calibrations: [
            .init(illuminant: 2850, colorMatrix: Matrix3x3.diagonal(shot / neutral(at: 12000)) * base),
            .init(illuminant: 6500, colorMatrix: Matrix3x3.diagonal(shot / neutral(at: 2200)) * base),
        ]), asShotNeutral: shot)
        // The guessing by itself: from daylight to tungsten and back.
        func guess(after kelvin: Double) throws -> Double {
            let toXYZ = try #require(color.xyzToCamera(at: kelvin).inverse)
            return ColorTemperature(try #require(Chromaticity(xyz: toXYZ * shot))).kelvin
        }
        #expect(try guess(after: 6500) < 2850)
        #expect(try guess(after: 2850) > 6500)
        // The white point found is consistent: its temperature lies between the lights, and its neutral is the one asked about.
        let white = try #require(color.white(ofNeutral: color.asShotNeutral))
        let kelvin = ColorTemperature(white).kelvin
        #expect(kelvin > 2850 && kelvin < 6500, "\(kelvin) K")
        #expect(abs(try guess(after: kelvin) / kelvin - 1) < 1e-8)
        let back = try #require(color.neutral(for: white))
        #expect((back - color.asShotNeutral).max() < 1e-6 && (color.asShotNeutral - back).max() < 1e-6, "\(back)")
        #expect(color.isUsable)
    }

    @Test("A neutral under the chosen white comes out neutral, and white as white", arguments: Kind.allCases)
    func neutralStaysNeutral(kind: Kind) throws {
        for balance in Self.balances {
            let white = try #require(balance?.chromaticity ?? kind.color.asShotWhite)
            let matrix = try #require(kind.color.cameraToWorking(white: white))
            let rendered = matrix * SIMD3(1, 1, 1)
            // The made-up forward matrices are written to four decimals.
            let tolerance = kind.hasForwardMatrices ? 2e-4 : 1e-9
            #expect(abs(rendered.x - 1) < tolerance && abs(rendered.y - 1) < tolerance && abs(rendered.z - 1) < tolerance,
                    "\(kind) \(String(describing: balance)): \(rendered)")
        }
    }

    /// A camera whose primaries are sRGB's, as shot under D65: the color
    /// step is then the sRGB to Rec. 2020 conversion, known from the two
    /// standards (the D65 to D50 adaptation and back cancel).
    @Test("An sRGB camera under D65 is converted as sRGB is")
    func knownCamera() throws {
        let color = CameraColor(profile: CameraProfile(name: "sRGB", calibrations: [
            .init(illuminant: 6500, colorMatrix: Matrix3x3(SyntheticDNG.Color.sRGBMatrix)),
        ]), asShotNeutral: SIMD3(1, 1, 1))
        let asShot = try #require(color.asShot)
        #expect(abs(asShot.kelvin - 6504) < 12)
        let white = try #require(color.asShotWhite)
        let matrix = try #require(color.cameraToWorking(white: white))
        // IEC 61966-2-1's sRGB to XYZ, then XYZ to Rec. 2020.
        let sRGBToXYZ: [[Double]] = [[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]
        let expected = OutputReference.multiply(OutputReference.invert(ColorMath.rec2020ToXYZ), sRGBToXYZ)
        for (row, values) in zip(matrix.rows, expected) {
            // The two standards' matrices are printed to four decimals.
            #expect(abs(row.x - values[0]) < 5e-4 && abs(row.y - values[1]) < 5e-4 && abs(row.z - values[2]) < 5e-4,
                    "\(row) against \(values)")
        }
    }

    /// The math alone, before Core Image has any part in it.
    @Test("The color math is the DNG specification's, for one matrix, two, and forward matrices", arguments: Kind.allCases)
    func mathMatchesReference(kind: Kind) throws {
        var random = SplitMix64(seed: 11)
        let color = kind.color
        let smallest = color.asShotNeutral.min()
        let scale = (smallest / color.asShotNeutral) * LibRawDecoder.whiteMargin
        for balance in Self.balances {
            let transform = try #require(color.transform(for: balance, channelScale: scale))
            let gain = try #require(transform.gain), matrix = try #require(transform.matrix)
            let reference = Self.reference(kind: kind, balance: balance)
            for _ in 0..<200 {
                // A decode's values: each channel up to its own saturation.
                let decoded = (0..<3).map { channel in
                    Double(random.next() >> 11) / Double(1 << 53) * (smallest / color.asShotNeutral[channel])
                }
                let balanced = (SIMD3(decoded[0], decoded[1], decoded[2]) * gain)
                    .clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
                let ours = matrix * balanced
                let theirs = reference.render(decoded)
                for channel in 0..<3 {
                    #expect(abs(ours[channel] - theirs[channel]) < 1e-6, "\(kind) \(String(describing: balance)) \(decoded)")
                }
            }
        }
    }

    /// Code review C3, on the math alone: the analog balance and the camera
    /// calibration are part of XYZ to camera, each calibration with its own
    /// light, read between the two as the color matrices are.
    @Test("A camera's calibration and analog balance are part of its matrix, each calibration with its own light")
    func calibrationAndAnalogBalance() throws {
        let calibrated = Kind.calibrated.color, plain = Kind.dual.color
        #expect(calibrated.calibration.count == 2)
        // Without them the camera is another camera: another neutral for the same light, another white for the same neutral.
        let daylight = ColorTemperature(kelvin: 5500, tint: 0).chromaticity
        let with = try #require(calibrated.neutral(for: daylight)), without = try #require(plain.neutral(for: daylight))
        #expect(abs(with.x - without.x) > 0.02 || abs(with.z - without.z) > 0.02, "\(with) against \(without)")
        let asShot = try #require(calibrated.asShot), plainAsShot = try #require(plain.asShot)
        #expect(abs(asShot.kelvin - plainAsShot.kelvin) > 200)
        // At or beyond a calibration's light, XYZ to camera is that light's balance × calibration × color matrix.
        let balance = Matrix3x3.diagonal(SIMD3(Self.analogBalance[0], Self.analogBalance[1], Self.analogBalance[2]))
        let tungsten = balance * Matrix3x3(Self.tungstenCalibration) * Matrix3x3(Self.tungstenMatrix)
        let day = balance * Matrix3x3(Self.daylightCalibration) * Matrix3x3(Self.daylightMatrix)
        for (kelvin, expected) in [(2500.0, tungsten), (2850, tungsten), (6500, day), (9000, day)] {
            let matrix = calibrated.xyzToCamera(at: kelvin)
            #expect(zip(matrix.values, expected.values).allSatisfy { abs($0 - $1) < 1e-12 }, "\(kelvin) K")
        }
        // Between them, each of the two is read between its own pair.
        let weight = calibrated.profile.weightOfFirst(at: 4000)
        let between = (weight * (balance * Matrix3x3(Self.tungstenCalibration)) + (1 - weight) * (balance * Matrix3x3(Self.daylightCalibration)))
            * (weight * Matrix3x3(Self.tungstenMatrix) + (1 - weight) * Matrix3x3(Self.daylightMatrix))
        #expect(zip(calibrated.xyzToCamera(at: 4000).values, between.values).allSatisfy { abs($0 - $1) < 1e-12 })
        // One calibration for both lights is used at every temperature.
        var one = calibrated
        one.calibration = [balance]
        #expect(one.calibration(at: 3000) == balance && one.calibration(at: 8000) == balance)
        #expect(plain.calibration(at: 4000) == .identity)
    }

    @Test("Color data that gives no white point is not usable, and has no transform")
    func unusableColor() {
        let singular = CameraColor(profile: CameraProfile(name: "singular", calibrations: [
            .init(illuminant: 6500, colorMatrix: Matrix3x3([1, 2, 3, 2, 4, 6, 0, 0, 1])),
        ]), asShotNeutral: SIMD3(0.5, 1, 0.6))
        #expect(!singular.isUsable)
        #expect(singular.transform(for: nil, channelScale: SIMD3(1, 1, 1)) == nil)
        let noNeutral = CameraColor(profile: Kind.single.color.profile, asShotNeutral: SIMD3(0, 1, 0.6))
        #expect(!noNeutral.isUsable)
        #expect(noNeutral.asShot != nil || noNeutral.transform(for: nil, channelScale: SIMD3(1, 1, 1)) == nil)
        let noProfile = CameraColor(profile: CameraProfile(name: "empty", calibrations: []), asShotNeutral: SIMD3(0.5, 1, 0.6))
        #expect(!noProfile.isUsable)
        // A neutral the matrix takes to a color without luminance is no light: it has no white point.
        for kind in Kind.allCases {
            let dark = kind.color.xyzToCamera(at: 6500) * SIMD3(1, -0.2, 0.5)
            #expect(kind.color.white(ofNeutral: dark) == nil, "\(kind)")
        }
        // A white balance far from any light still renders: the neutral is held above zero.
        let extreme = Kind.single.color.neutral(for: ColorTemperature(kelvin: 2000, tint: -150).chromaticity)
        #expect(extreme.map { $0.min() >= 0.001 && $0.max() == 1 } == true)
    }

    @Test("The tone curve passes through its points, rises all the way, and continues above white")
    func toneCurve() throws {
        let points = try #require(BaselineLook.toneCurve)
        #expect(points.count == BaselineLook.encodedKnots.count)
        for point in points {
            #expect(abs(CameraColorTransform.toneValue(points, at: point.input) - point.output) < 1e-9)
        }
        #expect(CameraColorTransform.toneValue(points, at: 0) == 0)
        #expect(abs(CameraColorTransform.toneValue(points, at: 1) - 1) < 1e-12)
        #expect(CameraColorTransform.toneValue(points, at: -0.2) == 0)
        var previous = -1.0
        for step in 0...2000 {
            let value = CameraColorTransform.toneValue(points, at: Double(step) / 1000)
            #expect(value >= previous, "at \(Double(step) / 1000)")
            previous = value
        }
        // Middle gray comes out brighter, as the system decoder's default curve makes it.
        #expect(CameraColorTransform.toneValue(points, at: 0.18) > 0.2)
        // The table Core Image reads is the same function.
        let table = CameraColorTransform.curveTable(points)
        #expect(table.count == CameraColorTransform.curveEntryCount * 3)
        for index in stride(from: 0, to: CameraColorTransform.curveEntryCount, by: 97) {
            let encoded = CameraColorTransform.curveDomainMaximum * Double(index) / Double(CameraColorTransform.curveEntryCount - 1)
            let expected = CameraColorTransform.encoded(CameraColorTransform.toneValue(points, at: CameraColorTransform.linear(encoded)))
            #expect(abs(Double(table[index * 3]) - expected) < 1e-6)
            #expect(table[index * 3] == table[index * 3 + 1] && table[index * 3] == table[index * 3 + 2])
        }
    }
}
