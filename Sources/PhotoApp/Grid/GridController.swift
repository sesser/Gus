import AppKit
import PhotoCore
import SwiftUI

/// Hosts the AppKit grid inside SwiftUI.
struct GridView: NSViewRepresentable {
    let model: LibraryModel

    func makeCoordinator() -> GridController {
        GridController(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(cellSize: model.thumbnailSize, mode: model.mode, showsInfo: model.showFileInfo)
    }
}

/// Grid of thumbnails backed by `NSCollectionView` with `UniformGridLayout`.
@MainActor
final class GridController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, LibraryItemsObserver {
    let model: LibraryModel
    let scrollView = NSScrollView()
    let collectionView = PhotoCollectionView()
    let layout = UniformGridLayout()
    private var mode: BrowserMode = .grid
    private var showsInfo: Bool?
    private var prefetchTasks: [Int: Task<Void, Never>] = [:]
    private var prefetchScheduled = false

    init(model: LibraryModel) {
        self.model = model
        super.init()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [Palette.gridBackground]
        collectionView.register(PhotoCell.self, forItemWithIdentifier: PhotoCell.identifier)
        collectionView.controller = self

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.gridBackground
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(takeFocus(_:)),
                                               name: .browserShouldTakeFocus, object: model)
        model.observer = self
    }

    func update(cellSize: Double, mode: BrowserMode, showsInfo: Bool) {
        if showsInfo != self.showsInfo {
            self.showsInfo = showsInfo
            refreshVisibleCells()
        }
        if layout.targetCellSize != cellSize {
            let anchor = model.focusIndex
            layout.targetCellSize = cellSize
            collectionView.layoutSubtreeIfNeeded()
            refreshVisibleCells()
            if let anchor { scroll(to: anchor, centered: true) }
        }
        if mode != self.mode {
            self.mode = mode
            scrollView.isHidden = mode != .grid
            if mode == .grid {
                collectionView.window?.makeFirstResponder(collectionView)
            }
        }
    }

    /// Thumbnail decode size for the current cell size.
    var pixelSize: Int {
        Int(layout.cellSize * (collectionView.window?.backingScaleFactor ?? 2))
    }

