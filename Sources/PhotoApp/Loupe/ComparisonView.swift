import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

// Side by side comparison (docs/features/side-by-side-comparison/design.md):
// the loupe showing two photos. Two panes, each a loupe canvas of its own
// (the single loupe's scroll view and image view), in equal columns on the
// loupe's surround. Nothing is edited here, so a pane only loads the saved
// renditions the single loupe loads (preview, HDR, full resolution when
// zoomed) and never talks to the editor.
//
// Linked zoom and position (§5): a person's scroll, drag or pinch on one
// pane is followed by the other through its clip view's bounds changes.
// Whatever the code itself does to a pane (a refit, a new photo, a
// rendition of another size) runs inside `performWithoutFollowing`, and the
// controller then says explicitly what the other pane does.

struct ComparisonCanvas: NSViewRepresentable {
    let model: LibraryModel

    func makeCoordinator() -> ComparisonController {
        ComparisonController(model: model)
    }

    func makeNSView(context: Context) -> ComparisonHostView {
        context.coordinator.hostView
    }

    func updateNSView(_ view: ComparisonHostView, context: Context) {
        // Reading these registers observation: culling, a walked side, the
        // active side, the link, HDR and the key window all land here.
        _ = (model.itemsRevision, model.comparison, model.comparisonLeaving, model.linksComparison, model.showsHDR,
             model.isWindowKey)
        context.coordinator.update()
    }

    static func dismantleNSView(_ view: ComparisonHostView, coordinator: ComparisonController) {
        coordinator.tearDown()
    }
}

/// Lays out the two panes, keeps them linked, runs the entering and leaving
/// animations and handles the comparison's keys.
@MainActor
final class ComparisonController: NSObject {
    let model: LibraryModel
    let hostView = ComparisonHostView()
    let panes: [ComparisonPane]
    private let ringLayer = CAShapeLayer()
    /// The comparison on screen: the model's, or the one being left.
    private(set) var shown: ComparisonState?
    private var isLeaving = false
    /// The pane the loupe's photo refits into while entering (design §2,
    /// §16 D3): left, or right when a remembered pair comes back that way.
    private var enteringSide = ComparisonSide.left
    private var linked: Bool
    /// 0: one pane fills the loupe, as the single loupe's canvas does; 1:
    /// both panes sit in their columns.
    private var progress = 1.0
    private var animation: FilmStripAnimation?
    /// Started once the view is in a window (the display link needs one).
    private var pendingAnimation: FilmStripAnimation?
    private var displayLink: CADisplayLink?
    /// Above zero while the code itself moves a pane: the other does not follow.
    private var followSuspensions = 0
    /// A refit before this time animates (the film strip changed the frame).
    private var animatesFitUntil = Date.distantPast
    private var fittedSize = NSSize.zero
    private var neighborTasks: [Task<Void, Never>] = []
    private var screenObserver: (any NSObjectProtocol)?
    /// The debug script's `compare animate off`: zoom, refits, entering and
    /// leaving happen at once, so a scripted check reads the settled state
    /// without waiting, and works while the display sleeps (animations and
    /// display links do not run then). Never changed by the app itself.
    static var debugAnimates = true
    private var describedValues: [ComparisonSide: String] = [:]

