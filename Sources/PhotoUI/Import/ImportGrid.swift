import AppKit
import PhotoCore
import SwiftUI

/// The import grid: the library grid's `NSCollectionView` and
/// `UniformGridLayout` with `ImportCell`s (decision 18). The check box is the
/// selection, so the collection view selects nothing itself; the keyboard
/// focus is a cell with the system focus ring.
struct ImportGridView: NSViewRepresentable {
    let model: CardImportModel
    /// Read in the parent's body so a change updates the grid.
    let shots: [SourceShot]
    let selection: Set<URL>

    func makeCoordinator() -> ImportGridController {
        ImportGridController(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(shots: shots, selection: selection)
    }
}

@MainActor
final class ImportGridController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let model: CardImportModel
    let scrollView = NSScrollView()
    let collectionView = ImportCollectionView()
    let layout = UniformGridLayout()
    private(set) var shots: [SourceShot] = []
    private var selection: Set<URL> = []
    /// The keyboard focus, by shot so it survives rescans.
    private(set) var focusID: URL?

    init(model: CardImportModel) {
        self.model = model
        super.init()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [Palette.gridBackground]
        collectionView.register(ImportCell.self, forItemWithIdentifier: ImportCell.identifier)
        collectionView.controller = self
        collectionView.focusRingType = .exterior
        collectionView.setAccessibilityLabel(String(localized: "Photos to import",
                                                    comment: "VoiceOver: the import window's grid"))
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.gridBackground
    }

    func update(shots: [SourceShot], selection: Set<URL>) {
        if shots.map(\.id) != self.shots.map(\.id) || shots != self.shots {
            self.shots = shots
            self.selection = selection
            if let focusID, !shots.contains(where: { $0.id == focusID }) { self.focusID = nil }
            collectionView.reloadData()
            collectionView.noteFocusRingMaskChanged()
        } else if selection != self.selection {
            self.selection = selection
            refreshVisibleCells()
        }
    }

    var focusIndex: Int? {
        focusID.flatMap { id in shots.firstIndex { $0.id == id } }
    }

    private var pixelSize: Int {
        Int(layout.cellSize * (collectionView.window?.backingScaleFactor ?? 2))
    }

    private var colorSpace: CGColorSpace? {
        let window = collectionView.window
        return window?.colorSpace?.cgColorSpace ?? window?.screen?.colorSpace?.cgColorSpace
    }

