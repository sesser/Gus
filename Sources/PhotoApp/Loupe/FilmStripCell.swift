import AppKit
import PhotoCore
import PhotoUI

/// One thumbnail. Loads the `thumbnail` tier at the largest step's size
/// (whatever the step, so a resize never reloads), memory cache first, and
/// cancels the load on reuse.
final class FilmStripCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FilmStripCell")

    weak var controller: FilmStripController?
    private let cellView = FilmStripCellView()
    private var loadTask: Task<Void, Never>?
    private var versionID: Int64?
    private var editStackHash: String?
    /// The pixel size the shown image was loaded for.
    private var loadedPixelSize = 0

    override func loadView() {
        view = cellView
        cellView.onPress = { [weak self] in
            guard let self else { return }
            self.controller?.cellWasClicked(self)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad()
        versionID = nil
        editStackHash = nil
        loadedPixelSize = 0
        cellView.setImage(nil, animated: false)
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    func configure(with item: CatalogItem, model: LibraryModel, isFocused: Bool, pixelSize: Int) {
        let isNewItem = versionID != item.versionID
        let isNewRendition = isNewItem || editStackHash != item.editStackHash
        versionID = item.versionID
        editStackHash = item.editStackHash
        cellView.apply(item, offline: model.isOffline(item), isFocused: isFocused)
        guard isNewRendition || cellView.image == nil || pixelSize > loadedPixelSize else { return }

        cancelLoad()
        guard let request = model.previewRequest(for: item, tier: .thumbnail) else { return }
        if let image = model.previews.memoryCachedImage(for: request, maxPixelSize: pixelSize) {
            loadedPixelSize = pixelSize
            cellView.setImage(image, animated: false)
            return
        }
        if isNewItem { cellView.setImage(nil, animated: false) }
        let previews = model.previews
        let versionID = item.versionID
        let editStackHash = item.editStackHash
        loadTask = Task { [weak self] in
            guard let image = try? await previews.image(for: request, maxPixelSize: pixelSize, priority: .visible),
                  let self, self.versionID == versionID, self.editStackHash == editStackHash else { return }
            self.loadedPixelSize = pixelSize
            self.cellView.setImage(image, animated: true)
        }
    }
}

/// Draws a thumbnail with plain layers: the cell fill (and the focused
/// look), the image fitted inside, and the marks on small dark backings.
final class FilmStripCellView: NSView {
    var onPress: (() -> Void)?
    private(set) var image: CGImage?

    private let imageLayer = CALayer()
    /// Bottom-trailing: the flag and the label's dot.
    private let cullingBacking = CALayer()
    private let flagLayer = CALayer()
    private let labelLayer = CALayer()
    /// Bottom-leading: a video's glyph.
    private let videoBacking = CALayer()
    private let videoLayer = CALayer()
    /// Top-leading: the master's volume is offline.
    private let offlineBacking = CALayer()
    private let offlineLayer = CALayer()
    /// Top-trailing, the one corner left: a copy made with Duplicate.
    private let copyBacking = CALayer()
    private let copyLayer = CALayer()

    private var item: CatalogItem?
    private var offline = false
    private var isFocused = false
    private var glyphSizes: [ObjectIdentifier: CGSize] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        layer.cornerRadius = FilmStripMetrics.cellCornerRadius
        layer.masksToBounds = true
        layer.actions = PhotoCellView.noActions

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.minificationFilter = .trilinear
        labelLayer.cornerRadius = FilmStripMetrics.labelDotSize / 2
        for backing in [cullingBacking, videoBacking, offlineBacking, copyBacking] {
            backing.backgroundColor = Palette.filmStripMarkBacking.cgColor
            backing.cornerRadius = FilmStripMetrics.markCornerRadius
        }
        for glyph in [flagLayer, videoLayer, offlineLayer, copyLayer] {
            glyph.contentsGravity = .resizeAspect
        }
        cullingBacking.addSublayer(flagLayer)
        cullingBacking.addSublayer(labelLayer)
        videoBacking.addSublayer(videoLayer)
        offlineBacking.addSublayer(offlineLayer)
        copyBacking.addSublayer(copyLayer)
        for sublayer in [imageLayer, cullingBacking, flagLayer, labelLayer, videoBacking, videoLayer, offlineBacking,
                         offlineLayer, copyBacking, copyLayer] {
            sublayer.actions = PhotoCellView.noActions
        }
        for sublayer in [imageLayer, cullingBacking, videoBacking, offlineBacking, copyBacking] {
            layer.addSublayer(sublayer)
        }
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [imageLayer, flagLayer, videoLayer, offlineLayer, copyLayer] {
            sublayer.contentsScale = scale
        }
    }

    func apply(_ item: CatalogItem, offline: Bool, isFocused: Bool) {
        let previous = self.item
        let wasOffline = self.offline
        let wasFocused = self.isFocused
        self.item = item
        self.offline = offline
        self.isFocused = isFocused
        // The same photo culled: VoiceOver reads the new value.
        if let previous, previous.versionID == item.versionID,
           previous.flag != item.flag || previous.colorLabel != item.colorLabel || previous.rating != item.rating
            || wasOffline != offline {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        let value = PhotoAccessibility.value(for: item, offline: offline)
        let label = PhotoAccessibility.label(for: item)
        toolTip = value.isEmpty ? label : label + " · " + value
        if wasFocused != isFocused { updateChrome() }
        updateMarks()
        needsLayout = true
    }

    private func updateMarks() {
        guard let item else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let glyph = FilmStripMetrics.markGlyphSize
        switch item.flag {
        case .picked:
            setGlyph(Symbols.image("flag.fill", color: color(Palette.pick), pointSize: glyph), on: flagLayer)
        case .rejected:
            setGlyph(Symbols.image("xmark.circle.fill", color: color(Palette.reject), pointSize: glyph), on: flagLayer)
        case .none:
            setGlyph(nil, on: flagLayer)
        }
        flagLayer.isHidden = item.flag == .none
        if let label = Palette.color(for: item.colorLabel) {
            labelLayer.backgroundColor = color(label).cgColor
            labelLayer.isHidden = false
        } else {
            labelLayer.isHidden = true
        }
        cullingBacking.isHidden = flagLayer.isHidden && labelLayer.isHidden
        setGlyph(item.isVideo ? Symbols.image("video.fill", color: .white, pointSize: glyph) : nil, on: videoLayer)
        videoBacking.isHidden = !item.isVideo
        setGlyph(offline ? Symbols.image("externaldrive.badge.xmark", color: .white, pointSize: glyph) : nil,
                 on: offlineLayer)
        offlineBacking.isHidden = !offline
        setGlyph(item.isCopy ? Symbols.image(PhotoCellView.copySymbol, color: .white, pointSize: glyph) : nil, on: copyLayer)
        copyBacking.isHidden = !item.isCopy
        imageLayer.opacity = item.flag == .rejected ? FilmStripMetrics.rejectedOpacity : 1
        CATransaction.commit()
    }

    /// The copy mark is drawn (debug scripts).
    var showsCopyMark: Bool { !copyBacking.isHidden }

    func setImage(_ image: CGImage?, animated: Bool) {
        self.image = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated, image != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = FilmStripMetrics.fadeDuration
            imageLayer.add(fade, forKey: "contents")
        }
        imageLayer.contents = image
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let padding = FilmStripGeometry.imagePadding
        let area = bounds.insetBy(dx: padding, dy: padding)
        imageLayer.frame = area
        // Marks sit on the image's corners, which aspect-fitting moves in.
        let picture = Self.fitted(aspect: imageAspect, in: area)
        let inset = FilmStripMetrics.markInset
        let pad = FilmStripMetrics.markPadding

        // Flag, then the label's dot, bottom-trailing.
        let flagSize = glyphSize(flagLayer)
        let dot = FilmStripMetrics.labelDotSize
        var width = pad * 2
        var height = dot
        if !flagLayer.isHidden {
            width += flagSize.width
            height = max(height, flagSize.height)
        }
        if !labelLayer.isHidden { width += dot + (flagLayer.isHidden ? 0 : FilmStripMetrics.markGap) }
        height += pad * 2
        cullingBacking.frame = NSRect(x: picture.maxX - inset - width, y: picture.minY + inset, width: width, height: height)
        flagLayer.frame = NSRect(x: pad, y: (height - flagSize.height) / 2, width: flagSize.width, height: flagSize.height)
        labelLayer.frame = NSRect(x: width - pad - dot, y: (height - dot) / 2, width: dot, height: dot)

        let videoSize = glyphSize(videoLayer)
        videoBacking.frame = NSRect(x: picture.minX + inset, y: picture.minY + inset,
                                    width: videoSize.width + pad * 2, height: videoSize.height + pad * 2)
        videoLayer.frame = NSRect(x: pad, y: pad, width: videoSize.width, height: videoSize.height)

        let offlineSize = glyphSize(offlineLayer)
        let offlineHeight = offlineSize.height + pad * 2
        offlineBacking.frame = NSRect(x: picture.minX + inset, y: picture.maxY - inset - offlineHeight,
                                      width: offlineSize.width + pad * 2, height: offlineHeight)
        offlineLayer.frame = NSRect(x: pad, y: pad, width: offlineSize.width, height: offlineSize.height)

        let copySize = glyphSize(copyLayer)
        let copyWidth = copySize.width + pad * 2
        let copyHeight = copySize.height + pad * 2
        copyBacking.frame = NSRect(x: picture.maxX - inset - copyWidth, y: picture.maxY - inset - copyHeight,
                                   width: copyWidth, height: copyHeight)
        copyLayer.frame = NSRect(x: pad, y: pad, width: copySize.width, height: copySize.height)
        CATransaction.commit()
    }

    /// The image's width over height: the loaded image's, else the photo's.
    private var imageAspect: CGFloat {
        if let image, image.height > 0 { return CGFloat(image.width) / CGFloat(image.height) }
        if let size = item?.orientedSize, size.height > 0 { return size.width / size.height }
        return 1
    }

    static func fitted(aspect: CGFloat, in area: NSRect) -> NSRect {
        guard aspect > 0, area.width > 0, area.height > 0 else { return area }
        if aspect >= area.width / area.height {
            let height = area.width / aspect
            return NSRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height)
        }
        let width = area.height * aspect
        return NSRect(x: area.midX - width / 2, y: area.minY, width: width, height: area.height)
    }

    /// A mark's glyph, with its size in points (`Symbols` renders at 2×).
    private func setGlyph(_ image: CGImage?, on layer: CALayer) {
        layer.contents = image
        glyphSizes[ObjectIdentifier(layer)] = image.map { CGSize(width: CGFloat($0.width) / 2,
                                                                 height: CGFloat($0.height) / 2) }
    }

    private func glyphSize(_ layer: CALayer) -> CGSize {
        glyphSizes[ObjectIdentifier(layer)] ?? .zero
    }

    private func updateChrome() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color(isFocused ? Palette.cellSelected : Palette.cell).cgColor
        layer.borderWidth = isFocused ? PaletteSpec.selectedBorderWidth(in: PaletteAppearance(effectiveAppearance)) : 0
        layer.borderColor = NSColor.controlAccentColor.cgColor
        CATransaction.commit()
    }

    /// A palette color as this cell's appearance shows it (layers do not follow it).
    private func color(_ dynamic: NSColor) -> NSColor {
        dynamic.resolved(for: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
        updateMarks()
    }

    // MARK: Mouse

    // A click focuses the photo; a double-click is two clicks. No drag,
    // selection, hover or context menu.
    override func mouseDown(with event: NSEvent) {
        onPress?()
    }

    override func rightMouseDown(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { item != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { item.map(PhotoAccessibility.label) }
    override func accessibilityValue() -> Any? { item.map { PhotoAccessibility.value(for: $0, offline: offline) } }
    override func isAccessibilitySelected() -> Bool { isFocused }

    override func accessibilityPerformPress() -> Bool {
        guard item != nil else { return false }
        onPress?()
        return true
    }

    /// The cell keeps no reuse state AppKit's default would reset; see `PhotoCellView`.
    override func prepareForReuse() {}
}
