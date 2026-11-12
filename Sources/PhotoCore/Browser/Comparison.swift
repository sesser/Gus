import CoreGraphics
import Foundation

// Side by side comparison (docs/features/side-by-side-comparison): the loupe
// showing two photos. The rules live here, without AppKit, so they can be
// tested: which two photos a command compares, when it is refused, how a
// side walks through the source, and how linked panes follow each other.

/// A pane of the comparison, left to right. Panes are indexed (design §1),
/// so showing more of them later is a layout change, not a new model.
public enum ComparisonSide: Int, CaseIterable, Hashable, Sendable {
    case left = 0
    case right = 1

    /// The pane the switch key makes active next: it cycles.
    public var next: ComparisonSide {
        ComparisonSide(rawValue: (rawValue + 1) % Self.allCases.count) ?? .left
    }
}

/// The comparison the loupe shows: one version per pane and the active
/// pane. Version IDs, not images, so two versions of one master need no
/// change here (design §1).
public struct ComparisonState: Equatable, Sendable {
    public private(set) var left: Int64
    public private(set) var right: Int64
    public var active: ComparisonSide

    public init(left: Int64, right: Int64, active: ComparisonSide = .left) {
        self.left = left
        self.right = right
        self.active = active
    }

    public subscript(side: ComparisonSide) -> Int64 {
        get { side == .left ? left : right }
        set { if side == .left { left = newValue } else { right = newValue } }
    }

    /// The photo every command acts on: the loupe's focus follows it.
    public var activeVersionID: Int64 { self[active] }
    /// The photo on the pane that is not active.
    public var otherVersionID: Int64 { self[active.next] }
    /// Both photos, left then right: the selection while comparing and after leaving.
    public var versionIDs: [Int64] { [left, right] }

    public func side(of versionID: Int64) -> ComparisonSide? {
        ComparisonSide.allCases.first { self[$0] == versionID }
    }

    public mutating func switchActive() {
        active = active.next
    }
}

/// What the rules need to know of a photo in the source.
public struct ComparisonCandidate: Equatable, Sendable {
    public var versionID: Int64
    /// The other file of its RAW+JPEG pair, when it has one.
    public var partnerVersionID: Int64?
    public var isVideo: Bool
    public var isOffline: Bool

    public init(versionID: Int64, partnerVersionID: Int64? = nil, isVideo: Bool = false, isOffline: Bool = false) {
        self.versionID = versionID
        self.partnerVersionID = partnerVersionID
        self.isVideo = isVideo
        self.isOffline = isOffline
    }

    /// A still image whose original is online (design §3).
    public var canBeCompared: Bool { !isVideo && !isOffline }

    /// The RAW and the JPEG of one photo, shown as two items.
    public func isPairHalf(of other: ComparisonCandidate) -> Bool {
        partnerVersionID == other.versionID || other.partnerVersionID == versionID
    }

    /// Whether this photo can sit beside `other`: comparable, another photo,
    /// and not the other file of its pair (ruling RI-3).
    public func canSit(beside other: ComparisonCandidate) -> Bool {
        canBeCompared && versionID != other.versionID && !isPairHalf(of: other)
    }
}

/// Why choosing Compare Side by Side did not enter comparison (design §3).
/// The UI puts each into an alert's words.
public enum ComparisonRefusal: Equatable, Sendable {
    /// `alone`: comparison was asked for with this one photo (the loupe, the
    /// video loupe, one selected), not with two selected.
    case video(Int64, alone: Bool)
    case offline(Int64, alone: Bool)
    /// The two selected items are the files of one RAW+JPEG pair.
    case pairHalves(Int64, Int64)
    /// No other photo in the source can be compared with this one.
    case noPartner(Int64)

    /// The alert's title names what was asked: "Can’t Compare This Photo"
    /// when comparison was entered with one photo, "… These Photos" with
    /// two selected (design §16 D5).
    public var concernsOnePhoto: Bool {
        switch self {
        case .video(_, let alone), .offline(_, let alone): alone
        case .noPartner: true
        case .pairHalves: false
        }
    }
}

/// What Compare Side by Side does for a selection.
public enum ComparisonEntry: Equatable, Sendable {
    /// The wrong number of photos: the command is dimmed, nothing happens.
    case unavailable
    case enter(ComparisonState)
    case refused(ComparisonRefusal)
}

public enum ComparisonRules {
    /// The Compare toolbar item's symbol (design §4), and the link toggle's.
    public static let toolbarSymbolName = "rectangle.split.2x1"
    public static let linkSymbolName = "link"

    // MARK: Entering

