import CoreGraphics
import Foundation

/// A photo pixel, in the orientation the view shows (`PixelMagnifierImage`).
public struct PixelPosition: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// The pixel magnifier's zoom (docs/features/chromatic-aberration/design.md
/// §20): device pixels per photo pixel × 100, the view's own meaning of a
/// percentage. One preference on this Mac, shared by every tool.
public enum PixelMagnifierLevel: Int, CaseIterable, Sendable {
    case percent100 = 100, percent200 = 200, percent400 = 400, percent800 = 800, percent1600 = 1600

    public static let standard = PixelMagnifierLevel.percent800
    /// The `UserDefaults` key of the preference.
    public static let defaultsKey = "pixelMagnifier.level"

    /// A stored value; anything unknown reads as the starting level.
    public init(stored: Int) {
        self = PixelMagnifierLevel(rawValue: stored) ?? .standard
    }

    /// Device pixels per photo pixel, on any display.
    public var cellSize: Int { rawValue / 100 }

    /// A one-device-pixel line would cover too much of a smaller cell.
    public var showsGrid: Bool { rawValue >= 800 }

    /// The next level up (or down), nil at the end of the list: no wrap.
    public func stepped(up: Bool) -> PixelMagnifierLevel? {
        let levels = Self.allCases
        guard let index = levels.firstIndex(of: self) else { return nil }
        let next = up ? index + 1 : index - 1
        return levels.indices.contains(next) ? levels[next] : nil
    }
}

/// The pixels a tool samples, in the orientation the view shows.
public protocol PixelMagnifierImage: Sendable {
    var width: Int { get }
    var height: Int { get }
    /// The pixel's linear Rec. 2020 color (the working space); nil beyond
    /// the photo or its crop, which the magnifier leaves empty.
    func color(x: Int, y: Int) -> SIMD3<Double>?
}

/// What a tool says of the pixel a click would pick.
public enum PixelMagnifierVerdict: Equatable, Sendable {
    case fine
    /// A click there would be refused; the short state to show.
    case refused(String)
}

/// A tool that uses the magnifier (design §20 "Built to be reused"). The
/// magnifier knows nothing else about the tool: the image, the rule for which
/// pixel a click picks, a verdict on that pixel and an optional note.
public protocol PixelMagnifierTool: Sendable {
    var image: any PixelMagnifierImage { get }
    /// The note under the values ("Before edits"), or none.
    var note: String? { get }
    /// Photo pixels across the view's output.
    var outputPixelWidth: Double { get }
    /// `output` (the view's output in unit coordinates, y down) as a position
    /// in the image: photo pixels, continuous.
    func position(forOutput output: CGPoint) -> SIMD2<Double>
    /// The pixel a click at `position` (photo pixels, continuous, in the
    /// image's orientation) would pick; `photoPixelsPerDevicePixel` is the
    /// view's scale. Nil if none.
    func pickedPixel(at position: SIMD2<Double>, photoPixelsPerDevicePixel: Double) -> PixelPosition?
    func verdict(at pixel: PixelPosition) -> PixelMagnifierVerdict
}

