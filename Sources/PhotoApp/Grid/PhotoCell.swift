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
                guard let self, self.versionID == versionID, self.editStackHash == editStackHash,
                      !(error is CancellationError) else { return }
                self.cellView.showUnavailable()
            }
        }
    }

    var hasImage: Bool { cellView.image != nil }
}

final class PhotoCellView: NSView {
    var onDoubleClick: (() -> Void)?
    private(set) var image: CGImage?

    private let imageLayer = CALayer()
    private let ratingLayer = CATextLayer()
    private let nameLayer = CATextLayer()
    private let kindLayer = CALayer()
    private let flagLayer = CALayer()
    private let labelLayer = CALayer()
    private let offlineLayer = CALayer()
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
        placeholderLayer.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        placeholderLayer.cornerRadius = 3
        ratingLayer.fontSize = 11
        ratingLayer.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        ratingLayer.foregroundColor = Palette.rating.cgColor
        ratingLayer.alignmentMode = .left
        ratingLayer.truncationMode = .end
        nameLayer.fontSize = 11
        nameLayer.font = NSFont.systemFont(ofSize: 11)
        nameLayer.foregroundColor = Palette.fileName.cgColor
        nameLayer.alignmentMode = .left
        nameLayer.truncationMode = .middle
        kindLayer.contentsGravity = .resizeAspect
        labelLayer.cornerRadius = 5
        flagLayer.contentsGravity = .resizeAspect
        offlineLayer.contentsGravity = .resizeAspect
        offlineLayer.contents = Symbols.image("externaldrive.badge.xmark", color: .white, pointSize: 12)
        offlineLayer.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        offlineLayer.cornerRadius = 4

        for sublayer in [placeholderLayer, imageLayer, ratingLayer, nameLayer, kindLayer, flagLayer, labelLayer,
                         offlineLayer] {
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
        for sublayer in [imageLayer, ratingLayer, nameLayer, kindLayer, flagLayer, offlineLayer] {
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
        offlineLayer.frame = NSRect(x: imageFrame.minX + 4, y: imageFrame.maxY - 22, width: 22, height: 18)
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
        self.item = item
        self.offline = offline
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ratingLayer.string = item.rating.rawValue > 0 ? String(repeating: "★", count: item.rating.rawValue) : ""
        if nameLayer.string as? String != item.baseName {
            nameLayer.string = item.baseName
        }
        let badgeText = FileKindText.badge(for: item)
        if badgeText != shownBadgeText {
            shownBadgeText = badgeText
            let badge = Badges.image(badgeText)
            kindLayer.contents = badge?.image
            kindSize = badge?.size ?? .zero
            positionInfo()
        }
        switch item.flag {
        case .picked:
            flagLayer.contents = Symbols.image("flag.fill", color: Palette.pick, pointSize: 11)
            flagLayer.isHidden = false
        case .rejected:
            flagLayer.contents = Symbols.image("xmark.circle.fill", color: Palette.reject, pointSize: 11)
            flagLayer.isHidden = false
        case .none:
            flagLayer.contents = nil
            flagLayer.isHidden = true
        }
        if let color = Palette.color(for: item.colorLabel) {
            labelLayer.backgroundColor = color.cgColor
            labelLayer.isHidden = false
        } else {
            labelLayer.isHidden = true
        }
        offlineLayer.isHidden = !offline
        imageLayer.opacity = item.flag == .rejected ? 0.35 : 1
        // Only the label moves with the flag; a full layout pass per configured
        // cell showed up in fast-scroll profiles.
        positionLabel()
        CATransaction.commit()
    }

    func setImage(_ image: CGImage?, animated: Bool) {
        self.image = image
        unavailable = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated, image != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.12
            imageLayer.add(fade, forKey: "contents")
        }
        imageLayer.contents = image
        placeholderLayer.isHidden = image != nil
        placeholderLayer.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        CATransaction.commit()
    }

    func showUnavailable() {
        unavailable = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.isHidden = false
        placeholderLayer.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        CATransaction.commit()
    }

    private func updateChrome() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = (isSelected ? Palette.cellSelected : Palette.cell).cgColor
        layer.borderWidth = isSelected ? 2 : 0
        layer.borderColor = NSColor.controlAccentColor.cgColor
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 { onDoubleClick?() }
    }

    /// AppKit's default resets alpha, hiding and animations under an animator on
    /// every reuse, a visible share of cell dequeue time in fast-scroll profiles.
    /// This view never changes those, and `PhotoCell` resets what it does change.
    override func prepareForReuse() {}
}

/// SF Symbols rendered once into images layers can use.
@MainActor
enum Symbols {
    private static var cache: [String: CGImage] = [:]

    static func image(_ name: String, color: NSColor, pointSize: CGFloat) -> CGImage? {
        let key = "\(name)|\(color.description)|\(pointSize)"
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return nil }
        var rect = CGRect(origin: .zero, size: symbol.size)
        let image = symbol.cgImage(forProposedRect: &rect, context: nil,
                                   hints: [.ctm: AffineTransform(scale: 2)])
        cache[key] = image
        return image
    }
}

/// Small rounded type badges ("RAW", "JPEG"), rendered once per label.
@MainActor
enum Badges {
    struct Badge {
        let image: CGImage
        /// Size in points.
        let size: CGSize
    }

    private static var cache: [String: Badge] = [:]

    static func image(_ text: String?) -> Badge? {
        guard let text, !text.isEmpty else { return nil }
        if let cached = cache[text] { return cached }
        let font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.badgeText, .kern: 0.4]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let size = CGSize(width: ceil(textSize.width) + 8, height: 13)
        let scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let fill = text.hasPrefix(FileKindText.badge(.raw)) ? Palette.rawBadgeFill : Palette.badgeFill
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 3, cornerHeight: 3,
                               transform: nil))
        context.setFillColor(fill.cgColor)
        context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2 + 0.5))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        let badge = Badge(image: image, size: size)
        cache[text] = badge
        return badge
    }
}
