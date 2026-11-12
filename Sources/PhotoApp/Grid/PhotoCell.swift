import AppKit
import PhotoCore
import PhotoUI

/// One grid cell. Everything is drawn with plain layers and implicit animations
/// are disabled, so configuring a cell during fast scrolling is cheap.
final class PhotoCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PhotoCell")

    private let cellView = PhotoCellView()
    private var loadTask: Task<Void, Never>?
    private(set) var versionID: Int64?
    private var editStackHash: String?
    var onDoubleClick: (() -> Void)?

    override func loadView() {
        view = cellView
        cellView.onDoubleClick = { [weak self] in self?.onDoubleClick?() }
    }

    override var isSelected: Bool {
        didSet { cellView.isSelected = isSelected }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        versionID = nil
        editStackHash = nil
        cellView.setImage(nil, animated: false)
    }

    /// Shows `item`, starting an asynchronous thumbnail load if it is not in memory.
    /// After an edit the previous thumbnail stays until the new one is ready.
    func configure(with item: CatalogItem, model: LibraryModel, pixelSize: Int) {
        let isNewItem = versionID != item.versionID
        let isNewRendition = isNewItem || editStackHash != item.editStackHash
        versionID = item.versionID
        editStackHash = item.editStackHash
        cellView.showsInfo = model.showFileInfo
        cellView.model = model
        cellView.apply(item, offline: model.isOffline(item))
        guard isNewRendition || cellView.image == nil else { return }

        loadTask?.cancel()
        guard let request = model.previewRequest(for: item, tier: .thumbnail) else { return }
        if let image = model.previews.memoryCachedImage(for: request, maxPixelSize: pixelSize) {
            cellView.setImage(image, animated: false)
            return
        }
        if isNewItem { cellView.setImage(nil, animated: false) }
        let previews = model.previews
        let versionID = item.versionID
        let editStackHash = item.editStackHash
        loadTask = Task { [weak self] in
            do {
                let image = try await previews.image(for: request, maxPixelSize: pixelSize, priority: .visible)
                guard let self, self.versionID == versionID, self.editStackHash == editStackHash else { return }
                self.cellView.setImage(image, animated: true)
            } catch {
                // Stale: a newer stack is saved, and its hash reconfigures the cell.
                guard let self, self.versionID == versionID, self.editStackHash == editStackHash,
                      !(error is CancellationError), error as? PreviewService.Failure != .staleEditStack else { return }
                self.cellView.showUnavailable()
            }
        }
    }

    var hasImage: Bool { cellView.image != nil }
}

final class PhotoCellView: NSView {
    var onDoubleClick: (() -> Void)?
    /// For VoiceOver's actions on the photo.
    weak var model: LibraryModel?
    private(set) var image: CGImage?

    private let imageLayer = CALayer()
    /// SF Symbol stars, one image per rating.
    private let ratingLayer = CALayer()
    private let nameLayer = CATextLayer()
    private let kindLayer = CALayer()
    private let flagLayer = CALayer()
    private let labelLayer = CALayer()
    private let offlineLayer = CALayer()
    /// The photo is a copy made with Duplicate (virtual-copies design §6.1).
    private let copyLayer = CALayer()
    private let placeholderLayer = CALayer()

    private var item: CatalogItem?
    private var offline = false
    private var unavailable = false
    private var kindSize = CGSize.zero
    private var shownBadgeText: String?

    /// File name and type badge above the star strip, when the cell is wide enough.
    var showsInfo = true {
        didSet { if oldValue != showsInfo { needsLayout = true } }
    }

    var isSelected = false {
        didSet { if oldValue != isSelected { updateChrome() } }
    }

    static let stripHeight: CGFloat = 20
    static let infoHeight: CGFloat = 16
    static let padding: CGFloat = 6
    /// Narrower cells show the image and culling marks only.
    static let minimumStripWidth: CGFloat = 96
    static let minimumInfoWidth: CGFloat = 120
    /// The offline and copy marks on the image's top corners: a white glyph
    /// on a dark backing, at every cell size.
    static let markSize = CGSize(width: 22, height: 18)
    static let markInset: CGFloat = 4
    static let markGlyphSize: CGFloat = 12
    static let markCornerRadius: CGFloat = 4
    static let markBacking = NSColor(white: 0, alpha: 0.55)
    static let copySymbol = "square.on.square"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        layer.cornerRadius = 6
        layer.masksToBounds = true
        layer.actions = Self.noActions

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.minificationFilter = .trilinear
        placeholderLayer.backgroundColor = color(Palette.cellSelected).cgColor
        placeholderLayer.cornerRadius = 3
        ratingLayer.contentsGravity = .left
        nameLayer.fontSize = 11
        nameLayer.font = NSFont.systemFont(ofSize: 11)
        nameLayer.alignmentMode = .left
        nameLayer.truncationMode = .middle
        kindLayer.contentsGravity = .resizeAspect
        labelLayer.cornerRadius = 5
        flagLayer.contentsGravity = .resizeAspect
        offlineLayer.contents = Symbols.image("externaldrive.badge.xmark", color: .white, pointSize: Self.markGlyphSize)
        copyLayer.contents = Symbols.image(Self.copySymbol, color: .white, pointSize: Self.markGlyphSize)
        for mark in [offlineLayer, copyLayer] {
            mark.contentsGravity = .resizeAspect
            mark.backgroundColor = Self.markBacking.cgColor
            mark.cornerRadius = Self.markCornerRadius
        }
        copyLayer.isHidden = true