    /// Whether Compare Side by Side / Stop Comparing is enabled. Dimmed only
    /// for counts, where there is nothing to explain (design §3, §4): the
    /// grid with one or two photos selected, the loupe or video loupe with
    /// two or more photos in the source, or while comparing; never during a
    /// crop session, which holds unsaved work.
    public static func canToggle(isComparing: Bool, isCropping: Bool, isLoupe: Bool, selectedCount: Int,
                                 itemCount: Int) -> Bool {
        if isCropping { return false }
        if isComparing { return true }
        guard itemCount >= 2 else { return false }
        return isLoupe || selectedCount == 1 || selectedCount == 2
    }

    /// Which two photos the command compares (design §3 "Which two photos",
    /// §16 D3).
    ///
    /// Two selected in the grid: those two in source order, the focused one
    /// active. One photo (the loupe, the video loupe, one selected): that
    /// photo on the left and its partner on the right, the partner active,
    /// so the arrows and the film strip choose the second photo at once.
    /// When the partner is the photo it was last compared with, that
    /// comparison comes back as it was left: the same photo on each side
    /// and the same active side.
    ///
    /// - Parameters:
    ///   - isLoupe: the loupe or the video loupe is showing `focus`.
    ///   - selection: the grid's selected indices.
    ///   - remembered: the comparison the photo was last in during this
    ///     loupe session, and where its other photo is in the source now.
    public static func entry(isLoupe: Bool, selection: [Int], focus: Int?, count: Int,
                             remembered: (state: ComparisonState, partnerIndex: Int)? = nil,
                             candidate: (Int) -> ComparisonCandidate) -> ComparisonEntry {
        guard count >= 2 else { return .unavailable }
        let selected = selection.filter { (0..<count).contains($0) }.sorted()
        if !isLoupe, selected.count == 2 {
            // Source order: the earlier one left, so the panes match the grid.
            let photos = selected.map(candidate)
            // The first reason that applies, for the first photo it applies to.
            for photo in photos {
                if photo.isVideo { return .refused(.video(photo.versionID, alone: false)) }
                if photo.isOffline { return .refused(.offline(photo.versionID, alone: false)) }
            }
            if photos[0].isPairHalf(of: photos[1]) {
                return .refused(.pairHalves(photos[0].versionID, photos[1].versionID))
            }
            // Active is the photo the keys acted on a moment ago.
            return .enter(ComparisonState(left: photos[0].versionID, right: photos[1].versionID,
                                          active: focus == selected[1] ? .right : .left))
        }
        let single: Int? = isLoupe ? focus : (selected.count == 1 ? selected[0] : nil)
        guard let index = single, (0..<count).contains(index) else { return .unavailable }
        let photo = candidate(index)
        if photo.isVideo { return .refused(.video(photo.versionID, alone: true)) }
        if photo.isOffline { return .refused(.offline(photo.versionID, alone: true)) }
        guard let partner = partner(of: index, count: count, remembered: remembered?.partnerIndex, candidate: candidate) else {
            return .refused(.noPartner(photo.versionID))
        }
        let other = candidate(partner).versionID
        // The same two as last time: as they were left, whichever side the photo was on.
        if let remembered, partner == remembered.partnerIndex,
           Set(remembered.state.versionIDs) == [photo.versionID, other] {
            return .enter(remembered.state)
        }
        return .enter(ComparisonState(left: photo.versionID, right: other, active: .right))
    }

    /// The photo compared with the one at `index` when only one is chosen:
    /// the one it was last compared with, if it still can be; otherwise the
    /// next photo in the source that can be compared; at the end of the
    /// source, the previous one.
    public static func partner(of index: Int, count: Int, remembered: Int? = nil,
                               candidate: (Int) -> ComparisonCandidate) -> Int? {
        guard (0..<count).contains(index) else { return nil }
        let photo = candidate(index)
        func fits(_ other: Int) -> Bool {
            other != index && (0..<count).contains(other) && candidate(other).canSit(beside: photo)
        }
        if let remembered, fits(remembered) { return remembered }
        if let next = ((index + 1)..<count).first(where: fits) { return next }
        return (0..<index).reversed().first(where: fits)
    }

    // MARK: Walking

    public enum Walk: Sendable {
        case previous, next, first, last
    }

