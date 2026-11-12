import AppKit
import Foundation
import Testing
@testable import PhotoCore

/// The rules of side by side comparison (docs/features/side-by-side-comparison):
/// one suite per acceptance criterion's rule, named for it.
@Suite("Comparison")
struct ComparisonTests {
    /// A source of plain photos with version IDs 100, 101, …; `change` edits them.
    static func source(_ count: Int, _ change: (inout [ComparisonCandidate]) -> Void = { _ in }) -> [ComparisonCandidate] {
        var photos = (0..<count).map { ComparisonCandidate(versionID: Int64(100 + $0)) }
        change(&photos)
        return photos
    }

    /// `remembered`: the comparison the photo was last in; its other photo's
    /// index is looked up in `photos`, as the app does.
    static func entry(_ photos: [ComparisonCandidate], isLoupe: Bool = false, selection: [Int], focus: Int?,
                      remembered: ComparisonState? = nil) -> ComparisonEntry {
        let photo = focus.flatMap { photos.indices.contains($0) ? photos[$0].versionID : nil }
        let memory = remembered.flatMap { state -> (state: ComparisonState, partnerIndex: Int)? in
            guard let photo, let side = state.side(of: photo),
                  let partner = photos.firstIndex(where: { $0.versionID == state[side.next] }) else { return nil }
            return (state, partner)
        }
        return ComparisonRules.entry(isLoupe: isLoupe, selection: selection, focus: focus, count: photos.count,
                                     remembered: memory) { photos[$0] }
    }

    // MARK: AC1, R2: which two photos

    @Test func twoSelectedPhotosAreComparedInSourceOrder() {
        let photos = Self.source(6)
        // Selected in either order: the earlier one is left, so the panes match the grid.
        #expect(Self.entry(photos, selection: [4, 1], focus: 1) == .enter(ComparisonState(left: 101, right: 104, active: .left)))
        #expect(Self.entry(photos, selection: [1, 4], focus: 4) == .enter(ComparisonState(left: 101, right: 104, active: .right)))
    }

    @Test func activeIsTheLeftPhotoWhenFocusIsNeither() {
        let photos = Self.source(6)
        #expect(Self.entry(photos, selection: [1, 4], focus: 5) == .enter(ComparisonState(left: 101, right: 104, active: .left)))
        #expect(Self.entry(photos, selection: [1, 4], focus: nil) == .enter(ComparisonState(left: 101, right: 104, active: .left)))
    }

    /// Design §16 D3 and AC6b: with one photo, the photo beside it is the
    /// active one, so the arrows and the film strip choose the second photo.
    @Test func oneSelectedPhotoIsComparedWithTheNextWhichIsActive() {
        let photos = Self.source(6)
        #expect(Self.entry(photos, selection: [2], focus: 2) == .enter(ComparisonState(left: 102, right: 103, active: .right)))
    }

