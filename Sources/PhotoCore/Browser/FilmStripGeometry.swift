import Foundation

/// The loupe's film strip as numbers (section 11 of docs/UI_REDESIGN.md):
/// the thumbnail steps and snapping to them, the step shown under the
/// height cap, the strip's height, where each cell sits, the scroll offset
/// that centers a photo, which cells are visible, and whether a move
/// animates.
///
/// Offsets are the clip view's origin in the strip's document, which holds
/// an inset of `(visible width − cell) / 2` at both ends so the first and
/// the last photo can reach the center.
public struct FilmStripGeometry: Equatable, Sendable {
    /// The thumbnail sizes the strip settles on, in points, smallest first.
    public static let steps: [Double] = [48, 64, 80, 96, 120]
    public static let defaultSize: Double = 120
    /// Above and below the cells.
    public static let verticalPadding: Double = 8
    /// Between cells.
    public static let spacing: Double = 4
    /// Around the image inside a cell.
    public static let imagePadding: Double = 3
    /// The strip never takes more of the loupe's height than this.
    public static let heightShare: Double = 0.25
    /// The recentering scroll, in seconds.
    public static let animationDuration: Double = 0.2
    /// Showing and hiding the strip; settling on a step after a resize.
    public static let showDuration: Double = 0.25
    public static let hideDuration: Double = 0.2
    public static let settleDuration: Double = 0.15

    public static var smallestStep: Double { steps[0] }
    public static var largestStep: Double { steps[steps.count - 1] }

    /// The cell edge shown: a step, or a height between steps while the
    /// handle is dragged.
    public let cellSize: Double

    public init(cellSize: Double) {
        self.cellSize = cellSize
    }

    /// The step shown for the stored step and the loupe's whole height
    /// (canvas, strip and caption).
    public init(storedSize: Double, loupeHeight: Double) {
        self.init(cellSize: Self.shownStep(stored: storedSize, loupeHeight: loupeHeight))
    }

    /// The step nearest `size` (ties go to the larger step; sizes outside
    /// the steps go to the nearer end).
    public static func nearestStep(_ size: Double) -> Double {
        guard size.isFinite else { return defaultSize }
        var best = steps[0]
        for step in steps where abs(step - size) <= abs(best - size) {
            best = step
        }
        return best
    }

    /// A stored size as read from user defaults: the default when absent,
    /// otherwise the nearest step (sizes from the slider build included).
    public static func validatedSize(_ stored: Double?) -> Double {
        guard let stored, stored.isFinite else { return defaultSize }
        return nearestStep(stored)
    }

    /// The strip's height for a cell size.
    public static func stripHeight(cellSize: Double) -> Double {
        cellSize + verticalPadding * 2
    }

    /// The largest step whose strip takes at most a quarter of the loupe;
    /// the smallest step when none does.
    public static func largestFittingStep(loupeHeight: Double) -> Double {
        let limit = heightShare * loupeHeight
        return steps.last { stripHeight(cellSize: $0) <= limit } ?? smallestStep
    }

    /// The stored step, or the largest step that fits under the cap.
    public static func shownStep(stored: Double, loupeHeight: Double) -> Double {
        min(validatedSize(stored), largestFittingStep(loupeHeight: loupeHeight))
    }

    /// The strip heights a resize drag moves between.
    public static func dragHeights(loupeHeight: Double) -> ClosedRange<Double> {
        stripHeight(cellSize: smallestStep)...stripHeight(cellSize: largestFittingStep(loupeHeight: loupeHeight))
    }

    /// The step a drag settles on for the strip's height at release.
    public static func settledStep(stripHeight height: Double, loupeHeight: Double) -> Double {
        min(nearestStep(height - verticalPadding * 2), largestFittingStep(loupeHeight: loupeHeight))
    }

    /// The step to store after a release settled on `settled`: that step,
    /// except when it is the largest that fits under the cap and the stored
    /// step is larger, which is kept so the strip grows back with the window.
    public static func storedStep(afterSettlingOn settled: Double, stored: Double, loupeHeight: Double) -> Double {
        let stored = validatedSize(stored)
        if settled == largestFittingStep(loupeHeight: loupeHeight), stored > settled { return stored }
        return settled
    }

    /// One step larger (`up`) or smaller than `step` among those that fit,
    /// or nil at the end.
    public static func step(after step: Double, up: Bool, loupeHeight: Double) -> Double? {
        let fitting = steps.filter { $0 <= largestFittingStep(loupeHeight: loupeHeight) }
        return up ? fitting.first { $0 > step } : fitting.last { $0 < step }
    }

