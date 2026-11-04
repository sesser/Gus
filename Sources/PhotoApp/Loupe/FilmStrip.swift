import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

// The loupe's film strip (section 11 of docs/UI_REDESIGN.md): the current
// source's photos in a row between the photo and the caption, the focused
// one centered, with a resize handle on its top edge. It only moves focus,
// the way the arrow keys do, and never takes the keyboard.
//
// The canvas must refit once per change, never per frame. So the layout
// reserves the strip's height in steps (`FilmStripPresence` and the stored
// step), and everything that moves continuously (sliding in and out, a
// resize drag, settling on a step) happens inside the strip's own AppKit
// view, which may draw over the canvas's bottom margin while it does.

/// The strip's fixed measurements that are not geometry (`FilmStripGeometry`).
enum FilmStripMetrics {
    /// Mark glyphs (flag, video, offline) and the label's dot.
    static let markGlyphSize: CGFloat = 9
    static let labelDotSize: CGFloat = 7
    /// The backing's corner radius, its padding around the marks, the gap
    /// between two marks on it, and its distance from the image's corner.
    static let markCornerRadius: CGFloat = 3
    static let markPadding: CGFloat = 2
    static let markGap: CGFloat = 2
    static let markInset: CGFloat = 2
    static let cellCornerRadius: CGFloat = 4
    /// Rejected photos, as in the grid.
    static let rejectedOpacity: Float = 0.35
    static let fadeDuration: CFTimeInterval = 0.12
    /// The caption toggle's smallest hit area (section 10).
    static let minimumHitSize: CGFloat = 20
    /// The resize handle's capsule.
    static let handleSize = NSSize(width: 36, height: 4)
    /// The resize zone reaches this far above and below the strip's top edge.
    static let handleReach: CGFloat = 4
}

/// Whether the strip is in the view tree and whether the layout reserves its
/// height (decision 10). Showing reserves the height at once (one refit) and
/// slides the strip up into it; hiding slides it down first, then gives the
/// height back (one refit).
@MainActor
@Observable
final class FilmStripPresence {
    /// The strip's view exists: while shown, and while it slides away.
    private(set) var isPresent = false
    /// The layout holds the strip's height under the canvas.
    private(set) var reservesSpace = false
    /// The next strip view created slides in (a show from the toggle or menu).
    @ObservationIgnored private var slidesInOnAppear = false
    @ObservationIgnored weak var controller: FilmStripController?
    @ObservationIgnored weak var model: LibraryModel?

    /// `animated`: the person showed or hid the strip (the toggle, the menu);
    /// opening the loupe and review change it at once.
    func set(shown: Bool, animated: Bool) {
        let animated = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shown {
            if reservesSpace {
                // Shown again while it slides away: back up from where it is.
                if controller?.isHiding == true { controller?.slide(in: true, animated: animated) }
                return
            }
            if animated { postAnimateNextFit() }
            isPresent = true
            reservesSpace = true
            if let controller {
                controller.slide(in: true, animated: animated)
            } else {
                slidesInOnAppear = animated
            }
        } else {
            guard isPresent else { return }
            if animated, let controller {
                controller.slide(in: false, animated: true) { [weak self] in self?.finishHiding(animated: true) }
            } else {
                finishHiding(animated: false)
            }
        }
    }

    private func finishHiding(animated: Bool) {
        if animated { postAnimateNextFit() }
        reservesSpace = false
        isPresent = false
        slidesInOnAppear = false
    }

    /// Read once by a new strip view.
    func takeSlideIn() -> Bool {
        defer { slidesInOnAppear = false }
        return slidesInOnAppear
    }

    func postAnimateNextFit() {
        NotificationCenter.default.post(name: .loupeShouldAnimateNextFit, object: model)
    }
}

/// The strip's AppKit view. Its frame is taller than the height the layout
/// reserves: the strip grows over the canvas's bottom margin during a resize
/// drag, and the handle's zone reaches above the top edge. Points above the
/// strip go through to the canvas (`FilmStripHostView.hitTest`).
struct FilmStripView: NSViewRepresentable {
    let model: LibraryModel
    let presence: FilmStripPresence
    /// The stored step as shown under the cap.
    let geometry: FilmStripGeometry
    let loupeHeight: Double

