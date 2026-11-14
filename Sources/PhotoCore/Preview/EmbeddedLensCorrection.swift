import CoreImage
import Foundation

/// A camera's own lens corrections (`FujifilmRAF.LensTables`) as they are
/// applied to LibRaw's decode: geometric distortion, lateral chromatic
/// aberration and vignetting, in one resampling of the decoded image, in its
/// linear light, before anything else sees it. The system's RAW decoder does
/// the same for the raws it reads, which is why these raws need it done here.
///
/// The math follows darktable's embedded-metadata lens correction
/// (`src/iop/lens.cc`, its second algorithm for Fujifilm, after Freddie
/// Witherden's; GPL 3 or later, see `THIRD_PARTY_NOTICES.md`), written again
/// in Swift and Metal:
///
/// - The tables are linear between their knots, constant beyond the last.
/// - Radii are fractions of half the frame's diagonal, about the frame's
///   center. The knots are radii of the recorded (uncorrected) image.
/// - A point recorded at radius r belongs at r / m(r), m = 1 + distortion / 100.
///   The corrected picture has the recorded one's scale at its center, so its
///   pixel at radius ρ takes green from the r with r / m(r) = ρ.
/// - Red and blue are taken from r · (1 + shift(r)), their own tables' shift.
/// - Every sample is divided by the share of light its place on the sensor
///   got: vignetting(r) / 100, at the radius the sample is taken from. The
///   result ends at the decode's white, 1 (not darktable's: its pipeline
///   keeps values above white). LibRaw's image ends there, so a clipped area
///   is 1 wherever it lies; multiplied on, it would be white at the center
///   and up to 100 / vignetting times brighter toward the corners, a ring
///   that shows as soon as Exposure or Highlights is pulled down. The camera
///   and the system decoder clip after the gain too. Values the gain lifts
///   past white are highlights the recorded frame held and the corrected one
///   has no room for, as in the camera's own picture.
///
/// - The corrected picture is then scaled about its center by the largest
///   source-over-destination ratio any color has between the frame's short
///   side and its corner (`outputScale`), so that it fills the frame and no
///   place of it is taken from outside the recorded frame: a little smaller
///   for barrel distortion (the edges' middles stay where they were, the
///   corners come from further in), larger for pincushion.
///
/// That last step is darktable's choice for filling its frame. For the
/// X-Trans files compared it is also what the camera does: with it the
/// corrected render of an X-E3 file lines up with the JPEG the camera
/// embedded in it to a third of that JPEG's pixels (`LibRawFallbackTests`),
/// where at the recorded scale it is off by 1.5% of the radius. It is not
/// every camera's rule: an X-A5's own JPEG keeps the recorded scale at the
/// center (code review Q12; that camera's files are read by the system
/// decoder, so none takes this path today).
struct EmbeddedLensCorrection: Sendable, Equatable {
    /// Entries of each lookup table. Between two entries the kernel
    /// interpolates linearly. The functions are smooth between the camera's
    /// knots, where that is exact to 10⁻⁷; at a knot their slope jumps, and
    /// the one entry pair around it is off by at most a quarter of the jump
    /// times the entries' spacing: for the XF 35mm f/2's tables 10⁻⁵ of the
    /// radius (0.04 pixels at a 24-megapixel frame's corner) and 0.05% of the
    /// light, in a ring a thousandth of the radius wide.
    static let tableCount = 1024

    let tables: FujifilmRAF.LensTables
    /// The corrected picture's magnification about its center (`outputScale`).
    let scale: Double
    /// The largest radius a sample is taken from, at least 1: the gain table's reach.
    let sourceReach: Double
    /// Source radius over output radius, minus 1, for red, green and blue, at
    /// radii 0 … 1 of the output (scaled) picture in `tableCount` steps.
    let multiplierOffsets: [SIMD3<Double>]
    /// What a sample is multiplied by, minus 1, at source radii
    /// 0 … `sourceReach` in `tableCount` steps.
    let gainOffsets: [Double]

    /// - Parameter shortSideRadius: Half the frame's short side over half
    ///   its diagonal (0.555 for 3:2).
    init(_ tables: FujifilmRAF.LensTables, shortSideRadius: Double) {
        self.tables = tables
        let scale = Self.outputScale(tables, shortSideRadius: shortSideRadius)
        self.scale = scale
        let last = Double(Self.tableCount - 1)
        let multipliers = (0..<Self.tableCount).map {
            Self.multipliers(tables, destinationRadius: Double($0) / last / scale) / scale
        }
        multiplierOffsets = multipliers.map { $0 - 1 }
        let reach = max(1, multipliers.map { $0.max() }.max() ?? 1)
        sourceReach = reach
        gainOffsets = (0..<Self.tableCount).map { Self.gain(tables, sourceRadius: Double($0) / last * reach) - 1 }
    }

    // MARK: The camera's functions

    /// A table's value at `radius`: linear between knots, the first or last
    /// value outside them.
    static func value(_ values: [Double], knots: [Double], at radius: Double) -> Double {
        guard let first = knots.first, radius > first else { return values.first ?? 0 }
        for index in 1..<knots.count where radius <= knots[index] {
            let t = (radius - knots[index - 1]) / (knots[index] - knots[index - 1])
            return values[index - 1] + (values[index] - values[index - 1]) * t
        }
        return values.last ?? 0
    }

    /// 1 + distortion / 100 at a radius of the recorded image.
    static func distortionFactor(_ tables: FujifilmRAF.LensTables, sourceRadius: Double) -> Double {
        1 + value(tables.distortion, knots: tables.knots, at: sourceRadius) / 100
    }