/// A pixel's values for reading: integers 0 … 255 in Display P3 with its
/// usual tone curve; L is the Rec. 2020 luminance on the same curve.
public struct PixelMagnifierValues: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int
    public var l: Int

    public init(r: Int, g: Int, b: Int, l: Int) {
        self.r = r
        self.g = g
        self.b = b
        self.l = l
    }

    /// Linear Rec. 2020 to linear Display P3, each row normalized to sum to
    /// exactly 1 and used relative to green, so a neutral stays exactly
    /// neutral and reads R = G = B = L.
    private static let toP3: (red: SIMD2<Double>, green: SIMD2<Double>, blue: SIMD2<Double>) = {
        let rec2020ToXYZ: [[Double]] = [
            [0.636_958_048_301_291, 0.144_616_903_586_208, 0.168_880_975_164_172],
            [0.262_700_212_011_267, 0.677_998_071_518_871, 0.059_301_716_469_862],
            [0.000_000_000_000_000, 0.028_072_693_049_087, 1.060_985_057_710_791],
        ]
        let p3ToXYZ: [[Double]] = [
            [0.486_570_948_648_216, 0.265_667_693_169_093, 0.198_217_285_234_363],
            [0.228_974_564_069_749, 0.691_738_521_836_506, 0.079_286_914_093_745],
            [0.000_000_000_000_000, 0.045_113_381_858_903, 1.043_944_368_900_976],
        ]
        let xyzToP3 = Matrix3.inverse(p3ToXYZ)
        var rows: [SIMD2<Double>] = []
        for row in 0..<3 {
            var cells = [0.0, 0.0, 0.0]
            for column in 0..<3 {
                for k in 0..<3 { cells[column] += xyzToP3[row][k] * rec2020ToXYZ[k][column] }
            }
            let total = cells[0] + cells[1] + cells[2]
            rows.append(SIMD2(cells[0] / total, cells[2] / total))
        }
        return (rows[0], rows[1], rows[2])
    }()

    public init(linearRec2020 color: SIMD3<Double>) {
        let g = color.y
        let dr = color.x - g, db = color.z - g
        let matrix = Self.toP3
        r = Self.encode(g + matrix.red.x * dr + matrix.red.y * db)
        self.g = Self.encode(g + matrix.green.x * dr + matrix.green.y * db)
        b = Self.encode(g + matrix.blue.x * dr + matrix.blue.y * db)
        l = Self.encode(g + 0.2627 * dr + 0.0593 * db)
    }

    /// The sRGB curve (Display P3's), as an integer; beyond the range reads 0 or 255.
    static func encode(_ linear: Double) -> Int {
        guard linear.isFinite else { return linear > 0 ? 255 : 0 }
        let c = min(max(linear, 0), 1)
        let encoded = c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return Int((encoded * 255).rounded())
    }
}

/// The magnifier's fixed size in points, on every display (design §20).
public enum PixelMagnifierLayout {
    public static let pictureDiameter = 128.0
    public static let ringDiameter = 136.0
    public static let plateGap = 4.0
    public static let plateHeight = 36.0
    public static var compositeSize: CGSize { CGSize(width: ringDiameter, height: ringDiameter + plateGap + plateHeight) }
    /// From the pointer's hot spot to the composite's nearest corner, on each axis.
    public static let pointerGap = 20.0
    public static let edgeInset = 8.0
    /// The preferred side must fit with this much to spare before it comes back.
    public static let returnMargin = 24.0
}

/// Where the composite sits (design §20 "Where it sits"), in the canvas's
/// points, y down.
public struct PixelMagnifierPlacement: Equatable, Sendable {
    public var isLeftOfPointer = false
    public var isAbovePointer = false
    public var origin = CGPoint.zero

    public init(isLeftOfPointer: Bool = false, isAbovePointer: Bool = false, origin: CGPoint = .zero) {
        self.isLeftOfPointer = isLeftOfPointer
        self.isAbovePointer = isAbovePointer
        self.origin = origin
    }

    /// The placement for `pointer` given the last one: below and to the right
    /// unless that leaves the canvas; a flipped side returns only with
    /// `returnMargin` to spare, so it can't flicker; clamped into the canvas
    /// when neither side fits.
    public static func place(pointer: CGPoint, canvas: CGSize, previous: PixelMagnifierPlacement?) -> PixelMagnifierPlacement {
        let size = PixelMagnifierLayout.compositeSize
        let isLeft = flips(pointer: Double(pointer.x), extent: Double(size.width), canvas: Double(canvas.width),
                           wasFlipped: previous?.isLeftOfPointer ?? false)
        let isAbove = flips(pointer: Double(pointer.y), extent: Double(size.height), canvas: Double(canvas.height),
                            wasFlipped: previous?.isAbovePointer ?? false)
        let x = origin(pointer: Double(pointer.x), extent: Double(size.width), canvas: Double(canvas.width), flipped: isLeft)
        let y = origin(pointer: Double(pointer.y), extent: Double(size.height), canvas: Double(canvas.height), flipped: isAbove)
        return PixelMagnifierPlacement(isLeftOfPointer: isLeft, isAbovePointer: isAbove, origin: CGPoint(x: x, y: y))
    }

    private static func flips(pointer: Double, extent: Double, canvas: Double, wasFlipped: Bool) -> Bool {
        let gap = PixelMagnifierLayout.pointerGap
        let inset = PixelMagnifierLayout.edgeInset
        let preferredEnd = pointer + gap + extent
        if wasFlipped { return preferredEnd + PixelMagnifierLayout.returnMargin > canvas - inset }
        return preferredEnd > canvas - inset
    }