    /// The view's height: the tallest strip a drag can reach, plus the
    /// handle's reach above it.
    static func frameHeight(loupeHeight: Double) -> CGFloat {
        CGFloat(FilmStripGeometry.dragHeights(loupeHeight: loupeHeight).upperBound) + FilmStripMetrics.handleReach
    }

    func makeCoordinator() -> FilmStripController {
        FilmStripController(model: model, presence: presence)
    }

    func makeNSView(context: Context) -> FilmStripHostView {
        context.coordinator.hostView
    }

    func updateNSView(_ view: FilmStripHostView, context: Context) {
        context.coordinator.update(geometry: geometry, loupeHeight: loupeHeight)
    }

    static func dismantleNSView(_ view: FilmStripHostView, coordinator: FilmStripController) {
        coordinator.tearDown()
    }
}

/// Feeds the strip from the model, keeps the focused photo centered, and
/// runs the strip's own motion: sliding in and out, resize drags and
/// settling on a step. Hears item and focus changes as a
/// `LibraryItemsObserver`, beside the grid.
@MainActor
final class FilmStripController: NSObject, NSCollectionViewDataSource, LibraryItemsObserver {
    let model: LibraryModel
    let presence: FilmStripPresence
    let hostView = FilmStripHostView()
    let scrollView = FilmStripScrollView()
    let collectionView = FilmStripCollectionView()
    let layout = FilmStripLayout()
    let handle = FilmStripHandleView()
    /// The index drawn as focused.
    private var shownFocus: Int?
    private var shownWidth: CGFloat = 0
    private var clipObserver: (any NSObjectProtocol)?

    /// The settled step's strip, from the layout.
    private var settledGeometry = FilmStripGeometry(cellSize: FilmStripGeometry.defaultSize)
    private var loupeHeight: Double = 0
    /// The strip's height now (the cells are this minus the padding); it
    /// differs from the settled one during a drag and the settle after it.
    private var stripHeight: CGFloat = 0
    /// How much of the strip shows, from its bottom: the strip's height,
    /// less while it slides in or out.
    private var revealHeight: CGFloat = 0
    private var hasLaidOut = false
    private var slidesIn = false

    // Motion
    private var animation: FilmStripAnimation?
    /// Started once the view is in a window (the display link needs one).
    private var pendingAnimation: FilmStripAnimation?
    private var displayLink: CADisplayLink?
    private(set) var isHiding = false
    private var isDragging = false
    private var dragStart: (pointerY: CGFloat, height: CGFloat)?