    /// The thumbnails' decode size: the largest step's, whatever the step,
    /// so resizing only rescales images already loaded.
    public static func thumbnailPixelSize(backingScale: Double) -> Int {
        Int(largestStep * backingScale)
    }

    public var stripHeight: Double { cellSize + Self.verticalPadding * 2 }

    /// From one cell's leading edge to the next.
    public var pitch: Double { cellSize + Self.spacing }

    /// The inset at each end that lets the first and last cell reach the
    /// center; none when the strip is narrower than a cell.
    public func endInset(visibleWidth: Double) -> Double {
        max(0, (visibleWidth - cellSize) / 2)
    }

    /// The document's width.
    public func contentWidth(count: Int, visibleWidth: Double) -> Double {
        let cells = count > 0 ? Double(count) * pitch - Self.spacing : 0
        return max(visibleWidth, endInset(visibleWidth: visibleWidth) * 2 + cells)
    }

    /// The leading edge of cell `index` in the document.
    public func cellOrigin(_ index: Int, visibleWidth: Double) -> Double {
        endInset(visibleWidth: visibleWidth) + Double(index) * pitch
    }

    /// The largest offset the document allows.
    public func maximumOffset(count: Int, visibleWidth: Double) -> Double {
        max(0, contentWidth(count: count, visibleWidth: visibleWidth) - visibleWidth)
    }

    /// `offset` kept within the document.
    public func clampedOffset(_ offset: Double, count: Int, visibleWidth: Double) -> Double {
        min(max(offset, 0), maximumOffset(count: count, visibleWidth: visibleWidth))
    }

    /// The offset that puts cell `index` in the middle of the visible width:
    /// `index × pitch` whenever the strip is at least a cell wide.
    public func centeringOffset(for index: Int, count: Int, visibleWidth: Double) -> Double {
        guard count > 0 else { return 0 }
        let index = min(max(index, 0), count - 1)
        let center = cellOrigin(index, visibleWidth: visibleWidth) + cellSize / 2 - visibleWidth / 2
        return clampedOffset(center, count: count, visibleWidth: visibleWidth)
    }

    /// The cell whose center is nearest the middle of the visible width.
    public func centeredIndex(offset: Double, count: Int, visibleWidth: Double) -> Int? {
        guard count > 0 else { return nil }
        let middle = offset + visibleWidth / 2 - endInset(visibleWidth: visibleWidth) - cellSize / 2
        return min(max(Int((middle / pitch).rounded()), 0), count - 1)
    }

    /// Indices of the cells that intersect the visible width at `offset`.
    public func visibleRange(offset: Double, visibleWidth: Double, count: Int) -> Range<Int> {
        guard visibleWidth > 0 else { return 0..<0 }
        return cells(from: offset, to: offset + visibleWidth, visibleWidth: visibleWidth, count: count)
    }

    /// Indices of the cells that intersect the document from `minX` to
    /// `maxX` (the layout's rectangles, which can be wider than the strip).
    public func cells(from minX: Double, to maxX: Double, visibleWidth: Double, count: Int) -> Range<Int> {
        guard count > 0, maxX > minX else { return 0..<0 }
        let inset = endInset(visibleWidth: visibleWidth)
        let start = minX - inset
        let end = maxX - inset
        // A cell is visible when its leading edge is before `end` and its
        // trailing edge after `start`.
        let first = max(0, Int(floor((start - cellSize) / pitch)) + 1)
        let last = min(count - 1, Int(ceil(end / pitch)) - 1)
        guard first <= last else { return 0..<0 }
        return first..<(last + 1)
    }

    /// A focus change scrolls with an animation only when the target is
    /// within one visible width (further, an animation would stream the
    /// thumbnails it passes), the key is not repeating (the strip keeps up
    /// with a held arrow), and Reduce Motion is off.
    public static func animatesMove(from current: Double, to target: Double, visibleWidth: Double,
                                    isKeyRepeat: Bool, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, !isKeyRepeat, current != target else { return false }
        return abs(target - current) <= visibleWidth
    }

    /// The show / hide toggle's symbol: the bottom-panel member of the
    /// panel-toggle family (`sidebar.leading`, `sidebar.trailing`).
    public static let toggleSymbolName = "rectangle.bottomthird.inset.filled"
}