    /// The radius of the recorded image that belongs at `destinationRadius`
    /// of the corrected one: the r with r / m(r) = ρ. Found by bisection (the
    /// left side grows with r for every table `isPlausible` lets through), to
    /// the last bit.
    static func sourceRadius(_ tables: FujifilmRAF.LensTables, destinationRadius: Double) -> Double {
        guard destinationRadius > 0 else { return 0 }
        var low = 0.0, high = destinationRadius * 2
        for _ in 0..<80 {
            let middle = (low + high) / 2
            if middle / distortionFactor(tables, sourceRadius: middle) < destinationRadius { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// Source radius over destination radius for red, green and blue.
    static func multipliers(_ tables: FujifilmRAF.LensTables, destinationRadius: Double) -> SIMD3<Double> {
        // At the center the ratio is its limit, m(0) (and the shifts' values there).
        let source = sourceRadius(tables, destinationRadius: destinationRadius)
        let green = destinationRadius > 0 ? source / destinationRadius : distortionFactor(tables, sourceRadius: 0)
        let red = green * (1 + value(tables.red, knots: tables.knots, at: source))
        let blue = green * (1 + value(tables.blue, knots: tables.knots, at: source))
        return SIMD3(red, green, blue)
    }

    /// The magnification that makes the corrected picture fill its frame from
    /// within the recorded one: the largest multiplier of any color at 200
    /// radii from the frame's short side to its corner, as darktable takes it.
    static func outputScale(_ tables: FujifilmRAF.LensTables, shortSideRadius: Double) -> Double {
        guard !tables.isIdentity else { return 1 }
        let start = min(max(shortSideRadius, 0), 1)
        return (0..<200).map { step in
            multipliers(tables, destinationRadius: start + (1 - start) * Double(step) / 199).max()
        }.max() ?? 1
    }

    /// Source radius over output radius for red, green and blue, at a radius
    /// of the scaled, corrected picture: what the lookup table holds.
    func multipliers(atOutputRadius radius: Double) -> SIMD3<Double> {
        Self.multipliers(tables, destinationRadius: radius / scale) / scale
    }

    /// What a sample taken at `sourceRadius` is multiplied by: the center's
    /// light over the light that reached that radius.
    static func gain(_ tables: FujifilmRAF.LensTables, sourceRadius: Double) -> Double {
        100 / value(tables.vignetting, knots: tables.knots, at: sourceRadius)
    }

    // MARK: The lookup tables

    /// The tables as the kernel reads them: `tableCount` wide, two rows of
    /// 32-bit floats. In Core Image's coordinates the lower row (y 0.5) holds
    /// the multipliers' offsets in red, green and blue, the upper one
    /// (y 1.5) the gain's offset in red. Offsets from 1, so that a context
    /// that keeps the table in half floats still has the multipliers to
    /// about 3 · 10⁻⁵ (a tenth of a pixel at a 24-megapixel frame's corner).
    /// Not color managed.
    var lookupImage: CIImage {
        var values = [Float](repeating: 0, count: Self.tableCount * 2 * 4)
        for index in 0..<Self.tableCount {
            // The bitmap's first row is the image's top one.
            values[index * 4] = Float(gainOffsets[index])
            values[index * 4 + 3] = 1
            let lower = (Self.tableCount + index) * 4
            values[lower] = Float(multiplierOffsets[index].x)
            values[lower + 1] = Float(multiplierOffsets[index].y)
            values[lower + 2] = Float(multiplierOffsets[index].z)
            values[lower + 3] = 1
        }
        return CIImage(bitmapData: values.withUnsafeBytes { Data($0) }, bytesPerRow: Self.tableCount * 16,
                       size: CGSize(width: Self.tableCount, height: 2), format: .RGBAf, colorSpace: nil)
    }

    // MARK: Applying

    /// The corrected frame: `frame` of `source` (in `source`'s coordinates,
    /// the camera's frame at the decode's scale; it may start between
    /// pixels), resampled, as an image of the frame's size at the origin.
    /// Samples beyond `source` repeat its edge. Nil when the kernel is not
    /// available (`LensKernels`).
    func apply(to source: CIImage, frame: CGRect) -> CIImage? {
        guard let kernel = try? LensKernels.kernel("embeddedLens"), !frame.isEmpty, !source.extent.isInfinite else { return nil }
        let output = CGRect(x: 0, y: 0, width: frame.width.rounded(), height: frame.height.rounded())
        let radius = hypot(frame.width, frame.height) / 2
        let last = Double(Self.tableCount - 1)
        let sourceCenter = CGPoint(x: frame.midX, y: frame.midY)
        let outputCenter = CGPoint(x: output.midX, y: output.midY)
        let offsets = multiplierOffsets.flatMap { [$0.x, $0.y, $0.z] }
        let lowest = 1 + (offsets.min() ?? 0), highest = 1 + (offsets.max() ?? 0)
        let table = lookupImage
        let tableExtent = table.extent
        return kernel.apply(extent: output, roiCallback: { index, rect in
            guard index == 0 else { return tableExtent }
            // The rectangle about the center, scaled by every multiplier in use, plus the interpolation's neighbors.
            let scaled = [lowest, highest].map { factor in
                CGRect(x: sourceCenter.x + (rect.minX - outputCenter.x) * factor,
                       y: sourceCenter.y + (rect.minY - outputCenter.y) * factor,
                       width: rect.width * factor, height: rect.height * factor)
            }
            return scaled[0].union(scaled[1]).insetBy(dx: -2, dy: -2)
        }, arguments: [source.clampedToExtent(), table, CIVector(cgPoint: sourceCenter), CIVector(cgPoint: outputCenter),
                       CIVector(x: last / radius, y: last / (radius * sourceReach), z: last)])?
            .cropped(to: output)
    }
}