    // MARK: Data source

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        shots.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ImportCell.identifier, for: indexPath)
        guard let cell = item as? ImportCell, shots.indices.contains(indexPath.item) else { return item }
        configure(cell, at: indexPath.item)
        return cell
    }

    private func configure(_ cell: ImportCell, at index: Int) {
        let shot = shots[index]
        cell.configure(with: shot, included: selection.contains(shot.id), colorSpace: colorSpace, pixelSize: pixelSize)
        cell.onClick = { [weak self] event in self?.click(shot, event: event) }
        cell.onToggle = { [weak self] in self?.toggle(shot, extend: false) }
    }

    private func refreshVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let cell = collectionView.item(at: indexPath) as? ImportCell, shots.indices.contains(indexPath.item)
            else { continue }
            configure(cell, at: indexPath.item)
        }
    }

    // MARK: Mouse and keys

    private func click(_ shot: SourceShot, event: NSEvent) {
        collectionView.window?.makeFirstResponder(collectionView)
        setFocus(shot.id)
        toggle(shot, extend: event.modifierFlags.contains(.shift))
    }

    func toggle(_ shot: SourceShot, extend: Bool) {
        guard !shot.isDuplicate else { return }
        model.click(shot, extend: extend)
    }

    func toggleFocused() {
        guard let index = focusIndex else { return }
        toggle(shots[index], extend: false)
    }

    /// Returns true when the key moved the focus.
    func move(_ move: GridMove) -> Bool {
        let pageRows = max(1, Int(scrollView.contentView.bounds.height / (layout.cellSize + layout.spacing)) - 1)
        guard let target = move.target(from: focusIndex, columns: layout.columns, count: shots.count, pageRows: pageRows)
        else { return false }
        setFocus(shots[target].id)
        return true
    }

    func setFocus(_ id: URL?) {
        focusID = id
        collectionView.noteFocusRingMaskChanged()
        guard let index = focusIndex else { return }
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestHorizontalEdge)
        if let cell = focusedCellView { NSAccessibility.post(element: cell, notification: .focusedUIElementChanged) }
    }

    var focusedFrame: NSRect? {
        focusIndex.map { layout.frame(forItemAt: $0) }
    }

    var focusedCellView: NSView? {
        focusIndex.flatMap { collectionView.item(at: IndexPath(item: $0, section: 0))?.view }
    }

    // MARK: Context menu

    /// Select / Deselect for the clicked shot, then Select All and Deselect All.
    func menu(forItemAt index: Int?) -> NSMenu? {
        let menu = NSMenu()
        if let index, shots.indices.contains(index) {
            let shot = shots[index]
            setFocus(shot.id)
            if !shot.isDuplicate {
                let included = selection.contains(shot.id)
                menu.addItem(ClosureMenuItem(included ? String(localized: "Deselect", comment: "Import grid context menu")
                                                      : String(localized: "Select", comment: "Import grid context menu")) {
                    [weak self] in self?.toggle(shot, extend: false)
                })
                menu.addItem(.separator())
            }
        }
        let all = ClosureMenuItem(String(localized: "Select All")) { [weak self] in self?.model.selectAll() }
        all.isEnabled = model.canSelectAll
        let none = ClosureMenuItem(String(localized: "Deselect All")) { [weak self] in self?.model.selectNone() }
        none.isEnabled = model.canDeselectAll
        menu.addItem(all)
        menu.addItem(none)
        menu.autoenablesItems = false
        return menu
    }

    func windowDidChange(_ window: NSWindow?) {
        model.window = window
    }
}

/// The import grid's collection view: keys, the focus ring and the context menu.
final class ImportCollectionView: NSCollectionView {
    weak var controller: ImportGridController?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return super.keyDown(with: event) }
        let move: GridMove? = switch event.keyCode {
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        case 115: .home
        case 119: .end
        case 116: .pageUp
        case 121: .pageDown
        default: nil
        }
        if let move, controller.move(move) { return }
        switch event.keyCode {
        case 49: // Space
            controller.toggleFocused()
        case 36, 76: // Return, Enter
            controller.model.startImport()
        default:
            super.keyDown(with: event)
        }
    }

    /// Edit ▸ Select All (⌘A) while the grid has the focus; text fields keep
    /// theirs.
    override func selectAll(_ sender: Any?) {
        guard controller?.model.canSelectAll == true else { return }
        controller?.model.selectAll()
    }



    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, controller?.focusID == nil, let first = controller?.shots.first { controller?.setFocus(first.id) }
        noteFocusRingMaskChanged()
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        noteFocusRingMaskChanged()
        return resigned
    }

    override var focusRingMaskBounds: NSRect {
        MainActor.assumeIsolated { controller?.focusedFrame } ?? .zero
    }

    override func drawFocusRingMask() {
        guard let frame = MainActor.assumeIsolated({ controller?.focusedFrame }) else { return }
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.windowDidChange(window)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        return controller?.menu(forItemAt: path?.item)
    }

    // Declared nonisolated, but AppKit asks accessibility questions on the main thread.
    override var accessibilityFocusedUIElement: Any? {
        let cell = MainActor.assumeIsolated { controller?.focusedCellView }
        return cell ?? super.accessibilityFocusedUIElement
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() {
        handler()
    }
}

/// Edit ▸ Select All is dimmed while copying, as the Selection pull-down's is
/// (design.md I16). Other items stay enabled, as without validation.
extension ImportCollectionView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectAll(_:)) { return controller?.model.canSelectAll == true }
        return true
    }
}