    init(model: LibraryModel) {
        self.model = model
        linked = model.linksComparison
        panes = ComparisonSide.allCases.map { ComparisonPane(side: $0, model: model) }
        super.init()
        hostView.controller = self
        hostView.wantsLayer = true
        for pane in panes {
            pane.controller = self
            hostView.addSubview(pane.view)
        }
        ringLayer.fillColor = nil
        ringLayer.actions = ["path": NSNull(), "hidden": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull()]
        ringLayer.isHidden = true
        hostView.layer?.addSublayer(ringLayer)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(takeFocus(_:)), name: .browserShouldTakeFocus, object: nil)
        center.addObserver(self, selector: #selector(zoomRequested(_:)), name: .loupeShouldToggleZoom, object: model)
        center.addObserver(self, selector: #selector(zoomStepRequested(_:)), name: .loupeShouldStepZoom, object: model)
        center.addObserver(self, selector: #selector(zoomSetRequested(_:)), name: .loupeShouldSetZoom, object: model)
        center.addObserver(self, selector: #selector(animateNextFit(_:)), name: .loupeShouldAnimateNextFit, object: model)
        center.addObserver(self, selector: #selector(colorsChanged(_:)), name: NSColor.systemColorsDidChangeNotification,
                           object: nil)
    }

    func tearDown() {
        stopAnimation()
        neighborTasks.forEach { $0.cancel() }
        panes.forEach { $0.tearDown() }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        NotificationCenter.default.removeObserver(self)
    }

    private func pane(_ side: ComparisonSide) -> ComparisonPane { panes[side.rawValue] }

    /// The pane commands act on; nil once the comparison has been left.
    var activePane: ComparisonPane? {
        model.comparison.map { pane($0.active) }
    }

    // MARK: Following the model

    func update() {
        let wasLinked = linked
        linked = model.linksComparison
        for pane in panes { pane.hdrSetting = model.showsHDR }
        if let state = model.comparison {
            let previous = shown
            if isLeaving {
                // Compared again before the leaving animation ended.
                stopAnimation()
                isLeaving = false
                progress = 1
            }
            shown = state
            if previous == nil, let side = model.comparisonEntersFrom, Self.debugAnimates {
                beginEntering(into: side)
            }
            model.comparisonEntersFrom = nil
            layoutPanes()
            for pane in panes {
                let item = model.item(versionID: state[pane.side])
                let isNewPhoto = pane.item?.versionID != item?.versionID
                performWithoutFollowing { pane.show(item) }
                // A side walked to another photo: it opens where the other
                // pane is, so walking a burst at 100% stays on the face (§5).
                if isNewPhoto, previous != nil, linked, let leader = panes.first(where: { $0 !== pane }) {
                    follow(leader, pane)
                }
            }
            if !wasLinked, linked { relink() }
            if previous?.activeVersionID != state.activeVersionID || previous?.active != state.active {
                publishZoom()
                preloadNeighbors()
                if previous != nil { NSAccessibility.post(element: hostView, notification: .selectedChildrenChanged) }
            }
        } else if let leaving = model.comparisonLeaving, shown != nil, !isLeaving, Self.debugAnimates {
            beginLeaving(leaving)
        } else if model.comparisonLeaving != nil, shown == nil || !Self.debugAnimates {
            // A view made only for a comparison already left has nothing to animate.
            model.comparisonLeaving = nil
        }
        updateRing()
        updateAccessibility()
    }

    // MARK: Layout

    func layoutPanes() {
        let size = hostView.bounds.size
        guard size.width > 0, size.height > 0, let shown else { return }
        let animatesFit = size != fittedSize && Date() < animatesFitUntil && Self.debugAnimates
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if size != fittedSize {
            fittedSize = size
            animatesFitUntil = .distantPast
            // One refit per change of the canvas's frame (the film strip's rule).
            model.loupeFitCount += 1
        }
        // The pane that grows from, or to, the whole loupe: the one the
        // loupe's photo goes into, or the active one when leaving.
        let movingSide = isLeaving ? shown.active : enteringSide
        let place = {
            for pane in self.panes {
                let isMoving = pane.side == movingSide
                let frame = isMoving && self.progress < 1
                    ? ComparisonGeometry.canvas(of: pane.side, in: size, progress: self.progress)
                    : ComparisonGeometry.canvases(in: size)[pane.side.rawValue]
                pane.view.isHidden = self.isLeaving && !isMoving
                // Entering: the other pane's photo fades in.
                pane.view.alphaValue = !self.isLeaving && !isMoving ? CGFloat(self.progress) : 1
                pane.setFrame(frame, animatesFit: animatesFit)
            }
        }
        if animatesFit {
            // One animation for both refits; nothing follows until it has
            // ended, or each pane would chase the other's magnification on
            // its way to the new fit.
            followSuspensions += 1
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = ComparisonGeometry.animationDuration
                place()
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.followSuspensions -= 1
                    self.publishZoom()
                }
            })
        } else {
            performWithoutFollowing(place)
        }
        updateRing()
    }

    /// The film strip changes the canvas's frame next: that refit animates,
    /// as long as it comes soon (as in the single loupe).
    @objc private func animateNextFit(_ notification: Notification) {
        animatesFitUntil = Date().addingTimeInterval(0.5)
    }

    // MARK: Entering and leaving (design §2)

    /// The single loupe's photo refits into its pane while the other
    /// pane's photo fades in.
    private func beginEntering(into side: ComparisonSide) {
        enteringSide = side
        progress = 0
        start(FilmStripAnimation(kind: .slide, from: 0, to: 1, duration: ComparisonGeometry.animationDuration,
                                 curve: .easeOut) { [weak self] value in
            self?.progress = Double(value)
            self?.layoutPanes()
        } completion: { [weak self] in
            self?.progress = 1
            self?.layoutPanes()
        })
    }

    /// The active photo refits to the whole loupe; the other pane is gone
    /// at once. The single loupe is already underneath.
    private func beginLeaving(_ state: ComparisonState) {
        isLeaving = true
        shown = state
        performWithoutFollowing { pane(state.active).applyZoom(.fit, unit: nil, animated: false) }
        start(FilmStripAnimation(kind: .slide, from: CGFloat(progress), to: 0,
                                 duration: ComparisonGeometry.animationDuration, curve: .easeOut) { [weak self] value in
            self?.progress = Double(value)
            self?.layoutPanes()
        } completion: { [weak self] in
            // The view goes away with this.
            self?.model.comparisonLeaving = nil
        })
        layoutPanes()
    }

    private func start(_ animation: FilmStripAnimation) {
        stopAnimation()
        guard hostView.window != nil else {
            pendingAnimation = animation
            return
        }
        self.animation = animation
        let link = hostView.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        animation = nil
        pendingAnimation = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard let animation else { return stopAnimation() }
        let now = CACurrentMediaTime()
        if animation.startTime == nil { animation.startTime = now }
        animation.step(animation.value(at: now))
        if animation.isFinished(at: now) {
            stopAnimation()
            animation.completion()
        }
    }