    private static func origin(pointer: Double, extent: Double, canvas: Double, flipped: Bool) -> Double {
        let gap = PixelMagnifierLayout.pointerGap
        let inset = PixelMagnifierLayout.edgeInset
        let wanted = flipped ? pointer - gap - extent : pointer + gap
        let low = inset, high = canvas - inset - extent
        guard high >= low else { return max((canvas - extent) / 2, 0) }
        return min(max(wanted, low), high)
    }
}

/// What the magnifier shows for a pointer position (R20–R26).
public enum PixelMagnifier {
    /// The outlined pixel and what the plate says about it.
    public struct Reading: Equatable, Sendable {
        public var pixel: PixelPosition
        public var values: PixelMagnifierValues
        public var verdict: PixelMagnifierVerdict
        public var note: String?
    }

    /// The reading at `position`: the pixel the tool's rule picks, which is
    /// what a click there takes. Nil if the rule finds none.
    public static func reading(tool: any PixelMagnifierTool, at position: SIMD2<Double>,
                               photoPixelsPerDevicePixel: Double) -> Reading? {
        guard let pixel = tool.pickedPixel(at: position, photoPixelsPerDevicePixel: photoPixelsPerDevicePixel),
              let color = tool.image.color(x: pixel.x, y: pixel.y) else { return nil }
        return Reading(pixel: pixel, values: PixelMagnifierValues(linearRec2020: color),
                       verdict: tool.verdict(at: pixel), note: tool.note)
    }

    /// The reading for a pointer at `output` (output unit coordinates, the
    /// middle of its device pixel), the output being `devicePixelsAcross` wide on screen.
    public static func reading(tool: any PixelMagnifierTool, atOutput output: CGPoint,
                               devicePixelsAcross: Double) -> Reading? {
        let scale = tool.outputPixelWidth / max(devicePixelsAcross, 1)
        return reading(tool: tool, at: tool.position(forOutput: output), photoPixelsPerDevicePixel: scale)
    }

    /// One line of the grid over the picture, in device pixels: from the top
    /// left of the first cell's edge, a device pixel wide.
    public struct GridLine: Equatable, Sendable {
        public var x0: Int
        public var y0: Int
        public var x1: Int
        public var y1: Int
    }

    /// The square of pixels the picture shows, centered on one pixel: hard
    /// cells `cellSize` device pixels wide. Cells beyond the photo or its
    /// crop are nil.
    public struct Picture: Equatable, Sendable {
        public var center: PixelPosition
        /// Across the picture, in device pixels.
        public var deviceSize: Int
        public var cellSize: Int
        /// Cells across (odd, so one is the middle), covering the picture.
        public var cellsAcross: Int
        /// `cellsAcross²` cells, top row first.
        public var cells: [PixelMagnifierValues?]

        /// Device position of cell `index`'s left (or top) edge: the middle
        /// cell is centered, whole device pixels.
        func deviceOrigin(ofCell index: Int) -> Int {
            (deviceSize - cellSize) / 2 + (index - cellsAcross / 2) * cellSize
        }

        /// The picture as RGBA, 8 bits, Display P3, `deviceSize` square: each
        /// cell one flat color, `surround` beyond the photo or crop, and a
        /// 50 % gray device-pixel hairline on the surround side of the edge.
        public func bitmap(surround: (r: UInt8, g: UInt8, b: UInt8)) -> [UInt8] {
            var rgba = [UInt8](repeating: 255, count: deviceSize * deviceSize * 4)
            for i in stride(from: 0, to: rgba.count, by: 4) {
                rgba[i] = surround.r
                rgba[i + 1] = surround.g
                rgba[i + 2] = surround.b
            }
            let hairline = (r: Self.halfGray(surround.r), g: Self.halfGray(surround.g), b: Self.halfGray(surround.b))
            for row in 0..<cellsAcross {
                for column in 0..<cellsAcross {
                    let x0 = deviceOrigin(ofCell: column), y0 = deviceOrigin(ofCell: row)
                    guard let value = cells[row * cellsAcross + column] else {
                        paintHairline(&rgba, column: column, row: row, x0: x0, y0: y0, color: hairline)
                        continue
                    }
                    fill(&rgba, x0: x0, y0: y0, width: cellSize, height: cellSize, color: (UInt8(value.r), UInt8(value.g), UInt8(value.b)))
                }
            }
            return rgba
        }