        for sublayer in [placeholderLayer, imageLayer, ratingLayer, nameLayer, kindLayer, flagLayer, labelLayer,
                         offlineLayer, copyLayer] {
            sublayer.actions = Self.noActions
            layer.addSublayer(sublayer)
        }
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    static let noActions: [String: any CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(),
        "opacity": NSNull(), "backgroundColor": NSNull(), "borderColor": NSNull(), "borderWidth": NSNull(),
        "string": NSNull(), "foregroundColor": NSNull(), "frame": NSNull(),
    ]

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [imageLayer, ratingLayer, nameLayer, kindLayer, flagLayer, offlineLayer, copyLayer] {
            sublayer.contentsScale = scale
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = self.bounds
        let padding = Self.padding
        let showStrip = bounds.width >= Self.minimumStripWidth
        let showInfo = showStrip && showsInfo && bounds.width >= Self.minimumInfoWidth
        let strip = showStrip ? Self.stripHeight + (showInfo ? Self.infoHeight : 0) : 0
        let imageFrame = NSRect(x: padding, y: padding + strip, width: bounds.width - padding * 2,
                                height: bounds.height - padding * 2 - strip)
        imageLayer.frame = imageFrame
        placeholderLayer.frame = imageFrame.insetBy(dx: imageFrame.width * 0.08, dy: imageFrame.height * 0.08)
        ratingLayer.isHidden = !showStrip
        ratingLayer.frame = NSRect(x: padding + 2, y: padding + 2, width: bounds.width * 0.6, height: 15)
        nameLayer.isHidden = !showInfo
        kindLayer.isHidden = !showInfo
        positionInfo()
        flagLayer.frame = NSRect(x: bounds.width - padding - 16, y: padding + 1, width: 15, height: 15)
        positionLabel()
        // Offline at the image's top-leading corner, the copy mark mirrored
        // at top-trailing; both follow the layout direction.
        let mark = Self.markSize
        let markY = imageFrame.maxY - Self.markInset - mark.height
        let leadingX = imageFrame.minX + Self.markInset
        let trailingX = imageFrame.maxX - Self.markInset - mark.width
        let rightToLeft = userInterfaceLayoutDirection == .rightToLeft
        offlineLayer.frame = NSRect(x: rightToLeft ? trailingX : leadingX, y: markY, width: mark.width, height: mark.height)
        copyLayer.frame = NSRect(x: rightToLeft ? leadingX : trailingX, y: markY, width: mark.width, height: mark.height)
        CATransaction.commit()
    }

    /// The name takes the row's width minus the badge, whose width depends on its text.
    private func positionInfo() {
        guard !nameLayer.isHidden else { return }
        let padding = Self.padding
        let rowY = padding + Self.stripHeight - 1
        kindLayer.frame = NSRect(x: bounds.width - padding - 2 - kindSize.width,
                                 y: rowY + (Self.infoHeight - kindSize.height) / 2,
                                 width: kindSize.width, height: kindSize.height)
        nameLayer.frame = NSRect(x: padding + 2, y: rowY, width: max(0, kindLayer.frame.minX - padding - 6),
                                 height: Self.infoHeight - 1)
    }

    /// The label dot sits left of the flag when there is one.
    private func positionLabel() {
        let padding = Self.padding
        labelLayer.frame = bounds.width >= Self.minimumStripWidth
            ? NSRect(x: bounds.width - padding - (flagLayer.isHidden ? 12 : 32), y: padding + 4, width: 10, height: 10)
            : NSRect(x: bounds.width - 14, y: bounds.height - 14, width: 10, height: 10)
    }