    init(model: LibraryModel, presence: FilmStripPresence) {
        self.model = model
        self.presence = presence
        super.init()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [Palette.loupeBackground]
        collectionView.register(FilmStripCell.self, forItemWithIdentifier: FilmStripCell.identifier)
        collectionView.controller = self

        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.loupeBackground

        hostView.controller = self
        hostView.revealView.addSubview(scrollView)
        hostView.addSubview(hostView.revealView)
        hostView.addSubview(handle)
        handle.controller = self

        // The strip's width decides the end insets: a new width recenters.
        let clip = scrollView.contentView
        clip.postsFrameChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.widthDidChange() }
        }
        shownFocus = model.focusIndex
        slidesIn = presence.takeSlideIn()
        presence.controller = self
        model.addObserver(self)
    }

    func tearDown() {
        stopAnimation()
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
        model.removeObserver(self)
        for item in collectionView.visibleItems() { (item as? FilmStripCell)?.cancelLoad() }
    }

    /// The settled step and the loupe's height, from the layout.
    func update(geometry: FilmStripGeometry, loupeHeight: Double) {
        self.loupeHeight = loupeHeight
        let changed = geometry != settledGeometry || !hasLaidOut
        settledGeometry = geometry
        guard changed, !isDragging, animation?.kind != .settle else {
            handle.update(height: Double(stripHeight), range: FilmStripGeometry.dragHeights(loupeHeight: loupeHeight),
                          shownStep: settledGeometry.cellSize, dragging: isDragging)
            return
        }
        let height = CGFloat(geometry.stripHeight)
        if !hasLaidOut {
            hasLaidOut = true
            stripHeight = height
            if slidesIn {
                slidesIn = false
                revealHeight = 0
                applyHeights()
                slide(in: true, animated: true)
                return
            }
            revealHeight = height
        } else {
            stripHeight = height
            if animation == nil { revealHeight = height }
        }
        applyHeights()
    }

    /// Thumbnail decode size: the largest step's, whatever the step.
    var pixelSize: Int {
        FilmStripGeometry.thumbnailPixelSize(backingScale: Double(hostView.window?.backingScaleFactor ?? 2))
    }

    /// The size shown and the cells' layout for `stripHeight`, then recenters
    /// (every frame of a drag, a slide or a settle: the focused photo stays
    /// in the middle).
    private func applyHeights() {
        let cell = Double(stripHeight) - FilmStripGeometry.verticalPadding * 2
        layout.geometry = FilmStripGeometry(cellSize: cell)
        hostView.revealHeight = revealHeight
        hostView.stripHeight = stripHeight
        hostView.needsLayout = true
        hostView.layoutSubtreeIfNeeded()
        handle.update(height: Double(stripHeight), range: FilmStripGeometry.dragHeights(loupeHeight: loupeHeight),
                      shownStep: settledGeometry.cellSize, dragging: isDragging)
        recenter(animated: false)
    }

    // MARK: Data source

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        model.items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: FilmStripCell.identifier, for: indexPath)
        guard let cell = cell as? FilmStripCell, model.items.indices.contains(indexPath.item) else { return cell }
        configure(cell, at: indexPath.item)
        cell.controller = self
        return cell
    }

    private func configure(_ cell: FilmStripCell, at index: Int) {
        let item = model.items[index]
        cell.configure(with: item, model: model, isFocused: index == model.focusIndex, pixelSize: pixelSize)
    }

    private func refreshVisibleCells(where test: (Int) -> Bool = { _ in true }) {
        for indexPath in collectionView.indexPathsForVisibleItems() where test(indexPath.item) {
            guard model.items.indices.contains(indexPath.item),
                  let cell = collectionView.item(at: indexPath) as? FilmStripCell else { continue }
            configure(cell, at: indexPath.item)
        }
    }

    // MARK: Clicks

    /// A click (or VoiceOver's press) on a thumbnail: focus moves there as
    /// with the arrow keys, through the same `setFocus`, and VoiceOver hears
    /// the same announcement. A click on the focused photo does nothing.
    func cellWasClicked(_ cell: FilmStripCell) {
        guard let index = collectionView.indexPath(for: cell)?.item else { return }
        focus(index)
    }

    func focus(_ index: Int) {
        guard model.items.indices.contains(index), index != model.focusIndex else { return }
        model.setFocus(index)
        model.announceLoupePhoto()
    }

    // MARK: Model changes

    func libraryItemsReloaded() {
        collectionView.reloadData()
        shownFocus = model.focusIndex
        recenter(animated: false)
    }

    func libraryItemsChanged(at indices: IndexSet) {
        refreshVisibleCells { indices.contains($0) }
    }

    func libraryFocusChanged() {
        let previous = shownFocus
        shownFocus = model.focusIndex
        if previous != shownFocus {
            refreshVisibleCells { $0 == previous || $0 == self.shownFocus }
            NSAccessibility.post(element: collectionView, notification: .selectedChildrenChanged)
        }
        // A held arrow key jumps, so the strip keeps up with it.
        let event = NSApp.currentEvent
        let isKeyRepeat = event?.type == .keyDown && event?.isARepeat == true
        recenter(animated: true, isKeyRepeat: isKeyRepeat)
    }

    func libraryAvailabilityChanged() {
        refreshVisibleCells()
    }

    // MARK: Centering

    private func widthDidChange() {
        let width = scrollView.contentView.bounds.width
        guard width != shownWidth else { return }
        shownWidth = width
        recenter(animated: false)
    }

    /// Puts the focused photo in the middle of the strip. Only focus changes
    /// animate, and only over a short distance (`FilmStripGeometry`).
    func recenter(animated: Bool, isKeyRepeat: Bool = false) {
        let clip = scrollView.contentView
        let width = Double(clip.bounds.width)
        let count = model.items.count
        guard width > 0, count > 0, let focus = model.focusIndex else { return }
        let geometry = layout.geometry
        // The document must have its new width before the clip view is
        // constrained to it.
        let size = NSSize(width: geometry.contentWidth(count: count, visibleWidth: width),
                          height: max(geometry.stripHeight, Double(clip.bounds.height)))
        if collectionView.frame.size != size { collectionView.setFrameSize(size) }
        let target = geometry.centeringOffset(for: focus, count: count, visibleWidth: width)
        let current = Double(clip.bounds.origin.x)
        let animates = animated && FilmStripGeometry.animatesMove(
            from: current, to: target, visibleWidth: width, isKeyRepeat: isKeyRepeat,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let origin = NSPoint(x: target, y: 0)
        // Through the animator either way: a new move (or a jump, with no
        // duration) replaces one in flight, from where it is.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animates ? FilmStripGeometry.animationDuration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Showing and hiding

    /// Slides the strip up out of the caption line (`in`) or down into it.
    /// The layout's reserved height does not change here (`FilmStripPresence`).
    func slide(in show: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        isHiding = !show
        let target = show ? stripHeight : 0
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopAnimation()
            revealHeight = target
            applyHeights()
            isHiding = false
            completion?()
            return
        }
        start(FilmStripAnimation(kind: .slide, from: revealHeight, to: target,
                                 duration: show ? FilmStripGeometry.showDuration : FilmStripGeometry.hideDuration,
                                 curve: show ? .easeOut : .easeIn) { [weak self] value in
            self?.revealHeight = value
            self?.applyHeights()
        } completion: { [weak self] in
            self?.isHiding = false
            completion?()
        })
    }

    // MARK: Resizing

    func beginResize(pointerY: CGFloat) {
        stopAnimation()
        revealHeight = stripHeight
        isDragging = true
        dragStart = (pointerY, stripHeight)
        applyHeights()
    }

    /// The strip follows the pointer between the smallest and the largest
    /// step that fit, its cells with it; the layout's height does not change.
    func resize(pointerY: CGFloat) {
        guard let dragStart else { return }
        let range = FilmStripGeometry.dragHeights(loupeHeight: loupeHeight)
        let height = min(max(Double(dragStart.height + pointerY - dragStart.pointerY), range.lowerBound),
                         range.upperBound)
        stripHeight = CGFloat(height)
        revealHeight = stripHeight
        applyHeights()
    }

    /// Settles on the nearest step, then stores it (the layout then gives
    /// the strip that height: one refit).
    func endResize() {
        guard dragStart != nil else { return }
        dragStart = nil
        isDragging = false
        let step = FilmStripGeometry.settledStep(stripHeight: Double(stripHeight), loupeHeight: loupeHeight)
        settle(on: step, storing: FilmStripGeometry.storedStep(afterSettlingOn: step, stored: model.filmStripSize,
                                                                loupeHeight: loupeHeight))
    }

    /// Double-click on the handle: the default step, or the largest that fits.
    func resetSize() {
        stopAnimation()
        let shown = FilmStripGeometry.shownStep(stored: FilmStripGeometry.defaultSize, loupeHeight: loupeHeight)
        settle(on: shown, storing: FilmStripGeometry.defaultSize)
    }

    /// VoiceOver's increment and decrement: one step among those that fit.
    func stepSize(up: Bool) -> Bool {
        guard let step = FilmStripGeometry.step(after: settledGeometry.cellSize, up: up, loupeHeight: loupeHeight)
        else { return false }
        stopAnimation()
        presence.postAnimateNextFit()
        model.filmStripSize = step
        return true
    }

    private func settle(on step: Double, storing stored: Double) {
        let target = CGFloat(FilmStripGeometry.stripHeight(cellSize: step))
        let store = { [weak self] in
            guard let self else { return }
            if self.model.filmStripSize != stored {
                self.presence.postAnimateNextFit()
                self.model.filmStripSize = stored
            }
            self.applyHeights()
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, target != stripHeight else {
            stripHeight = target
            revealHeight = target
            applyHeights()
            store()
            return
        }
        start(FilmStripAnimation(kind: .settle, from: stripHeight, to: target,
                                 duration: FilmStripGeometry.settleDuration, curve: .easeOut) { [weak self] value in
            self?.stripHeight = value
            self?.revealHeight = value
            self?.applyHeights()
        } completion: { store() })
    }

    // MARK: Animation

    /// Runs `animation` on the window's display link, replacing one in
    /// flight. Without a window yet it waits for one.
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

    func windowDidChange() {
        if hostView.window != nil, let pending = pendingAnimation {
            pendingAnimation = nil
            start(pending)
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard let animation else { return stopAnimation() }
        let now = CACurrentMediaTime()
        if animation.startTime == nil { animation.startTime = now }
        let value = animation.value(at: now)
        animation.step(value)
        if animation.isFinished(at: now) {
            stopAnimation()
            animation.completion()
        }
    }

    // MARK: Debug scripts

    /// For `print filmstrip`.
    var debugState: String {
        let clip = scrollView.contentView.bounds
        let geometry = layout.geometry
        let count = model.items.count
        let width = Double(clip.width)
        let centered = geometry.centeredIndex(offset: clip.minX, count: count, visibleWidth: width)
        let visible = geometry.visibleRange(offset: clip.minX, visibleWidth: width, count: count)
        return "step \(settledGeometry.cellSize) cell \(geometry.cellSize) height \(stripHeight) reveal \(revealHeight) "
            + "width \(width) offset \(clip.minX) centered \(centered.map(String.init) ?? "-") "
            + "visible \(visible.lowerBound)..<\(visible.upperBound) focus \(model.focusIndex.map(String.init) ?? "-")"
            + handlePosition
    }

    /// The handle's zone center, in window points from the top left (as
    /// the debug script's `click` and `hit` take them).
    private var handlePosition: String {
        guard let window = hostView.window, !handle.isHidden else { return "" }
        let point = handle.zoneCenterInWindow
        return " handle \(Int(point.x)),\(Int(window.frame.height - point.y))"
    }

    /// The center of cell `index` in window coordinates, when it is on screen.
    func windowPoint(ofCell index: Int) -> NSPoint? {
        guard model.items.indices.contains(index),
              let view = collectionView.item(at: IndexPath(item: index, section: 0))?.view else { return nil }
        let visible = view.visibleRect
        guard !visible.isEmpty else { return nil }
        return view.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
    }
}

/// A value moving over time on the display link.
@MainActor
final class FilmStripAnimation {
    enum Kind { case slide, settle }
    enum Curve {
        case easeIn, easeOut

        func callAsFunction(_ t: Double) -> Double {
            switch self {
            case .easeIn: t * t
            case .easeOut: 1 - (1 - t) * (1 - t)
            }
        }
    }

    let kind: Kind
    let from: CGFloat
    let to: CGFloat
    let duration: Double
    let curve: Curve
    let step: (CGFloat) -> Void
    let completion: () -> Void
    var startTime: CFTimeInterval?

    init(kind: Kind, from: CGFloat, to: CGFloat, duration: Double, curve: Curve,
         step: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        self.kind = kind
        self.from = from
        self.to = to
        self.duration = duration
        self.curve = curve
        self.step = step
        self.completion = completion
    }

    func value(at time: CFTimeInterval) -> CGFloat {
        let progress = min(max((time - (startTime ?? time)) / duration, 0), 1)
        return from + (to - from) * CGFloat(curve(progress))
    }

    func isFinished(at time: CFTimeInterval) -> Bool {
        time - (startTime ?? time) >= duration
    }
}

/// Holds the strip, its bottom on the caption. `revealView` clips the strip
/// while it slides (its content stays pinned to the bottom); the handle
/// sits on the strip's top edge. Points above the handle's zone are not the
/// strip's: they go through to the canvas.
final class FilmStripHostView: NSView {
    weak var controller: FilmStripController?
    let revealView = NSView()
    var revealHeight: CGFloat = 0
    var stripHeight: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        revealView.wantsLayer = true
        revealView.layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.windowDidChange()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        revealView.frame = NSRect(x: 0, y: 0, width: width, height: revealHeight)
        controller?.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: stripHeight)
        controller?.handle.frame = FilmStripHandleView.frame(forStripTop: revealHeight, width: width)
        controller?.handle.isHidden = revealHeight < 1
    }

    // Declared nonisolated, but AppKit hit-tests on the main thread.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let top = MainActor.assumeIsolated { revealHeight }
        guard local.y <= top + FilmStripMetrics.handleReach else { return nil }
        return super.hitTest(point)
    }

    /// Top to bottom: the handle, then the strip.
    override func accessibilityChildren() -> [Any]? {
        guard let controller else { return super.accessibilityChildren() }
        return controller.handle.isHidden ? [controller.scrollView] : [controller.handle, controller.scrollView]
    }
}