    @Test func theLoupesPhotoIsComparedWithItsPartnerWhateverIsSelected() {
        let photos = Self.source(6)
        // The loupe: the photo on screen stays on the left and the partner is
        // active; the grid's selection does not count.
        #expect(Self.entry(photos, isLoupe: true, selection: [0, 5], focus: 3)
            == .enter(ComparisonState(left: 103, right: 104, active: .right)))
    }

    @Test func thePartnerIsThePreviousPhotoAtTheEndOfTheSource() {
        let photos = Self.source(6)
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 5)
            == .enter(ComparisonState(left: 105, right: 104, active: .right)))
    }

    @Test func thePartnerIsThePhotoLastComparedWith() {
        let photos = Self.source(6)
        // S, then S again: the same pair comes back, not the next photo.
        let last = ComparisonState(left: 101, right: 104, active: .right)
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 1, remembered: last) == .enter(last))
        // A remembered photo that can no longer be compared is passed over.
        let offline = Self.source(6) { $0[4].isOffline = true }
        #expect(Self.entry(offline, isLoupe: true, selection: [], focus: 1, remembered: last)
            == .enter(ComparisonState(left: 101, right: 102, active: .right)))
        // So is one that left the source.
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 1,
                           remembered: ComparisonState(left: 101, right: 999, active: .left))
            == .enter(ComparisonState(left: 101, right: 102, active: .right)))
        // Never the photo itself.
        #expect(ComparisonRules.partner(of: 1, count: 6, remembered: 1) { photos[$0] } == 2)
    }

    /// AC6c and design §16 D3: `S`, `S` brings the comparison back as it was
    /// left, whichever side the loupe's photo is on and whichever is active.
    @Test func aRememberedPairComesBackOnTheSameSidesWithTheSameOneActive() {
        let photos = Self.source(6)
        // Left with the right photo active: the loupe shows 104, the right one.
        let leftOnTheRight = ComparisonState(left: 101, right: 104, active: .right)
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 4, remembered: leftOnTheRight) == .enter(leftOnTheRight))
        // Left with the left photo active after `A`: back with the left active.
        let leftOnTheLeft = ComparisonState(left: 101, right: 104, active: .left)
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 1, remembered: leftOnTheLeft) == .enter(leftOnTheLeft))
        // From the grid nothing is remembered: the loupe's session is over.
        #expect(Self.entry(photos, selection: [4], focus: 4) == .enter(ComparisonState(left: 104, right: 105, active: .right)))
    }

    @Test func thePartnerSkipsWhatCannotBeCompared() {
        let photos = Self.source(6) {
            $0[3].isVideo = true
            $0[4].isOffline = true
        }
        #expect(ComparisonRules.partner(of: 2, count: 6) { photos[$0] } == 5)
        // Nothing after it: the nearest one before.
        let tail = Self.source(4) {
            $0[2].isVideo = true
            $0[3].isVideo = true
        }
        #expect(ComparisonRules.partner(of: 1, count: 4) { tail[$0] } == 0)
    }

    @Test func thePartnerIsNeverTheOtherFileOfThePair() {
        // Pairs shown as two items: 1 and 2 are the RAW and JPEG of one photo.
        let photos = Self.source(4) {
            $0[1].partnerVersionID = 102
            $0[2].partnerVersionID = 101
        }
        #expect(ComparisonRules.partner(of: 1, count: 4) { photos[$0] } == 3)
        #expect(ComparisonRules.partner(of: 2, count: 4) { photos[$0] } == 3)
    }

    // MARK: Enabled by counts (design §3, §4)

    @Test func theCommandIsDimmedOnlyForCounts() {
        func can(loupe: Bool = false, selected: Int, items: Int, comparing: Bool = false, cropping: Bool = false) -> Bool {
            ComparisonRules.canToggle(isComparing: comparing, isCropping: cropping, isLoupe: loupe, selectedCount: selected,
                                      itemCount: items)
        }
        #expect(!can(selected: 0, items: 10))
        #expect(can(selected: 1, items: 10))
        #expect(can(selected: 2, items: 10))
        #expect(!can(selected: 3, items: 10))
        // A source with one item has nothing to compare with.
        #expect(!can(selected: 1, items: 1))
        #expect(!can(loupe: true, selected: 1, items: 1))
        // The loupe: two or more in the source, whatever the grid's selection was.
        #expect(can(loupe: true, selected: 5, items: 2))
        // Stop Comparing is always there; nothing during a crop session.
        #expect(can(loupe: true, selected: 2, items: 2, comparing: true))
        #expect(!can(loupe: true, selected: 1, items: 10, cropping: true))
    }

    @Test func theWrongCountEntersNothing() {
        let photos = Self.source(6)
        #expect(Self.entry(photos, selection: [], focus: 2) == .unavailable)
        #expect(Self.entry(photos, selection: [0, 1, 2], focus: 1) == .unavailable)
        #expect(Self.entry(Self.source(1), isLoupe: true, selection: [0], focus: 0) == .unavailable)
    }

    // MARK: AC6: what can't be compared, and why

    @Test func aVideoIsRefusedAndNamed() {
        let photos = Self.source(4) { $0[2].isVideo = true }
        #expect(Self.entry(photos, selection: [1, 2], focus: 1) == .refused(.video(102, alone: false)))
        // The video loupe's Compare Side by Side.
        #expect(Self.entry(photos, isLoupe: true, selection: [2], focus: 2) == .refused(.video(102, alone: true)))
        #expect(Self.entry(photos, selection: [2], focus: 2) == .refused(.video(102, alone: true)))
    }

    /// Design §16 D5: the alert's title names what was asked.
    @Test func theRefusalSaysWhetherOnePhotoOrTwoWereAsked() {
        let photos = Self.source(4) {
            $0[1].isOffline = true
            $0[2].isVideo = true
        }
        func refusal(_ entry: ComparisonEntry) -> ComparisonRefusal? {
            if case .refused(let refusal) = entry { refusal } else { nil }
        }
        // One photo, itself a video or offline: "Can’t Compare This Photo".
        #expect(refusal(Self.entry(photos, isLoupe: true, selection: [], focus: 2))?.concernsOnePhoto == true)
        #expect(refusal(Self.entry(photos, selection: [1], focus: 1))?.concernsOnePhoto == true)
        #expect(ComparisonRefusal.noPartner(100).concernsOnePhoto)
        // Two selected: "Can’t Compare These Photos".
        #expect(refusal(Self.entry(photos, selection: [0, 2], focus: 0))?.concernsOnePhoto == false)
        #expect(refusal(Self.entry(photos, selection: [0, 1], focus: 0))?.concernsOnePhoto == false)
        #expect(!ComparisonRefusal.pairHalves(101, 102).concernsOnePhoto)
    }

    @Test func anOfflinePhotoIsRefusedAndNamed() {
        let photos = Self.source(4) { $0[1].isOffline = true }
        #expect(Self.entry(photos, selection: [1, 2], focus: 2) == .refused(.offline(101, alone: false)))
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 1) == .refused(.offline(101, alone: true)))
    }

    @Test func whenBothFailTheFirstPhotosFirstReasonIsGiven() {
        let photos = Self.source(4) {
            $0[1].isOffline = true
            $0[2].isVideo = true
        }
        #expect(Self.entry(photos, selection: [1, 2], focus: 1) == .refused(.offline(101, alone: false)))
        // A video that is also offline is a video first.
        let both = Self.source(4) {
            $0[0].isVideo = true
            $0[0].isOffline = true
            $0[1].isOffline = true
        }
        #expect(Self.entry(both, selection: [0, 1], focus: 0) == .refused(.video(100, alone: false)))
    }

    @Test func aPhotoWithNothingToCompareWithIsRefused() {
        let photos = Self.source(3) {
            $0[1].isVideo = true
            $0[2].isOffline = true
        }
        #expect(Self.entry(photos, isLoupe: true, selection: [], focus: 0) == .refused(.noPartner(100)))
        #expect(Self.entry(photos, selection: [0], focus: 0) == .refused(.noPartner(100)))
    }

    /// Ruling RI-3.
    @Test func theTwoFilesOfOnePairAreRefused() {
        let photos = Self.source(4) {
            $0[1].partnerVersionID = 102
            $0[2].partnerVersionID = 101
        }
        #expect(Self.entry(photos, selection: [1, 2], focus: 1) == .refused(.pairHalves(101, 102)))
        // A grouped pair is one item and compares like any other photo.
        let grouped = Self.source(4) { $0[1].partnerVersionID = 900 }
        #expect(Self.entry(grouped, selection: [1, 2], focus: 1) == .enter(ComparisonState(left: 101, right: 102)))
    }

    // MARK: AC2, R3: the active photo

    /// The rule `LibraryModel.actionTargets` applies: while comparing, the
    /// selection is the two photos, and a command acts on the active one only.
    @Test func commandsActOnTheActivePhotoOnly() throws {
        let indices: [Int64: Int] = [101: 1, 104: 4]
        var state = ComparisonState(left: 101, right: 104, active: .left)
        var compared = try #require(ComparisonRules.selection(of: state) { indices[$0] })
        #expect(compared.selection == IndexSet([1, 4]))
        #expect(ActionTargets.indices(isLoupe: true, selection: compared.selection, focus: compared.focus) == IndexSet(integer: 1))
        // `A`: the other photo, and only it.
        state.switchActive()
        compared = try #require(ComparisonRules.selection(of: state) { indices[$0] })
        #expect(ActionTargets.indices(isLoupe: true, selection: compared.selection, focus: compared.focus) == IndexSet(integer: 4))
        // The switch key cycles, so it scales to more panes.
        state.switchActive()
        #expect(state.active == .left)
        #expect(state.side(of: 104) == .right)
        #expect(state.side(of: 7) == nil)
    }

    /// The grid's rule is unchanged: every selected photo, or the focused
    /// one when nothing is selected.
    @Test func theGridActsOnItsSelection() {
        #expect(ActionTargets.indices(isLoupe: false, selection: IndexSet([1, 4]), focus: 4) == IndexSet([1, 4]))
        #expect(ActionTargets.indices(isLoupe: false, selection: [], focus: 3) == IndexSet(integer: 3))
        #expect(ActionTargets.indices(isLoupe: true, selection: IndexSet([1, 4]), focus: nil).isEmpty)
    }

    // MARK: AC4, R5 and ruling RI-1: leaving

    /// Leaving changes neither the selection nor the focus, so what the
    /// comparison selects is what is left: the pair on screen (also after a
    /// walk) and the active photo, which the single loupe then shows.
    @Test func leavingKeepsTheCurrentPairSelectedAndTheActivePhotoFocused() throws {
        let indices: [Int64: Int] = [101: 1, 104: 4, 105: 5]
        var state = ComparisonState(left: 101, right: 104, active: .right)
        // The right side walked on: the pair on screen is what stays selected.
        state[.right] = 105
        let compared = try #require(ComparisonRules.selection(of: state) { indices[$0] })
        #expect(compared.selection == IndexSet([1, 5]))
        #expect(compared.focus == 5)
        // Back in the grid the pair is selected, and a command acts on both.
        #expect(ActionTargets.indices(isLoupe: false, selection: compared.selection, focus: compared.focus) == IndexSet([1, 5]))
        // A photo that is not in the source any more: nothing to select.
        #expect(ComparisonRules.selection(of: ComparisonState(left: 101, right: 900)) { indices[$0] } == nil)
    }

    // MARK: R6: walking a side

    @Test func walkingSkipsTheOtherSideAndWhatCannotBeCompared() {
        let photos = Self.source(8) {
            $0[3].isVideo = true
            $0[5].isOffline = true
        }
        func walk(_ walk: ComparisonRules.Walk, from index: Int, other: Int) -> Int? {
            ComparisonRules.walkTarget(walk, from: index, other: other, count: photos.count) { photos[$0] }
        }
        // Over the other side (2) and the video (3).
        #expect(walk(.next, from: 1, other: 2) == 4)
        #expect(walk(.previous, from: 4, other: 2) == 1)
        #expect(walk(.next, from: 4, other: 2) == 6)
        // At either end the key does nothing.
        #expect(walk(.next, from: 7, other: 2) == nil)
        #expect(walk(.previous, from: 0, other: 2) == nil)
        #expect(walk(.previous, from: 1, other: 0) == nil)
        // Home and End: the first and last photo the side can show.
        #expect(walk(.first, from: 4, other: 0) == 1)
        #expect(walk(.last, from: 1, other: 7) == 6)
        #expect(walk(.first, from: 1, other: 0) == nil)
    }

    @Test func walkingNeverPutsTheOtherFileOfThePairBesideIt() {
        let photos = Self.source(5) {
            $0[1].partnerVersionID = 102
            $0[2].partnerVersionID = 101
        }
        #expect(ComparisonRules.walkTarget(.next, from: 0, other: 2, count: 5) { photos[$0] } == 3)
        #expect(ComparisonRules.walkTarget(.previous, from: 3, other: 1, count: 5) { photos[$0] } == 0)
    }

    // MARK: Film strip (design §7)

    @Test func aStripClickWalksTheActiveSideOrSwitchesSides() {
        let photos = Self.source(6) {
            $0[4].isVideo = true
            $0[5].isOffline = true
        }
        func click(_ index: Int) -> ComparisonRules.StripClick {
            ComparisonRules.stripClick(on: index, activeIndex: 1, otherIndex: 2, active: .left) { photos[$0] }
        }
        #expect(click(1) == .nothing)
        #expect(click(2) == .activate(.right))
        #expect(click(3) == .replaceActive(3))
        #expect(click(4) == .refuse)
        #expect(click(5) == .refuse)
    }

    @Test func aStripClickNeverPutsTheOtherFileOfThePairBesideIt() {
        // 1 and 2 are the RAW and JPEG of one photo; the other side shows 1.
        let photos = Self.source(5) {
            $0[1].partnerVersionID = 102
            $0[2].partnerVersionID = 101
        }
        #expect(ComparisonRules.stripClick(on: 2, activeIndex: 3, otherIndex: 1, active: .right) { photos[$0] } == .refuse)
        // The active side's own other file is another photo to show there.
        #expect(ComparisonRules.stripClick(on: 2, activeIndex: 1, otherIndex: 3, active: .left) { photos[$0] }
            == .replaceActive(2))
    }

    // MARK: When a compared photo goes away (design §6)

    @Test func aReloadKeepsTheComparisonWhileBothPhotosRemain() {
        let state = ComparisonState(left: 101, right: 104, active: .right)
        #expect(ComparisonRules.reconcile(state) { _ in true } == .kept(state))
    }

    @Test func aPhotoLeavingTheSourceEndsTheComparisonOnTheOther() {
        let state = ComparisonState(left: 101, right: 104, active: .right)
        #expect(ComparisonRules.reconcile(state) { $0 != 104 } == .ended(remaining: 101))
        #expect(ComparisonRules.reconcile(state) { $0 != 101 } == .ended(remaining: 104))
        #expect(ComparisonRules.reconcile(state) { _ in false } == .ended(remaining: nil))
    }

    @Test func aSideFollowsItsPairsOtherFile() {
        // RAW+JPEG Pair ▸ Show the JPEG on the active photo of a grouped pair:
        // its version changes, the photo is the same, the comparison stays.
        let state = ComparisonState(left: 101, right: 104, active: .left)
        let pairs: [Int64: Int64] = [101: 201]
        #expect(ComparisonRules.reconcile(state, pairPartner: { pairs[$0] }) { $0 != 101 }
            == .kept(ComparisonState(left: 201, right: 104, active: .left)))
        // The same for the side that is not active (the switch undone after `A`).
        let switched = ComparisonState(left: 101, right: 104, active: .right)
        #expect(ComparisonRules.reconcile(switched, pairPartner: { pairs[$0] }) { $0 != 101 }
            == .kept(ComparisonState(left: 201, right: 104, active: .right)))
        // Never the same photo twice.
        #expect(ComparisonRules.reconcile(state, pairPartner: { _ in 104 }) { $0 != 101 } == .ended(remaining: 104))
        // The pair's other file is not in the source either: the comparison ends.
        #expect(ComparisonRules.reconcile(state, pairPartner: { pairs[$0] }) { $0 == 104 } == .ended(remaining: 104))
    }

    /// Removing the active photo (its project, say) reloads with the focus
    /// on the photo after it. Nobody chose that photo and it may be a video:
    /// it never takes the side, and the comparison ends on the other photo.
    @Test func aRemovedPhotosNeighbourNeverTakesItsSide() {
        let state = ComparisonState(left: 101, right: 104, active: .left)
        // 102 is present and would be focused next; 101 has no pair.
        #expect(ComparisonRules.reconcile(state) { $0 != 101 } == .ended(remaining: 104))
        #expect(ComparisonRules.reconcile(state, pairPartner: { _ in nil }) { $0 != 101 } == .ended(remaining: 104))
    }

    // MARK: AC5: review

    @Test func escLeavesReviewFirstAndComparisonStaysOn() {
        #expect(ComparisonRules.escape(isReviewing: true) == .exitReview)
        #expect(ComparisonRules.escape(isReviewing: false) == .showGrid)
        // Review does not decide whether the command is there.
        #expect(ComparisonRules.canToggle(isComparing: true, isCropping: false, isLoupe: true, selectedCount: 2, itemCount: 9))
    }

    // MARK: AC3, R4: linked zoom and position

    @Test func theLinkIsOnUntilTurnedOff() {
        #expect(ComparisonLink.isLinked(stored: nil))
        #expect(ComparisonLink.isLinked(stored: true))
        #expect(!ComparisonLink.isLinked(stored: false))
        #expect(ComparisonLink.defaultsKey == "compare.linksViews")
    }

    @Test func sameSizeFramesLineUpPixelForPixel() {
        // Two 3000 × 2000 pt documents in 500 × 400 pt panes at 100%.
        let document = CGSize(width: 3000, height: 2000)
        let visible = CGRect(x: 1200, y: 700, width: 500, height: 400)
        let unit = ComparisonLink.unitCenter(visible: visible, document: document)
        #expect(ComparisonLink.visibleOrigin(centering: unit, document: document, visible: visible.size) == visible.origin)
    }

    @Test func differentlySizedPhotosStayOnTheSameRelativePoint() {
        let unit = ComparisonLink.unitCenter(visible: CGRect(x: 1250, y: 400, width: 500, height: 400),
                                             document: CGSize(width: 3000, height: 2000))
        #expect(unit == CGPoint(x: 0.5, y: 0.3))
        // The follower is half the size: the same fractions of it are in the middle.
        let origin = ComparisonLink.visibleOrigin(centering: unit, document: CGSize(width: 1500, height: 1000),
                                                  visible: CGSize(width: 500, height: 400))
        #expect(origin == CGPoint(x: 500, y: 100))
    }

    @Test func theFollowerIsClampedToItsOwnBounds() {
        let document = CGSize(width: 1500, height: 1000)
        let pane = CGSize(width: 500, height: 400)
        #expect(ComparisonLink.visibleOrigin(centering: CGPoint(x: 0.02, y: 0.99), document: document, visible: pane)
            == CGPoint(x: 0, y: 600))
        // A document smaller than the pane on one axis is centered on it, as in the loupe.
        #expect(ComparisonLink.visibleOrigin(centering: CGPoint(x: 0.5, y: 0.5), document: CGSize(width: 300, height: 1000),
                                             visible: pane) == CGPoint(x: -100, y: 300))
    }

    /// What the pane that follows does for a leader at `magnification`.
    static func following(_ magnification: Double, leaderZoomedIn: Bool, leaderFit: Double, followerFit: Double,
                          maximum: Double = 8) -> Double {
        ComparisonLink.magnification(
            following: magnification,
            leaderIsFitted: ComparisonLink.isFitted(isZoomedIn: leaderZoomedIn, magnification: magnification, fit: leaderFit),
            followerFit: followerFit, maximum: maximum)
    }

    @Test func linkedPanesTakeTheSameMagnification() {
        // Both to 100%: each at one photo pixel per device pixel.
        #expect(Self.following(1, leaderZoomedIn: true, leaderFit: 0.2, followerFit: 0.2) == 1)
        #expect(Self.following(2, leaderZoomedIn: true, leaderFit: 0.2, followerFit: 0.4) == 2)
        // The leader at its fit: the follower at its own.
        #expect(Self.following(0.2, leaderZoomedIn: false, leaderFit: 0.2, followerFit: 0.4) == 0.4)
        // At the low end each stops at its own fit.
        #expect(Self.following(0.3, leaderZoomedIn: true, leaderFit: 0.2, followerFit: 0.4) == 0.4)
        #expect(Self.following(9, leaderZoomedIn: true, leaderFit: 0.2, followerFit: 0.4) == 8)
        // A pinch enlarging a fitted pane, before the gesture has ended: the other follows it.
        #expect(Self.following(0.5, leaderZoomedIn: false, leaderFit: 0.2, followerFit: 0.2) == 0.5)
    }

    /// AC3 for a photo about the size of its pane or smaller, where 100% is
    /// (nearly) its fit: a 2048 px JPEG in a wide pane beside a 24 MP raw.
    /// The magnification can't say whether 100% or fit was asked for; the
    /// zoom the command set does.
    @Test func aPhotoAsSmallAsItsPaneStillTakesTheOtherTo100Percent() {
        // The small photo leads, zoomed to 100% by `Z`: the raw goes to 100%, not back to fit.
        #expect(Self.following(1, leaderZoomedIn: true, leaderFit: 1, followerFit: 0.12) == 1)
        #expect(Self.following(1, leaderZoomedIn: true, leaderFit: 0.97, followerFit: 0.12) == 1)
        #expect(!ComparisonLink.isFitted(isZoomedIn: true, magnification: 1, fit: 1))
        // `Z` again: the same magnification, now meant as fit, and the raw goes to its fit.
        #expect(Self.following(1, leaderZoomedIn: false, leaderFit: 1, followerFit: 0.12) == 0.12)
        #expect(ComparisonLink.isFitted(isZoomedIn: false, magnification: 1, fit: 1))
        // The raw leads at 100%: the small photo stays at 100%, which is its fit.
        #expect(Self.following(1, leaderZoomedIn: true, leaderFit: 0.12, followerFit: 1) == 1)
        // The raw leads back to fit: the small photo is at its own fit.
        #expect(Self.following(0.12, leaderZoomedIn: false, leaderFit: 0.12, followerFit: 1) == 1)
    }

    @Test func unitCenterOfAnEmptyDocumentIsTheMiddle() {
        #expect(ComparisonLink.unitCenter(visible: .zero, document: .zero) == CGPoint(x: 0.5, y: 0.5))
    }

    // MARK: AC1: each pane shows the loupe's renditions

    @Test func aLoadOnlyReplacesALesserRendition() {
        let order: [LoupeRendition] = [.placeholder, .preview, .hdrPreview, .full, .hdrFull, .live]
        #expect(order == order.sorted())
        #expect(LoupeRendition.hdrPreview.isHDR && LoupeRendition.hdrFull.isHDR)
        #expect(!LoupeRendition.preview.isHDR && !LoupeRendition.full.isHDR)
        #expect(LoupeRendition.full.isFullResolution && LoupeRendition.hdrFull.isFullResolution)
        #expect(!LoupeRendition.hdrPreview.isFullResolution)
    }

    // MARK: Layout (design §2, §6)

    @Test func panesAreEqualColumnsWithAGutterRoundEach() {
        let canvases = ComparisonGeometry.canvases(in: CGSize(width: 1000, height: 600))
        #expect(canvases == [CGRect(x: 4, y: 4, width: 492, height: 592), CGRect(x: 504, y: 4, width: 492, height: 592)])
        // Between the two canvases: two gutters.
        #expect(canvases[1].minX - canvases[0].maxX == 8)
    }

    @Test func enteringRefitsTheLoupesPhotoIntoItsPane() {
        let size = CGSize(width: 1000, height: 600)
        #expect(ComparisonGeometry.canvas(of: .left, in: size, progress: 0) == CGRect(origin: .zero, size: size))
        #expect(ComparisonGeometry.canvas(of: .left, in: size, progress: 1) == ComparisonGeometry.canvases(in: size)[0])
        #expect(ComparisonGeometry.canvas(of: .right, in: size, progress: 1) == ComparisonGeometry.canvases(in: size)[1])
        // A remembered pair can bring the loupe's photo back on the right (design §16 D3).
        #expect(ComparisonGeometry.canvas(of: .right, in: size, progress: 0) == CGRect(origin: .zero, size: size))
        #expect(ComparisonGeometry.canvas(of: .left, in: size, progress: 0.5) == CGRect(x: 2, y: 2, width: 746, height: 596))
    }

    @Test(arguments: PaletteAppearance.allCases)
    func theRingSitsInTheGutterConcentricWithTheCanvas(_ appearance: PaletteAppearance) {
        let canvas = CGRect(x: 4, y: 4, width: 492, height: 592)
        let width = PaletteSpec.selectedBorderWidth(in: appearance)
        let ring = ComparisonGeometry.ring(around: canvas, width: width)
        // The line's outer edge is the gutter's outer edge, radius 8.
        #expect(ring.rect.insetBy(dx: -width / 2, dy: -width / 2) == canvas.insetBy(dx: -4, dy: -4))
        #expect(ring.cornerRadius + width / 2 == 8)
        // Its inner edge never reaches the canvas.
        #expect(ring.rect.insetBy(dx: width / 2, dy: width / 2).contains(canvas))
    }

    // MARK: Symbols (design §4, §9)

    /// The toolbar item's and the link toggle's symbols resolve on the
    /// system the tests run on; CI runs them on macOS 15, the app's minimum.
    @Test(arguments: [ComparisonRules.toolbarSymbolName, ComparisonRules.linkSymbolName])
    @MainActor func symbolsResolve(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }

    /// Where the system keeps the release each symbol first shipped in. A
    /// private file: nil when a macOS release has moved or reshaped it.
    static let symbolReleases: (symbols: [String: String], releases: [String: [String: String]])? = {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let symbols = plist["symbols"] as? [String: String],
              let releases = plist["year_to_release"] as? [String: [String: String]] else { return nil }
        return (symbols, releases)
    }()

    /// On a newer macOS the symbols resolving says nothing about macOS 15,
    /// so the system's own list is asked when it lists them. Skipped where
    /// the list is not in that place or shape, or does not name the symbol.
    @Test(.enabled(if: [ComparisonRules.toolbarSymbolName, ComparisonRules.linkSymbolName].allSatisfy { name in
              ComparisonTests.symbolReleases.map { $0.releases[$0.symbols[name] ?? ""]?["macOS"] != nil } ?? false
          }, "This macOS does not list symbol availability where macOS 27 does"),
          arguments: [ComparisonRules.toolbarSymbolName, ComparisonRules.linkSymbolName])
    func symbolsDateFromBeforeMacOS15(_ name: String) throws {
        let list = try #require(Self.symbolReleases)
        let macOS = try #require(list.releases[list.symbols[name] ?? ""]?["macOS"])
        let major = try #require(Int(macOS.split(separator: ".").first ?? ""))
        #expect(major <= 15, "\(name) needs macOS \(macOS)")
    }

    // MARK: Subtitle (design §11)

    @Test func theSubtitleSaysComparing() {
        #expect(BrowserSubtitle.loupe(isFiltered: false, isComparing: true) == .comparing(filtered: false))
        #expect(BrowserSubtitle.loupe(isFiltered: true, isComparing: true) == .comparing(filtered: true))
        #expect(BrowserSubtitle.loupe(isFiltered: true) == .source(filtered: true))
    }
}