    /// The view joined a window: whether HDR can be shown depends on its
    /// screen, so the photos are loaded again then and after every move to
    /// another screen (as in the single loupe).
    func windowDidChange() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        guard let window = hostView.window else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadPanes() }
        }
        if let pending = pendingAnimation {
            pendingAnimation = nil
            start(pending)
        }
        reloadPanes()
        updateRing()
    }

    private func reloadPanes() {
        performWithoutFollowing {
            for pane in panes { pane.reload() }
        }
    }

    // MARK: The ring (design §6)

    /// A rounded rectangle in the active pane's gutter, in the accent color
    /// the grid and the film strip use for "this photo"; neutral while the
    /// window is not key. It moves at once, with no animation.
    func updateRing() {
        guard let state = model.comparison, progress >= 1, !isLeaving else {
            ringLayer.isHidden = true
            return
        }
        let appearance = hostView.effectiveAppearance
        let width = PaletteSpec.selectedBorderWidth(in: PaletteAppearance(appearance))
        let ring = ComparisonGeometry.ring(around: pane(state.active).view.frame, width: width)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = hostView.bounds
        ringLayer.path = CGPath(roundedRect: ring.rect, cornerWidth: ring.cornerRadius, cornerHeight: ring.cornerRadius,
                                transform: nil)
        ringLayer.lineWidth = width
        ringLayer.strokeColor = ringColor.resolved(for: appearance).cgColor
        ringLayer.isHidden = false
        CATransaction.commit()
    }

    private var ringColor: NSColor {
        model.isWindowKey ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func colorsChanged(_ notification: Notification) {
        updateRing()
    }

    // MARK: Linked zoom and position (design §5)

    /// Runs `body` without the other pane following the bounds changes it causes.
    func performWithoutFollowing(_ body: () -> Void) {
        followSuspensions += 1
        defer { followSuspensions -= 1 }
        body()
    }

    /// A pane's visible part changed. When a person did that, the other
    /// pane goes to the same unit point at the same magnification, frame by
    /// frame, with no animation (direct manipulation).
    func paneDidScroll(_ leader: ComparisonPane) {
        guard followSuspensions == 0 else { return }
        if linked, model.comparison != nil {
            for follower in panes where follower !== leader { follow(leader, follower) }
        }
        if leader === activePane || linked { publishZoom() }
    }

    private func follow(_ leader: ComparisonPane, _ follower: ComparisonPane) {
        performWithoutFollowing {
            let fitted = leader.isFitted
            let magnification = ComparisonLink.magnification(
                following: Double(leader.magnification), leaderIsFitted: fitted,
                followerFit: Double(follower.fitMagnification), maximum: Double(follower.scrollView.maxMagnification))
            // Linked panes share the zoom: fitted or zoomed in, as the leader is.
            follower.show(magnification: CGFloat(magnification), unitCenter: leader.unitCenter,
                          zoom: fitted ? .fit : .actualSize)
        }
    }

    /// The link was turned on: the inactive pane jumps to the active pane's
    /// magnification and unit center, which is the one being worked in.
    private func relink() {
        guard let leader = activePane else { return }
        let unit = leader.unitCenter
        let zoom = leader.zoom
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && Self.debugAnimates
        animate(animated, leader: leader) {
            for follower in self.panes where follower !== leader {
                if zoom == .fit {
                    follower.applyZoom(.fit, unit: nil, animated: animated)
                } else {
                    let magnification = ComparisonLink.magnification(
                        following: Double(leader.magnification), leaderIsFitted: false,
                        followerFit: Double(follower.fitMagnification), maximum: Double(follower.scrollView.maxMagnification))
                    follower.setZoom(.actualSize)
                    follower.setMagnification(CGFloat(magnification), unit: unit, animated: animated)
                }
            }
        }
    }

    /// Runs zoom changes on one or both panes as one animation (the
    /// loupe's 0.15 s); nothing follows until it has ended. Each pane keeps
    /// the zoom the command gave it, as the single loupe does (a photo
    /// about the size of its pane is at 100% and at fit at once, so the
    /// magnification can't say which was asked for). Then linked panes are
    /// put exactly where `leader` ended (photos of different sizes can end
    /// a little apart, since each zooms about its own point on screen).
    private func animate(_ animated: Bool, leader: ComparisonPane, _ changes: @escaping @MainActor () -> Void) {
        followSuspensions += 1
        let finish: @MainActor () -> Void = { [weak self, weak leader] in
            guard let self else { return }
            self.followSuspensions -= 1
            if let leader, self.linked, self.model.comparison != nil {
                for follower in self.panes where follower !== leader { self.follow(leader, follower) }
            }
            self.publishZoom()
        }
        guard animated else {
            changes()
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ComparisonGeometry.animationDuration
            changes()
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }

    /// The panes a command on `pane` reaches: both while linked.
    private func reached(by pane: ComparisonPane) -> [ComparisonPane] {
        linked ? panes : [pane]
    }

    /// A click on the active pane, `Z`, the menus: 100% about the same unit
    /// point (the clicked point, which stays under the pointer as in the
    /// single loupe; the pane's center for keys), or fit.
    func toggleZoom(on pane: ComparisonPane, atDocumentPoint point: NSPoint? = nil) {
        setZoom(pane.zoom == .fit ? .actualSize : .fit, on: pane, unit: point.map(pane.unit(ofDocumentPoint:)))
    }

    func setZoom(_ zoom: LoupeController.Zoom, on pane: ComparisonPane, unit: CGPoint? = nil) {
        let unit = unit ?? pane.unitCenter
        let targets = reached(by: pane)
        let animated = Self.debugAnimates
        animate(animated, leader: pane) {
            for target in targets { target.applyZoom(zoom, unit: unit, animated: animated) }
        }
        publishZoom(magnification: zoom == .fit ? pane.fitMagnification : 1, zoom: zoom)
    }

    /// ⌘= / ⌘−: the next step, keeping each pane's visible center; at the
    /// low end each pane stops at its own fit.
    func stepZoom(in zoomIn: Bool) {
        guard let pane = activePane else { return }
        let fit = pane.fitMagnification
        guard let target = zoomIn ? LoupeZoomSteps.zoomIn(from: pane.magnification, fit: fit)
                                  : LoupeZoomSteps.zoomOut(from: pane.magnification, fit: fit) else { return }
        let targets = reached(by: pane)
        let zoom: LoupeController.Zoom = target > fit * 1.001 ? .actualSize : .fit
        let animated = Self.debugAnimates
        animate(animated, leader: pane) {
            for other in targets {
                let magnification = other === pane ? target : CGFloat(ComparisonLink.magnification(
                    following: Double(target), leaderIsFitted: zoom == .fit, followerFit: Double(other.fitMagnification),
                    maximum: Double(other.scrollView.maxMagnification)))
                other.setZoom(zoom)
                other.setMagnification(magnification, unit: other.unitCenter, animated: animated)
            }
        }
        publishZoom(magnification: target, zoom: zoom)
    }

    /// Tells the menus and the toolbar the active pane's zoom.
    func publishZoom(magnification: CGFloat? = nil, zoom: LoupeController.Zoom? = nil) {
        guard let pane = activePane else { return }
        let current = magnification ?? pane.magnification
        let zoom = zoom ?? pane.zoom
        let fit = pane.fitMagnification
        let state = LoupeZoomState(isZoomed: zoom != .fit,
                                   canZoomIn: LoupeZoomSteps.zoomIn(from: current, fit: fit) != nil,
                                   canZoomOut: zoom != .fit && LoupeZoomSteps.zoomOut(from: current, fit: fit) != nil,
                                   isActualSize: zoom != .fit && abs(current - 1) < 0.01)
        if model.loupeZoom != state { model.loupeZoom = state }
    }

    @objc private func zoomRequested(_ notification: Notification) {
        if let pane = activePane { toggleZoom(on: pane) }
    }

    @objc private func zoomStepRequested(_ notification: Notification) {
        guard model.comparison != nil, let zoomIn = notification.userInfo?[LoupeZoomStep.zoomInKey] as? Bool else { return }
        stepZoom(in: zoomIn)
    }

    /// The toolbar's Fit / 100%.
    @objc private func zoomSetRequested(_ notification: Notification) {
        guard let pane = activePane, let fit = notification.userInfo?[LoupeZoomStep.fitKey] as? Bool else { return }
        setZoom(fit ? .fit : .actualSize, on: pane)
    }

    // MARK: Pointer (design §5)

    /// A mouse-down on a pane: an inactive one becomes active, and that
    /// click does nothing more (true), as a first click in an inactive
    /// window only brings it forward.
    func activate(_ pane: ComparisonPane) -> Bool {
        guard let state = model.comparison, state.active != pane.side else { return false }
        model.setComparisonActive(pane.side)
        return true
    }

    // MARK: Keys

    /// From the model, or from a view in this window (an inspector value field).
    @objc private func takeFocus(_ notification: Notification) {
        guard notification.object as AnyObject? === model || notification.object as AnyObject? === hostView.window else { return }
        if model.comparison != nil { hostView.window?.makeFirstResponder(hostView) }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard model.comparison != nil else { return false }
        if let action = CullingKeymap.action(for: event) {
            model.perform(action)
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if modifiers.isEmpty {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case ComparisonKey.compare:
                model.toggleComparison()
                return true
            case ComparisonKey.switchSide:
                model.switchComparisonSide()
                return true
            default:
                break
            }
        }
        switch NavigationKey.from(event) {
        case .left, .up: model.walkComparison(.previous)
        case .right, .down: model.walkComparison(.next)
        case .home: model.walkComparison(.first)
        case .end: model.walkComparison(.last)
        case .exitLoupe:
            // Esc backs out one level as in the loupe: review first, then the loupe.
            switch ComparisonRules.escape(isReviewing: model.isReviewing) {
            case .exitReview: model.exitReview()
            case .showGrid: model.closeLoupe()
            }
        case .toggleLoupe: model.closeLoupe()
        case .toggleReview: model.toggleReview()
        case .toggleZoom:
            if let pane = activePane { toggleZoom(on: pane) }
        case .pageUp, .pageDown, nil: return false
        }
        return true
    }

    // MARK: Neighbors

    /// The photos the active side walks to next, so stepping through a
    /// burst does not wait on decoding (as the single loupe preloads).
    private func preloadNeighbors() {
        neighborTasks.forEach { $0.cancel() }
        neighborTasks = []
        guard let index = model.focusIndex else { return }
        let previews = model.previews
        let hdr = model.showsHDR && (hostView.window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1
        for neighbor in [index + 1, index - 1, index + 2] where model.items.indices.contains(neighbor) {
            guard let request = model.previewRequest(for: model.items[neighbor], tier: .preview) else { continue }
            let rendersHDR = hdr && neighbor != index + 2
            neighborTasks.append(Task {
                _ = try? await previews.image(for: request, priority: .prefetch)
                if rendersHDR { _ = try? await previews.hdrImage(for: request, priority: .prefetch) }
            })
        }
    }

    // MARK: Accessibility (design §10)

    /// "Left photo, active, 3 stars, Picked, 12 of 87".
    func accessibilityValue(of pane: ComparisonPane) -> String? {
        guard let state = model.comparison ?? shown, let item = pane.item,
              let index = model.indexOfVersion(item.versionID) else { return nil }
        return AccessibilityText.list([
            ComparisonText.paneValue(pane.side, isActive: state.active == pane.side),
            PhotoAccessibility.loupeValue(for: item, offline: model.isOffline(item), index: index, count: model.items.count),
        ])
    }

    func isActive(_ pane: ComparisonPane) -> Bool {
        model.comparison?.active == pane.side
    }

    /// The canvas's culling actions (performing one makes the pane active
    /// first), Make Active, zoom, the link, Stop Comparing and Show Grid.
    func accessibilityActions(of pane: ComparisonPane) -> [NSAccessibilityCustomAction]? {
        guard let item = pane.item, model.comparison != nil else { return nil }
        var actions = PhotoAccessibility.cullingActions(forVersion: item.versionID, model: model)
        if !isActive(pane) {
            actions.append(PhotoAccessibility.action(String(localized: "Make Active", comment: "VoiceOver action on the comparison's inactive pane")) {
                [weak self] in self?.model.setComparisonActive(pane.side)
            })
        }
        let zoomTitle = pane.zoom == .fit ? String(localized: "Zoom to 100%") : String(localized: "Zoom to Fit")
        actions += [
            PhotoAccessibility.action(zoomTitle) { [weak self] in self?.toggleZoom(on: pane) },
            PhotoAccessibility.action(model.linksComparison ? ComparisonText.unlink : ComparisonText.link) { [weak self] in
                guard let model = self?.model else { return }
                model.setComparisonLinked(!model.linksComparison)
            },
            PhotoAccessibility.action(ComparisonText.stop) { [weak self] in self?.model.stopComparing() },
            PhotoAccessibility.showGrid(model),
        ]
        return actions
    }

    /// Culling a compared photo, or a change of the active side, changes a
    /// pane's value; VoiceOver is told.
    private func updateAccessibility() {
        for pane in panes {
            let value = accessibilityValue(of: pane)
            if let old = describedValues[pane.side], let value, old != value {
                NSAccessibility.post(element: pane.view, notification: .valueChanged)
            }
            describedValues[pane.side] = value
        }
    }

    // MARK: Debug scripts

    /// For `print compare`.
    var debugState: [String] {
        guard let state = model.comparison else { return ["compare off"] }
        let color = ringLayer.isHidden ? "none" : (model.isWindowKey ? "accent" : "neutral")
        var lines = ["compare left \(state.left) right \(state.right) active \(state.active) linked \(model.linksComparison)"
            + " ring \(ringLayer.isHidden ? "hidden" : "drawn") \(color) width \(ringLayer.lineWidth)"
            + " around \(panes.first { $0.side == state.active }.map { NSStringFromRect($0.view.frame) } ?? "-")"]
        for pane in panes {
            let unit = pane.visibleUnitRect
            lines.append(String(format: "compare pane %@ %@ frame %@ magnification %.3f fit %.3f zoom %@ rendition %@ visible %.4f,%.4f %.4fx%.4f",
                                "\(pane.side)", pane.item?.fileName ?? "-", NSStringFromRect(pane.view.frame),
                                pane.magnification, pane.fitMagnification, "\(pane.zoom)", "\(pane.rendition)",
                                unit.minX, unit.minY, unit.width, unit.height))
        }
        return lines
    }
}

/// The comparison's bare keys (design §4), shown in the View menu and
/// handled by the grid, the loupe and the comparison.
enum ComparisonKey {
    /// Compare Side by Side / Stop Comparing.
    static let compare = "s"
    /// Switch to Right Photo / Switch to Left Photo.
    static let switchSide = "a"

    /// `S` with no modifier: the grid's, the loupe's and the video loupe's
    /// way into comparison.
    @MainActor
    static func isCompare(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        return modifiers.isEmpty && event.charactersIgnoringModifiers?.lowercased() == compare
    }
}

/// One pane: a loupe canvas showing one version's saved renditions, at fit
/// or zoomed.
@MainActor
final class ComparisonPane: NSObject {
    let side: ComparisonSide
    let model: LibraryModel
    weak var controller: ComparisonController?
    let view = ComparisonPaneView()
    let scrollView = LoupeScrollView()
    let imageView = LoupeImageView()
    private(set) var item: CatalogItem?
    /// The version and edit shown; a new edit hash loads new renditions.
    private var shownKey: ShownKey?
    private struct ShownKey: Equatable {
        var versionID: Int64
        var editStackHash: String
    }
    private(set) var zoom = LoupeController.Zoom.fit
    private(set) var rendition = LoupeRendition.placeholder
    private var loadTask: Task<Void, Never>?
    private var hdrTask: Task<Void, Never>?
    private var fullTask: Task<Void, Never>?
    /// The model's HDR setting as last applied; changing it reloads the photo.
    var hdrSetting = true {
        didSet { if hdrSetting != oldValue { reload() } }
    }

    init(side: ComparisonSide, model: LibraryModel) {
        self.side = side
        self.model = model
        super.init()
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.02
        scrollView.maxMagnification = 8
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.loupeBackground
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.width, .height]
        view.pane = self
        view.wantsLayer = true
        view.layer?.cornerRadius = ComparisonGeometry.canvasCornerRadius
        view.layer?.masksToBounds = true
        view.addSubview(scrollView)

        scrollView.onActivate = { [weak self] in
            guard let self else { return false }
            return self.controller?.activate(self) ?? false
        }
        scrollView.onClick = { [weak self] point in
            guard let self else { return }
            self.controller?.toggleZoom(on: self, atDocumentPoint: point)
        }
        scrollView.onDoubleClick = { [weak self] in self?.model.closeLoupe() }
        scrollView.onZoomScroll = { [weak self] factor, point in self?.zoom(by: factor, at: point) }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleRectChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(didEndMagnify(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    func tearDown() {
        scrollView.cancelPendingClick()
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Showing a version

    /// Loads the shown photo's renditions again (another screen, the HDR setting).
    func reload() {
        guard item != nil else { return }
        shownKey = nil
        show(item)
    }

    func show(_ newItem: CatalogItem?) {
        guard let newItem else {
            item = nil
            shownKey = nil
            rendition = .placeholder
            imageView.setImage(nil)
            setHeadroom(nil)
            return
        }
        let reloads = shownKey == nil && item?.versionID == newItem.versionID
        item = newItem
        let key = ShownKey(versionID: newItem.versionID, editStackHash: newItem.editStackHash)
        guard key != shownKey else { return }
        let sameVersion = key.versionID == shownKey?.versionID || reloads
        shownKey = key
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()

        let backing = view.window?.backingScaleFactor ?? 2
        if let size = newItem.orientedSize, !sameVersion {
            imageView.setFrameSize(NSSize(width: size.width / backing, height: size.height / backing))
        }
        rendition = .placeholder
        let immediate = immediateImage(for: newItem)
        // After an edit (an undo), the old rendition stays until the new one is there.
        if immediate != nil || !sameVersion {
            display(immediate?.image, as: immediate?.rendition ?? .placeholder)
        }
        if !sameVersion {
            scrollView.cancelPendingClick()
            // A newly shown photo opens at fit; a linked pane is then put
            // where the other one is (`ComparisonController.update`).
            applyZoom(.fit, unit: nil, animated: false)
        }

        if let request = model.previewRequest(for: newItem, tier: .preview) {
            let previews = model.previews
            loadTask = Task { [weak self] in
                guard let image = try? await previews.image(for: request, priority: .visible),
                      let self, self.shownKey == key, self.rendition <= .preview else { return }
                if newItem.orientedSize == nil {
                    self.resizeDocument(to: NSSize(width: CGFloat(image.width) / backing, height: CGFloat(image.height) / backing))
                }
                self.display(image, as: .preview)
            }
            if hdrAllowed {
                hdrTask = Task { [weak self] in
                    guard let image = try? await previews.hdrImage(for: request, priority: .visible),
                          let self, self.shownKey == key else { return }
                    self.display(image, as: .hdrPreview)
                }
            }
        }
        if zoom == .actualSize { loadFullResolution() }
    }

    /// Whatever is already decoded: the HDR or SDR preview, or an enlarged thumbnail.
    private func immediateImage(for item: CatalogItem) -> (image: CGImage, rendition: LoupeRendition)? {
        if let request = model.previewRequest(for: item, tier: .preview) {
            if hdrAllowed, let image = model.previews.memoryCachedHDRImage(for: request) {
                return (image, .hdrPreview)
            }
            if let image = model.previews.memoryCachedImage(for: request) {
                return (image, .preview)
            }
        }
        guard let request = model.previewRequest(for: item, tier: .thumbnail) else { return nil }
        for size in [512, 384, 256, 128] {
            if let image = model.previews.memoryCachedImage(for: request, maxPixelSize: size) { return (image, .placeholder) }
        }
        return nil
    }

    /// HDR is shown when the setting is on and the window's display has
    /// extended dynamic range, as in the single loupe.
    private var hdrAllowed: Bool {
        guard model.showsHDR, let screen = view.window?.screen else { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
    }

    /// Shows `image` unless something more detailed is already showing.
    private func display(_ image: CGImage?, as kind: LoupeRendition) {
        guard kind >= rendition else { return }
        rendition = kind
        matchFrame(to: image, exact: kind.isFullResolution)
        imageView.setImage(image, extendedRange: kind.isHDR)
        setHeadroom(kind.isHDR ? image?.contentHeadroom : nil)
        updateFiltering()
    }

    private func setHeadroom(_ headroom: Float?) {
        if model.comparisonHDRHeadroom[side] != headroom { model.comparisonHDRHeadroom[side] = headroom }
    }

    /// Keeps the image view in the proportions of what it shows, which a
    /// crop or a quarter turn changes. A full-resolution rendition sets its
    /// size exactly; others keep the current long edge.
    private func matchFrame(to image: CGImage?, exact: Bool) {
        guard let image, image.width > 0, image.height > 0 else { return }
        let backing = view.window?.backingScaleFactor ?? 2
        let current = imageView.frame.size
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var size: NSSize
        if exact {
            size = NSSize(width: CGFloat(image.width) / backing, height: CGFloat(image.height) / backing)
        } else {
            guard current.width > 0, current.height > 0,
                  abs(current.width / current.height - aspect) > 0.01 * aspect else { return }
            let long = max(current.width, current.height)
            size = aspect >= 1 ? NSSize(width: long, height: long / aspect) : NSSize(width: long * aspect, height: long)
        }
        guard abs(size.width - current.width) > 0.5 || abs(size.height - current.height) > 0.5 else { return }
        resizeDocument(to: size)
    }

    /// A rendition of another size: the same place stays in the middle at
    /// the same zoom, and the other pane does not move.
    private func resizeDocument(to size: NSSize) {
        let change = {
            let unit = self.unitCenter
            self.imageView.setFrameSize(size)
            let target = self.zoom == .fit ? self.fitMagnification : self.scrollView.magnification
            self.scrollView.setMagnification(target, centeredAt: self.documentPoint(ofUnit: unit))
        }
        if let controller { controller.performWithoutFollowing(change) } else { change() }
    }

    /// Nearest-neighbor only for real pixels above 100%, as in the single loupe.
    private func updateFiltering(magnification known: CGFloat? = nil) {
        imageView.usesNearestFiltering = LiveFrameRules.usesNearestFiltering(
            magnification: Double(known ?? scrollView.magnification), showsRealPixels: rendition.isFullResolution,
            keepsShippedFiltering: false)
    }

    /// The saved edit at full resolution, rendered off the main thread by
    /// the preview service, as the single loupe's 100% is. The pane keeps
    /// the image while it shows the photo; an offline original has none.
    private func loadFullResolution() {
        guard let item, rendition < .full,
              let request = model.previewRequest(for: item, tier: .preview), request.sourceURL != nil else { return }
        let previews = model.previews
        let hdr = hdrAllowed
        let key = shownKey
        fullTask?.cancel()
        fullTask = Task { [weak self] in
            if hdr, let image = try? await previews.hdrImage(for: request, fullResolution: true) {
                guard let self, self.shownKey == key else { return }
                self.display(image, as: .hdrFull)
                return
            }
            guard let image = try? await previews.fullResolutionImage(for: request),
                  let self, self.shownKey == key else { return }
            self.display(image, as: .full)
        }
    }

    // MARK: Geometry

    var magnification: CGFloat { scrollView.magnification }

    /// Fitted within a margin of the neutral surround, as in the single loupe.
    var fitMagnification: CGFloat {
        let document = imageView.frame.size
        let clipSize = scrollView.frame.size
        guard document.width > 0, document.height > 0, clipSize.width > 0 else { return 1 }
        let margin: CGFloat = 24
        let width = max(clipSize.width - margin * 2, 1)
        let height = max(clipSize.height - margin * 2, 1)
        return min(width / document.width, height / document.height, 1)
    }

    /// The middle of what is on screen, as fractions of the photo.
    var unitCenter: CGPoint {
        ComparisonLink.unitCenter(visible: scrollView.documentVisibleRect, document: imageView.frame.size)
    }

    func unit(ofDocumentPoint point: NSPoint) -> CGPoint {
        let size = imageView.bounds.size
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max(point.x / size.width, 0), 1), y: min(max(point.y / size.height, 0), 1))
    }

    func documentPoint(ofUnit unit: CGPoint) -> NSPoint {
        let size = imageView.bounds.size
        return NSPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    /// The part of the photo on screen in unit coordinates from the top
    /// left, for the debug script.
    var visibleUnitRect: CGRect {
        let bounds = imageView.bounds
        let visible = scrollView.documentVisibleRect.intersection(bounds)
        guard bounds.width > 0, bounds.height > 0, !visible.isEmpty else { return .zero }
        return CGRect(x: visible.minX / bounds.width, y: 1 - visible.maxY / bounds.height,
                      width: visible.width / bounds.width, height: visible.height / bounds.height)
    }

    /// The pane's place in the comparison; a fitted photo refits (inside
    /// the caller's animation group when `animatesFit`).
    func setFrame(_ frame: NSRect, animatesFit: Bool) {
        guard view.frame != frame else { return }
        view.frame = frame
        guard zoom == .fit else { return }
        applyZoom(.fit, unit: nil, animated: animatesFit)
    }

    /// Whether the pane that follows this one should be at its own fit
    /// (`ComparisonLink.isFitted`).
    var isFitted: Bool {
        ComparisonLink.isFitted(isZoomedIn: zoom == .actualSize, magnification: Double(scrollView.magnification),
                                fit: Double(fitMagnification))
    }

    /// The zoom a command or the linked pane gives this one; zoomed in
    /// shows the full-resolution render.
    func setZoom(_ newZoom: LoupeController.Zoom) {
        guard zoom != newZoom else { return }
        zoom = newZoom
        if newZoom == .actualSize { loadFullResolution() }
    }

    // MARK: Zoom

    /// Fit, or 100% with `unit` in the middle (the photo's center when nil).
    func applyZoom(_ zoom: LoupeController.Zoom, unit: CGPoint?, animated: Bool) {
        setZoom(zoom)
        setMagnification(zoom == .fit ? fitMagnification : 1, unit: unit ?? CGPoint(x: 0.5, y: 0.5), animated: animated)
    }

    /// Inside the caller's animation group when `animated`.
    func setMagnification(_ target: CGFloat, unit: CGPoint, animated: Bool) {
        let center = documentPoint(ofUnit: unit)
        updateFiltering(magnification: target)
        if animated {
            scrollView.animator().setMagnification(target, centeredAt: center)
        } else {
            scrollView.setMagnification(target, centeredAt: center)
        }
    }

    /// Follows the other pane: its magnification, `unitCenter` in the
    /// middle, clamped to this photo's bounds, and its zoom.
    func show(magnification target: CGFloat, unitCenter: CGPoint, zoom newZoom: LoupeController.Zoom) {
        if abs(scrollView.magnification - target) > 0.0001 { scrollView.magnification = target }
        let clip = scrollView.contentView
        let origin = ComparisonLink.visibleOrigin(centering: unitCenter, document: imageView.frame.size,
                                                  visible: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
        updateFiltering()
        setZoom(newZoom)
    }

    /// Takes the zoom from the magnification a pinch or an Option-scroll on
    /// this pane left, as the single loupe does: zoomed in past fit shows
    /// the full resolution render.
    func adoptMagnification() {
        updateFiltering()
        if scrollView.magnification > fitMagnification * 1.05 {
            if zoom != .actualSize {
                zoom = .actualSize
                loadFullResolution()
            }
        } else {
            zoom = .fit
        }
    }

    /// Option-scroll zooms between fit and the largest magnification,
    /// keeping the image point under the pointer where it is.
    func zoom(by factor: CGFloat, at windowPoint: NSPoint) {
        let old = scrollView.magnification
        let target = ScrollZoom.magnification(old, factor: factor, minimum: fitMagnification,
                                              maximum: scrollView.maxMagnification)
        guard abs(target - old) > 0.0001 else { return }
        let clip = scrollView.contentView
        let anchor = imageView.convert(windowPoint, from: nil)
        let origin = ScrollZoom.visibleOrigin(keeping: anchor, visibleOrigin: clip.bounds.origin, from: old, to: target)
        // One step for the other pane to follow, not two.
        controller?.performWithoutFollowing {
            scrollView.magnification = target
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
            scrollView.reflectScrolledClipView(clip)
        }
        adoptMagnification()
        controller?.paneDidScroll(self)
    }

    @objc private func visibleRectChanged(_ notification: Notification) {
        controller?.paneDidScroll(self)
    }

    @objc private func didEndMagnify(_ notification: Notification) {
        adoptMagnification()
        controller?.paneDidScroll(self)
    }
}

/// A pane's canvas, clipped to its corner radius. To VoiceOver it is an
/// image element as the loupe's canvas is: the scroll view inside it is hidden.
final class ComparisonPaneView: NSView {
    weak var pane: ComparisonPane?

    /// Right-click first makes the pane active, as a grid right-click selects.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let pane, let controller = pane.controller, controller.model.comparison != nil, pane.item != nil else { return nil }
        _ = controller.activate(pane)
        return PhotoContextMenu.comparison(model: controller.model)
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { pane?.item != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { pane?.item.map(PhotoAccessibility.label) }
    override func accessibilityValue() -> Any? { pane.flatMap { $0.controller?.accessibilityValue(of: $0) } }
    override func isAccessibilitySelected() -> Bool { pane.map { $0.controller?.isActive($0) == true } ?? false }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        pane.flatMap { $0.controller?.accessibilityActions(of: $0) }
    }
    override func accessibilityChildren() -> [Any]? { [] }

    // Declared nonisolated, but AppKit asks accessibility questions on the main thread.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        super.accessibilityHitTest(point) == nil ? nil : self
    }
}

/// Holds the two panes and the active pane's ring, and takes the keyboard
/// as the loupe's canvas does: one key view where the canvas is. To
/// VoiceOver it is a group, "Comparison", with the panes in reading order.
final class ComparisonHostView: NSView {
    weak var controller: ComparisonController?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if controller?.handle(event) != true { super.keyDown(with: event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The single loupe takes the keyboard back while this view only
        // shows the comparison being left.
        if controller?.model.comparison != nil { window?.makeFirstResponder(self) }
        controller?.windowDidChange()
    }

    override func layout() {
        super.layout()
        controller?.layoutPanes()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        controller?.updateRing()
    }

    override func isAccessibilityElement() -> Bool { controller?.model.comparison != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        String(localized: "Comparison", comment: "VoiceOver: the group holding the two photos being compared")
    }
    override func accessibilityChildren() -> [Any]? { controller?.panes.map(\.view) }
    override func accessibilitySelectedChildren() -> [Any]? {
        controller?.activePane.map { [$0.view] }
    }
}