    /// Where the arrows, Home and End take the active side (design §6):
    /// through the source as in the single loupe, skipping photos that can't
    /// be compared and the photo on the other side (and, by RI-3, the other
    /// file of its pair). Nil when the key does nothing.
    public static func walkTarget(_ walk: Walk, from index: Int, other: Int, count: Int,
                                  candidate: (Int) -> ComparisonCandidate) -> Int? {
        guard (0..<count).contains(index), (0..<count).contains(other) else { return nil }
        let beside = candidate(other)
        func fits(_ target: Int) -> Bool { target != other && candidate(target).canSit(beside: beside) }
        let target: Int? = switch walk {
        case .previous: (0..<index).reversed().first(where: fits)
        case .next: ((index + 1)..<count).first(where: fits)
        case .first: (0..<count).first(where: fits)
        case .last: (0..<count).reversed().first(where: fits)
        }
        return target == index ? nil : target
    }

    // MARK: Film strip

    /// What a click on a film strip cell does while comparing (design §7).
    public enum StripClick: Equatable, Sendable {
        /// The active photo's cell.
        case nothing
        /// The other side's cell: that side becomes active.
        case activate(ComparisonSide)
        /// Another photo: it goes into the active side.
        case replaceActive(Int)
        /// A video, an offline photo, or the other file of the other side's
        /// pair: nothing changes, and the system says "can't do that".
        case refuse
    }

    public static func stripClick(on index: Int, activeIndex: Int, otherIndex: Int, active: ComparisonSide,
                                  candidate: (Int) -> ComparisonCandidate) -> StripClick {
        if index == activeIndex { return .nothing }
        if index == otherIndex { return .activate(active.next) }
        return candidate(index).canSit(beside: candidate(otherIndex)) ? .replaceActive(index) : .refuse
    }

    // MARK: Reloads

    /// The comparison after the source's list was replaced (design §6 "When a
    /// compared photo goes away").
    public enum Reconciled: Equatable, Sendable {
        case kept(ComparisonState)
        /// A compared photo left the source: the loupe shows the one that
        /// remains alone, when one does.
        case ended(remaining: Int64?)
    }

    /// - Parameter pairPartner: for a compared photo that stood for a
    ///   grouped RAW+JPEG pair, the pair's other file. When the pair now
    ///   shows that file instead (RAW+JPEG Pair ▸ Show …, or its undo), the
    ///   side shows it: the photo is the same. Nothing else takes a missing
    ///   photo's place: not the photo a removal focuses next, which nobody
    ///   chose and which may not be comparable.
    public static func reconcile(_ state: ComparisonState, pairPartner: (Int64) -> Int64? = { _ in nil },
                                 isPresent: (Int64) -> Bool) -> Reconciled {
        var state = state
        for side in ComparisonSide.allCases where !isPresent(state[side]) {
            if let partner = pairPartner(state[side]), isPresent(partner), partner != state[side.next] {
                state[side] = partner
            }
        }
        let present = state.versionIDs.filter(isPresent)
        if present.count == 2 { return .kept(state) }
        return .ended(remaining: isPresent(state.activeVersionID) ? state.activeVersionID : present.first)
    }

    // MARK: Selection and targets

    /// The selection while comparing, and after leaving (ruling RI-1): the
    /// two photos, focus on the active one. Nil while either is not in the source.
    public static func selection(of state: ComparisonState, indexOf: (Int64) -> Int?) -> (selection: IndexSet, focus: Int)? {
        guard let left = indexOf(state.left), let right = indexOf(state.right) else { return nil }
        return (IndexSet([left, right]), state.active == .left ? left : right)
    }

    // MARK: Keys

    /// What Esc does while comparing: it backs out one level as in the
    /// loupe (design §1), review first, then the loupe. Comparison stays on
    /// through leaving review (design §4).
    public enum Escape: Equatable, Sendable {
        case exitReview
        case showGrid
    }

    public static func escape(isReviewing: Bool) -> Escape {
        isReviewing ? .exitReview : .showGrid
    }
}

/// Linked zoom and position (design §5): both panes show the same place at
/// the same scale. Positions are unit coordinates (fractions of the photo),
/// so same-size frames line up pixel for pixel and differently sized photos
/// stay on the same relative point.
public enum ComparisonLink {
    /// `UserDefaults`: linked when absent (the owner's default, PRD decision 4).
    public static let defaultsKey = "compare.linksViews"

    public static func isLinked(stored: Any?) -> Bool {
        stored as? Bool ?? true
    }

    /// A magnification within this factor of fit counts as fit.
    static let fitTolerance = 1.001