    func apply(_ item: CatalogItem, offline: Bool) {
        let previous = self.item
        let wasOffline = self.offline
        self.item = item
        self.offline = offline
        // The same photo culled (not a reused cell): VoiceOver reads the new value.
        if let previous, previous.versionID == item.versionID,
           previous.rating != item.rating || previous.flag != item.flag || previous.colorLabel != item.colorLabel
            || wasOffline != offline {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ratingLayer.contents = Symbols.stars(item.rating.rawValue, color: color(Palette.rating), pointSize: 10)
        // An original's name is its file's; a copy's says which copy it is.
        let name = PhotoName.display(item)
        if nameLayer.string as? String != name {
            nameLayer.string = name
        }
        let badgeText = FileKindText.badge(for: item)
        if badgeText != shownBadgeText {
            shownBadgeText = badgeText
            let badge = Badges.image(badgeText, appearance: effectiveAppearance)
            kindLayer.contents = badge?.image
            kindSize = badge?.size ?? .zero
            positionInfo()
        }
        switch item.flag {
        case .picked:
            flagLayer.contents = Symbols.image("flag.fill", color: color(Palette.pick), pointSize: 11)
            flagLayer.isHidden = false
        case .rejected:
            flagLayer.contents = Symbols.image("xmark.circle.fill", color: color(Palette.reject), pointSize: 11)
            flagLayer.isHidden = false
        case .none:
            flagLayer.contents = nil
            flagLayer.isHidden = true
        }
        // The label's name too, not only its color.
        toolTip = item.colorLabel == .none ? nil : PhotoAccessibility.text(.colorLabel(item.colorLabel))
        if let label = Palette.color(for: item.colorLabel) {
            labelLayer.backgroundColor = color(label).cgColor
            labelLayer.isHidden = false
        } else {
            labelLayer.isHidden = true
        }
        offlineLayer.isHidden = !offline
        copyLayer.isHidden = !item.isCopy
        imageLayer.opacity = item.flag == .rejected ? 0.35 : 1
        // Only the label moves with the flag; a full layout pass per configured
        // cell showed up in fast-scroll profiles.
        positionLabel()
        CATransaction.commit()
    }

    /// The copy mark is drawn, and where in the cell (debug scripts).
    var showsCopyMark: Bool { !copyLayer.isHidden }
    var copyMarkFrame: CGRect { copyLayer.frame }

    func setImage(_ image: CGImage?, animated: Bool) {
        self.image = image
        unavailable = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated, image != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.12
            imageLayer.add(fade, forKey: "contents")
        }
        imageLayer.contents = image
        placeholderLayer.isHidden = image != nil
        placeholderLayer.backgroundColor = color(Palette.cellSelected).cgColor
        CATransaction.commit()
    }

    func showUnavailable() {
        unavailable = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.isHidden = false
        placeholderLayer.backgroundColor = color(Palette.cell).cgColor
        CATransaction.commit()
    }

    private func updateChrome() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color(isSelected ? Palette.cellSelected : Palette.cell).cgColor
        nameLayer.foregroundColor = color(Palette.fileName).cgColor
        layer.borderWidth = isSelected ? PaletteSpec.selectedBorderWidth(in: PaletteAppearance(effectiveAppearance)) : 0
        layer.borderColor = NSColor.controlAccentColor.cgColor
        CATransaction.commit()
    }

    /// A palette color as this cell's appearance shows it (layers do not follow it).
    private func color(_ dynamic: NSColor) -> NSColor {
        dynamic.resolved(for: effectiveAppearance)
    }

    /// Increase Contrast, or the window's appearance, changed: redraw.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
        shownBadgeText = nil
        if let item { apply(item, offline: offline) }
        if image == nil { placeholderLayer.backgroundColor = color(unavailable ? Palette.cell : Palette.cellSelected).cgColor }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 { onDoubleClick?() }
    }

    // MARK: Accessibility

    // Computed when asked, so configuring cells while scrolling stays cheap.

    override func isAccessibilityElement() -> Bool { item != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { item.map(PhotoAccessibility.label) }
    override func accessibilityValue() -> Any? { item.map { PhotoAccessibility.value(for: $0, offline: offline) } }
    override func isAccessibilitySelected() -> Bool { isSelected }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let item, let model else { return nil }
        return PhotoAccessibility.gridActions(forVersion: item.versionID, model: model)
    }

    /// The keyboard focus of the grid, which VoiceOver follows.
    override func isAccessibilityFocused() -> Bool {
        guard let item, let focused = model?.focusedItem else { return false }
        return focused.versionID == item.versionID
    }

    /// AppKit's default resets alpha, hiding and animations under an animator on
    /// every reuse, a visible share of cell dequeue time in fast-scroll profiles.
    /// This view never changes those, and `PhotoCell` resets what it does change.
    override func prepareForReuse() {}
}