// MARK: - Views

/// Scrolls the strip. A plain mouse wheel (line deltas, no horizontal
/// component) scrolls it sideways, as Shift-wheel does, since the strip has
/// no vertical axis; trackpads, Shift-wheel and the scroller work as usual.
final class FilmStripScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
           let sideways = Self.horizontal(event) {
            super.scrollWheel(with: sideways)
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// The same wheel event with its vertical deltas moved to the horizontal axis.
    private static func horizontal(_ event: NSEvent) -> NSEvent? {
        guard let copy = event.cgEvent?.copy() else { return nil }
        let integerAxes: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
        ]
        for (vertical, horizontal) in integerAxes {
            copy.setIntegerValueField(horizontal, value: copy.getIntegerValueField(vertical))
            copy.setIntegerValueField(vertical, value: 0)
        }
        let fixed = (CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis2)
        copy.setDoubleValueField(fixed.1, value: copy.getDoubleValueField(fixed.0))
        copy.setDoubleValueField(fixed.0, value: 0)
        return NSEvent(cgEvent: copy)
    }
}

/// Never takes the keyboard or a selection: the loupe keeps the arrows and
/// the culling keys, and the focused look comes from the model. To
/// VoiceOver it is a list named Film Strip.
final class FilmStripCollectionView: NSCollectionView {
    weak var controller: FilmStripController?