    /// The center of `visible` (the part of the document on screen) as
    /// fractions of the document, in the document's own coordinates.
    public static func unitCenter(visible: CGRect, document: CGSize) -> CGPoint {
        guard document.width > 0, document.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max(visible.midX / document.width, 0), 1), y: min(max(visible.midY / document.height, 0), 1))
    }

    /// Whether a pane counts as fitted for the pane that follows it. A
    /// pane a command zoomed in is not, even when its photo is so small
    /// that 100% is its fit (`isZoomedIn`); a pane at fit that a pinch is
    /// enlarging is not either, before the gesture has ended.
    public static func isFitted(isZoomedIn: Bool, magnification: Double, fit: Double) -> Bool {
        !isZoomedIn && magnification <= fit * fitTolerance
    }

    /// The magnification a pane takes to follow another at `leader`: its
    /// own fit when the leader is fitted, otherwise the same magnification,
    /// and at the low end each stops at its own fit.
    public static func magnification(following leader: Double, leaderIsFitted: Bool, followerFit: Double,
                                     maximum: Double = .infinity) -> Double {
        if leaderIsFitted { return followerFit }
        return min(max(leader, followerFit), max(maximum, followerFit))
    }

    /// The origin of the visible rect that puts `unit` in the middle of a
    /// pane showing `visible` document points of a `document`, clamped to
    /// the document; an axis on which the document is smaller than the pane
    /// is centered, as the loupe centers it.
    public static func visibleOrigin(centering unit: CGPoint, document: CGSize, visible: CGSize) -> CGPoint {
        func origin(_ unit: CGFloat, _ document: CGFloat, _ visible: CGFloat) -> CGFloat {
            guard visible < document else { return (document - visible) / 2 }
            return min(max(unit * document - visible / 2, 0), document - visible)
        }
        return CGPoint(x: origin(unit.x, document.width, visible.width),
                       y: origin(unit.y, document.height, visible.height))
    }
}

/// What a loupe canvas shows, from least to most detailed. A load only
/// replaces a lesser rendition, so a slow SDR preview never hides an HDR one.
/// Live frames of an edit in progress outrank them all (the single loupe
/// only: comparison never edits).
public enum LoupeRendition: Int, Comparable, Sendable {
    case placeholder, preview, hdrPreview, full, hdrFull, live

    public static func < (lhs: LoupeRendition, rhs: LoupeRendition) -> Bool { lhs.rawValue < rhs.rawValue }

    public var isHDR: Bool { self == .hdrPreview || self == .hdrFull }
    /// The photo's own pixels: one image pixel per photo pixel.
    public var isFullResolution: Bool { self == .full || self == .hdrFull }
}

/// The comparison's fixed measurements (design §2, §6).
public enum ComparisonGeometry {
    /// Round every pane's canvas, active or not, so making a pane active moves nothing.
    public static let gutter = 4.0
    /// The canvas's corner radius; the ring's outer radius is this plus the gutter.
    public static let canvasCornerRadius = 4.0
    /// Entering, leaving and relinking (the loupe's fit animation).
    public static let animationDuration = 0.15

    /// The canvases of `count` equal columns across `size`, left to right,
    /// each inset by the gutter.
    public static func canvases(in size: CGSize, count: Int = ComparisonSide.allCases.count) -> [CGRect] {
        guard count > 0 else { return [] }
        let width = size.width / CGFloat(count)
        return (0..<count).map { index in
            CGRect(x: CGFloat(index) * width, y: 0, width: width, height: size.height)
                .insetBy(dx: gutter, dy: gutter)
        }
    }

    /// The canvas of the pane that fills the loupe at `progress` 0 (the
    /// single loupe's canvas, with no gutter) and sits in its column at 1.
    public static func canvas(of side: ComparisonSide, in size: CGSize, progress: Double) -> CGRect {
        let settled = canvases(in: size)[side.rawValue]
        let whole = CGRect(origin: .zero, size: size)
        let t = CGFloat(min(max(progress, 0), 1))
        return CGRect(x: whole.minX + (settled.minX - whole.minX) * t, y: whole.minY + (settled.minY - whole.minY) * t,
                      width: whole.width + (settled.width - whole.width) * t,
                      height: whole.height + (settled.height - whole.height) * t)
    }

    /// The active pane's ring: a rounded rectangle in its gutter, `width`
    /// wide, its outer edge on the gutter's (so its outer radius is the
    /// canvas's plus the gutter, concentric with the canvas). Returns the
    /// rectangle and radius of the line's center.
    public static func ring(around canvas: CGRect, width: Double) -> (rect: CGRect, cornerRadius: Double) {
        let inset = CGFloat(width / 2 - gutter)
        return (canvas.insetBy(dx: inset, dy: inset), canvasCornerRadius + gutter - width / 2)
    }
}