    // MARK: Data source

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        model.items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: PhotoCell.identifier, for: indexPath)
        guard let cell = cell as? PhotoCell, model.items.indices.contains(indexPath.item) else { return cell }
        let index = indexPath.item
        cell.configure(with: model.items[index], model: model, pixelSize: pixelSize)
        cell.onDoubleClick = { [weak self] in self?.model.openLoupe(at: index) }
        return cell
    }

    // MARK: Selection from the mouse

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel(clicked: indexPaths.count == 1 ? indexPaths.first?.item : nil)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel(clicked: nil)
    }

    private func syncSelectionToModel(clicked: Int?) {
        model.gridSelectionChanged(IndexSet(collectionView.selectionIndexPaths.map(\.item)), focus: clicked)
    }

    // MARK: Keyboard

    func perform(_ action: CullingAction) {
        model.perform(action)
    }

    /// Returns true when the key was handled.
    func navigate(_ key: NavigationKey, extend: Bool) -> Bool {
        let count = model.items.count
        guard count > 0 else { return false }
        let current = model.focusIndex ?? 0
        let columns = layout.columns
        let pageRows = max(1, Int(scrollView.contentView.bounds.height / (layout.cellSize + layout.spacing)) - 1)
        let target: Int
        switch key {
        case .left: target = current - 1
        case .right: target = current + 1
        case .up: target = current - columns
        case .down: target = current + columns
        case .home: target = 0
        case .end: target = count - 1
        case .pageUp: target = current - columns * pageRows
        case .pageDown: target = current + columns * pageRows
        case .toggleLoupe:
            model.openLoupe()
            return true
        case .exitLoupe, .toggleZoom:
            return false
        }
        model.setFocus(min(max(target, 0), count - 1), extend: extend)
        return true
    }

    // MARK: Model changes

    func libraryItemsReloaded() {
        cancelPrefetch()
        collectionView.reloadData()
        applyModelSelection()
        if let focus = model.focusIndex { scroll(to: focus, centered: false) }
        schedulePrefetch()
    }

    func libraryItemsChanged(at indices: IndexSet) {
        for indexPath in collectionView.indexPathsForVisibleItems() where indices.contains(indexPath.item) {
            guard let cell = collectionView.item(at: indexPath) as? PhotoCell else { continue }
            let item = model.items[indexPath.item]
            cell.updateBadges(with: item, offline: model.isOffline(item))
        }
    }

    func libraryFocusChanged() {
        applyModelSelection()
        if let focus = model.focusIndex { scroll(to: focus, centered: false) }
    }

    func libraryAvailabilityChanged() {
        refreshVisibleCells()
    }

    private func applyModelSelection() {
        let paths = Set(model.selection.map { IndexPath(item: $0, section: 0) })
        if collectionView.selectionIndexPaths != paths {
            collectionView.selectionIndexPaths = paths
        }
    }

    private func refreshVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let cell = collectionView.item(at: indexPath) as? PhotoCell,
                  model.items.indices.contains(indexPath.item) else { continue }
            cell.configure(with: model.items[indexPath.item], model: model, pixelSize: pixelSize)
        }
    }

    func scroll(to index: Int, centered: Bool) {
        guard model.items.indices.contains(index) else { return }
        let frame = layout.frame(forItemAt: index)
        let visible = scrollView.contentView.bounds
        if !centered, visible.contains(frame) { return }
        var origin = visible.origin
        if centered {
            origin.y = frame.midY - visible.height / 2
        } else if frame.minY < visible.minY {
            origin.y = frame.minY - layout.spacing
        } else {
            origin.y = frame.maxY + layout.spacing - visible.height
        }
        let maxY = max(0, collectionView.frame.height - visible.height)
        origin.y = min(max(origin.y, 0), maxY)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Display

    /// Previews are converted to the screen's color space as they are decoded, so
    /// Core Animation never converts them on the main thread.
    func windowDidChange(_ window: NSWindow?) {
        // One undo stack for the window, so ⌘Z works wherever the focus is.
        if let undoManager = window?.undoManager { model.undoManager = undoManager }
        let center = NotificationCenter.default
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeScreenProfileNotification] {
            center.removeObserver(self, name: name, object: nil)
            if let window {
                center.addObserver(self, selector: #selector(screenDidChange(_:)), name: name, object: window)
            }
        }
        updateDisplayColorSpace(window)
    }

    @objc private func takeFocus(_ notification: Notification) {
        if mode == .grid { collectionView.window?.makeFirstResponder(collectionView) }
    }

    @objc private func screenDidChange(_ notification: Notification) {
        updateDisplayColorSpace(notification.object as? NSWindow)
    }

    private func updateDisplayColorSpace(_ window: NSWindow?) {
        let space = window?.colorSpace?.cgColorSpace ?? window?.screen?.colorSpace?.cgColorSpace
        guard model.previews.displayColorSpace != space else { return }
        model.previews.displayColorSpace = space
    }

    // MARK: Prefetch

    /// Decodes thumbnails a screen above and below the visible area at low
    /// priority, so they are in memory by the time they scroll in.
    @objc private func boundsDidChange(_ notification: Notification) {
        schedulePrefetch()
    }

    private func schedulePrefetch() {
        guard !prefetchScheduled else { return }
        prefetchScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.prefetchScheduled = false
                self?.prefetch()
            }
        }
    }

    private func prefetch() {
        let visible = scrollView.contentView.bounds
        guard visible.height > 0 else { return }
        let window = visible.insetBy(dx: 0, dy: -visible.height)
        let visibleRange = layout.indices(in: visible)
        let wanted = layout.indices(in: window)
        for (index, task) in prefetchTasks where !wanted.contains(index) || visibleRange.contains(index) {
            task.cancel()
            prefetchTasks[index] = nil
        }
        let pixelSize = self.pixelSize
        let previews = model.previews
        for index in wanted where !visibleRange.contains(index) && prefetchTasks[index] == nil {
            guard let request = model.previewRequest(for: model.items[index], tier: .thumbnail),
                  previews.memoryCachedImage(for: request, maxPixelSize: pixelSize) == nil
            else { continue }
            prefetchTasks[index] = Task { [weak self] in
                _ = try? await previews.image(for: request, maxPixelSize: pixelSize, priority: .prefetch)
                self?.prefetchTasks[index] = nil
            }
        }
    }

    private func cancelPrefetch() {
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
    }
}

/// Routes keys to the controller before `NSCollectionView`'s own handling.
final class PhotoCollectionView: NSCollectionView {
    weak var controller: GridController?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let action = CullingKeymap.action(for: event) {
            controller?.perform(action)
            return
        }
        if let key = NavigationKey.from(event),
           controller?.navigate(key, extend: event.modifierFlags.contains(.shift)) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.windowDidChange(window)
        window?.makeFirstResponder(self)
    }
}