        /// The grid between cells that hold a photo pixel, none over the
        /// empty area beyond the photo or crop: along each drawn cell's top
        /// and left edge, joined into runs and clipped to the picture.
        public func gridLines() -> [GridLine] {
            var lines: [GridLine] = []
            for row in 0..<cellsAcross {
                let y = deviceOrigin(ofCell: row)
                guard y >= 0, y < deviceSize else { continue }
                appendRuns(to: &lines) { cell in isDrawn(column: cell, row: row) } line: { first, end in
                    GridLine(x0: max(first, 0), y0: y, x1: min(end, deviceSize), y1: y)
                }
            }
            for column in 0..<cellsAcross {
                let x = deviceOrigin(ofCell: column)
                guard x >= 0, x < deviceSize else { continue }
                appendRuns(to: &lines) { cell in isDrawn(column: column, row: cell) } line: { first, end in
                    GridLine(x0: x, y0: max(first, 0), x1: x, y1: min(end, deviceSize))
                }
            }
            return lines
        }

        private func appendRuns(to lines: inout [GridLine], isDrawn: (Int) -> Bool, line: (Int, Int) -> GridLine) {
            var start: Int?
            for cell in 0...cellsAcross {
                if cell < cellsAcross, isDrawn(cell) {
                    if start == nil { start = cell }
                } else if let first = start {
                    lines.append(line(deviceOrigin(ofCell: first), deviceOrigin(ofCell: cell - 1) + cellSize))
                    start = nil
                }
            }
        }

        private static func halfGray(_ value: UInt8) -> UInt8 {
            UInt8((Int(value) + 128) / 2)
        }

        private func isDrawn(column: Int, row: Int) -> Bool {
            guard (0..<cellsAcross).contains(column), (0..<cellsAcross).contains(row) else { return false }
            return cells[row * cellsAcross + column] != nil
        }

        private func paintHairline(_ rgba: inout [UInt8], column: Int, row: Int, x0: Int, y0: Int,
                                   color: (r: UInt8, g: UInt8, b: UInt8)) {
            let tone = (color.r, color.g, color.b)
            if isDrawn(column: column + 1, row: row) { fill(&rgba, x0: x0 + cellSize - 1, y0: y0, width: 1, height: cellSize, color: tone) }
            if isDrawn(column: column - 1, row: row) { fill(&rgba, x0: x0, y0: y0, width: 1, height: cellSize, color: tone) }
            if isDrawn(column: column, row: row + 1) { fill(&rgba, x0: x0, y0: y0 + cellSize - 1, width: cellSize, height: 1, color: tone) }
            if isDrawn(column: column, row: row - 1) { fill(&rgba, x0: x0, y0: y0, width: cellSize, height: 1, color: tone) }
        }

        private func fill(_ rgba: inout [UInt8], x0: Int, y0: Int, width: Int, height: Int, color: (UInt8, UInt8, UInt8)) {
            let left = max(x0, 0), right = min(x0 + width, deviceSize)
            let top = max(y0, 0), bottom = min(y0 + height, deviceSize)
            guard right > left, bottom > top else { return }
            for y in top..<bottom {
                for x in left..<right {
                    let i = (y * deviceSize + x) * 4
                    rgba[i] = color.0
                    rgba[i + 1] = color.1
                    rgba[i + 2] = color.2
                }
            }
        }
    }

    /// The picture around `center` at `level`, `deviceSize` device pixels across.
    public static func picture(image: any PixelMagnifierImage, center: PixelPosition, level: PixelMagnifierLevel,
                               deviceSize: Int) -> Picture {
        let cellSize = level.cellSize
        var across = deviceSize / cellSize + 2
        if across.isMultiple(of: 2) { across += 1 }
        let middle = across / 2
        var cells = [PixelMagnifierValues?](repeating: nil, count: across * across)
        for row in 0..<across {
            for column in 0..<across {
                if let color = image.color(x: center.x + column - middle, y: center.y + row - middle) {
                    cells[row * across + column] = PixelMagnifierValues(linearRec2020: color)
                }
            }
        }
        return Picture(center: center, deviceSize: deviceSize, cellSize: cellSize, cellsAcross: across, cells: cells)
    }
}