    override var acceptsFirstResponder: Bool { false }

    /// AppKit sizes a collection view to its clip view's width (layouts
    /// scroll vertically as far as it knows); this one scrolls sideways, so
    /// it takes the layout's width.
    override func setFrameSize(_ newSize: NSSize) {
        let content = collectionViewLayout?.collectionViewContentSize.width ?? 0
        super.setFrameSize(NSSize(width: max(newSize.width, content), height: newSize.height))
    }

    // Clicks between cells, drags and right-clicks do nothing.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { String(localized: "Film Strip") }
}

/// Square cells in one row, every frame computed from its index
/// (`FilmStripGeometry`), so a long source costs what is on screen.
final class FilmStripLayout: NSCollectionViewLayout {
    var geometry = FilmStripGeometry(storedSize: FilmStripGeometry.defaultSize, loupeHeight: .infinity) {
        didSet { if oldValue != geometry { invalidateLayout() } }
    }
    private var itemCount = 0
    private var visibleWidth: CGFloat = 0

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        itemCount = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        visibleWidth = collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width
    }

    override var collectionViewContentSize: NSSize {
        NSSize(width: geometry.contentWidth(count: itemCount, visibleWidth: visibleWidth), height: geometry.stripHeight)
    }

    func frame(forItemAt index: Int) -> NSRect {
        NSRect(x: geometry.cellOrigin(index, visibleWidth: visibleWidth), y: FilmStripGeometry.verticalPadding,
               width: geometry.cellSize, height: geometry.cellSize)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        geometry.cells(from: rect.minX, to: rect.maxX, visibleWidth: visibleWidth, count: itemCount).map { index in
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            attributes.frame = frame(forItemAt: index)
            return attributes
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < itemCount else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = frame(forItemAt: indexPath.item)
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != visibleWidth
    }
}

/// The caption's show / hide button for the strip (section 11).
struct FilmStripToggle: View {
    let model: LibraryModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.showsFilmStrip }, set: { model.showsFilmStrip = $0 })) {
            Label("Film Strip", systemImage: FilmStripGeometry.toggleSymbolName)
                .labelStyle(.iconOnly)
                .frame(minWidth: FilmStripMetrics.minimumHitSize, minHeight: FilmStripMetrics.minimumHitSize)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .help(model.showsFilmStrip ? String(localized: "Hide the film strip") : String(localized: "Show the film strip"))
    }
}
