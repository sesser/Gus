import AppKit
import PhotoCore

/// One shot in the import grid, built to the library cell's measurements
/// (`PhotoCellView`): corner radius 6, padding 6, the palette's cell fill, an
/// 11 pt name with the `Badges` type badge, and a 10 pt date line under it.
/// A system check box at top-leading says whether it is imported (section 8
/// of docs/UI_REDESIGN.md, decision 18).
final class ImportCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImportCell")

    private let cellView = ImportCellView()
    private var loadTask: Task<Void, Never>?
    private(set) var shotID: URL?

    override func loadView() {
        view = cellView
    }

    var onClick: ((NSEvent) -> Void)? {
        get { cellView.onClick }
        set { cellView.onClick = newValue }
    }

    /// VoiceOver's press, and the check box.
    var onToggle: (() -> Void)? {
        get { cellView.onToggle }
        set { cellView.onToggle = newValue }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        shotID = nil
        cellView.setImage(nil)
    }

    func configure(with shot: SourceShot, included: Bool, colorSpace: CGColorSpace?, pixelSize: Int) {
        let isNew = shotID != shot.id
        shotID = shot.id
        cellView.apply(shot, included: included)
        guard isNew || cellView.image == nil else { return }
        loadTask?.cancel()
        let url = shot.primary.url
        loadTask = Task { [weak self] in
            let image = await SourceThumbnails.shared.thumbnail(for: url, pixelSize: pixelSize, colorSpace: colorSpace)
            guard let self, !Task.isCancelled, self.shotID == shot.id else { return }
            self.cellView.setImage(image)
        }
    }
}

final class ImportCellView: NSView {
    var onClick: ((NSEvent) -> Void)?
    var onToggle: (() -> Void)?
    private(set) var image: CGImage?

    private let imageLayer = CALayer()
    private let placeholderLayer = CALayer()
    private let nameLayer = CATextLayer()
    private let kindLayer = CALayer()
    private let dateLayer = CATextLayer()
    /// The dark rounded square behind the check box, or the In Library badge.
    private let backingLayer = CALayer()
    private let inLibraryLayer = CALayer()
    private let checkBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private var shot: SourceShot?
    private var included = false
    private(set) var dateText = ""
    private var kindSize = CGSize.zero
    private var inLibrarySize = CGSize.zero
    private var shownBadge: String?

    static let padding: CGFloat = 6
    static let infoHeight: CGFloat = 16
    static let dateHeight: CGFloat = 14
    static let backing: CGFloat = 20

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
        placeholderLayer.cornerRadius = 3
        nameLayer.fontSize = 11
        nameLayer.font = NSFont.systemFont(ofSize: 11)
        nameLayer.alignmentMode = .left
        nameLayer.truncationMode = .middle
        dateLayer.fontSize = 10
        dateLayer.font = NSFont.systemFont(ofSize: 10)
        dateLayer.alignmentMode = .left
        dateLayer.truncationMode = .end
        kindLayer.contentsGravity = .resizeAspect
        inLibraryLayer.contentsGravity = .resizeAspect
        // The library cell's offline marker uses the same dark backing.
        backingLayer.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
        backingLayer.cornerRadius = 4
        for sublayer in [placeholderLayer, imageLayer, nameLayer, kindLayer, dateLayer, backingLayer, inLibraryLayer] {
            sublayer.actions = Self.noActions
            layer.addSublayer(sublayer)
        }

        // The cell is the check box to VoiceOver; the button only draws it.
        checkBox.setAccessibilityElement(false)
        checkBox.refusesFirstResponder = true
        checkBox.controlSize = .regular
        addSubview(checkBox)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    static let noActions: [String: any CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(),
        "opacity": NSNull(), "backgroundColor": NSNull(), "string": NSNull(), "foregroundColor": NSNull(),
        "frame": NSNull(),
    ]

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [imageLayer, nameLayer, kindLayer, dateLayer, inLibraryLayer] {
            sublayer.contentsScale = scale
        }
    }

    /// Clicks anywhere toggle the shot, the check box included: the grid
    /// handles them, so ⇧-click works the same everywhere.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(event)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let padding = Self.padding
        let strip = Self.infoHeight + Self.dateHeight
        let imageFrame = NSRect(x: padding, y: padding + strip, width: bounds.width - padding * 2,
                                height: bounds.height - padding * 2 - strip)
        imageLayer.frame = imageFrame
        placeholderLayer.frame = imageFrame.insetBy(dx: imageFrame.width * 0.08, dy: imageFrame.height * 0.08)
        dateLayer.frame = NSRect(x: padding + 2, y: padding, width: bounds.width - padding * 2 - 4, height: Self.dateHeight - 1)
        positionInfo()
        positionMarks(imageFrame)
        CATransaction.commit()
    }

    private func positionInfo() {
        let padding = Self.padding
        let rowY = padding + Self.dateHeight
        kindLayer.frame = NSRect(x: bounds.width - padding - 2 - kindSize.width,
                                 y: rowY + (Self.infoHeight - kindSize.height) / 2,
                                 width: kindSize.width, height: kindSize.height)
        nameLayer.frame = NSRect(x: padding + 2, y: rowY, width: max(0, kindLayer.frame.minX - padding - 6),
                                 height: Self.infoHeight - 1)
    }

    /// The check box on its backing at the image's top-leading corner, or the
    /// In Library badge in its place.
    private func positionMarks(_ imageFrame: NSRect) {
        let isDuplicate = shot?.isDuplicate == true
        let origin = NSPoint(x: imageFrame.minX + 4, y: imageFrame.maxY - 4 - Self.backing)
        if isDuplicate {
            backingLayer.frame = NSRect(x: origin.x, y: origin.y, width: inLibrarySize.width + 8, height: Self.backing)
            inLibraryLayer.frame = NSRect(x: origin.x + 4, y: origin.y + (Self.backing - inLibrarySize.height) / 2,
                                          width: inLibrarySize.width, height: inLibrarySize.height)
        } else {
            backingLayer.frame = NSRect(origin: origin, size: NSSize(width: Self.backing, height: Self.backing))
            let size = checkBox.fittingSize
            checkBox.frame = NSRect(x: origin.x + (Self.backing - size.width) / 2, y: origin.y + (Self.backing - size.height) / 2,
                                    width: size.width, height: size.height)
        }
    }

    func apply(_ shot: SourceShot, included: Bool) {
        let changed = self.shot?.id == shot.id && self.included != included
        self.shot = shot
        self.included = included
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let name = (shot.primary.name as NSString).deletingPathExtension
        if nameLayer.string as? String != name { nameLayer.string = name }
        dateText = Self.dateText(shot)
        if dateLayer.string as? String != dateText { dateLayer.string = dateText }
        let badge = shot.files.map { FileKindText.badge($0.kind) }.joined(separator: "+")
        if badge != shownBadge {
            shownBadge = badge
            let image = Badges.image(badge, appearance: effectiveAppearance)
            kindLayer.contents = image?.image
            kindSize = image?.size ?? .zero
            positionInfo()
        }
        checkBox.isHidden = shot.isDuplicate
        checkBox.state = included ? .on : .off
        inLibraryLayer.isHidden = !shot.isDuplicate
        if shot.isDuplicate {
            let image = Badges.image(Self.inLibraryText, appearance: NSAppearance(named: .darkAqua) ?? effectiveAppearance)
            inLibraryLayer.contents = image?.image
            inLibrarySize = image?.size ?? .zero
        }
        // Left out, or already in the library: the image at 50%.
        imageLayer.opacity = shot.isDuplicate || !included ? 0.5 : 1
        toolTip = shot.isDuplicate ? Self.alreadyInLibrary : shot.files.map(\.name).joined(separator: " + ")
        positionMarks(imageLayer.frame)
        CATransaction.commit()
        if changed { NSAccessibility.post(element: self, notification: .valueChanged) }
    }

    func setImage(_ image: CGImage?) {
        self.image = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        placeholderLayer.isHidden = image != nil
        CATransaction.commit()
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = Palette.cell.resolved(for: effectiveAppearance).cgColor
        placeholderLayer.backgroundColor = Palette.cellSelected.resolved(for: effectiveAppearance).cgColor
        nameLayer.foregroundColor = Palette.fileName.resolved(for: effectiveAppearance).cgColor
        dateLayer.foregroundColor = Palette.dateText.resolved(for: effectiveAppearance).cgColor
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        shownBadge = nil
        if let shot { apply(shot, included: included) }
    }

    static var inLibraryText: String {
        String(localized: "In Library", comment: "Import grid badge: the shot is already in the library")
    }

    static var alreadyInLibrary: String {
        String(localized: "Already in the library")
    }

    /// In the capture's own time: cameras usually record local time without a
    /// zone, stored as UTC (see `ImageMetadata.captureDate`).
    static func dateText(_ shot: SourceShot) -> String {
        let metadata = shot.primary.metadata
        var style = Date.FormatStyle.dateTime.day().month().hour().minute()
        if metadata.captureDate != nil {
            style.timeZone = metadata.captureOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? TimeZone(secondsFromGMT: 0)!
        }
        return shot.date.formatted(style)
    }

    // MARK: Accessibility

    // A check box: "DSC00328, RAW plus JPEG, Oct 30, 10:46 AM", checked when
    // it is imported; a shot already in the library says so.

    override func isAccessibilityElement() -> Bool { shot != nil }

    override func accessibilityRole() -> NSAccessibility.Role? {
        shot?.isDuplicate == true ? .image : .checkBox
    }

    override func accessibilityLabel() -> String? {
        guard let shot else { return nil }
        return AccessibilityText.list([(shot.primary.name as NSString).deletingPathExtension,
                                       AccessibilityText.fileType(shot.files.map(\.kind)), Self.dateText(shot)])
    }

    override func accessibilityValue() -> Any? {
        guard let shot else { return nil }
        return shot.isDuplicate ? Self.alreadyInLibrary : NSNumber(value: included ? 1 : 0)
    }

    override func accessibilityPerformPress() -> Bool {
        guard shot?.isDuplicate == false else { return false }
        onToggle?()
        return true
    }

    override func prepareForReuse() {}
}

/// Thumbnails of source files from their embedded previews (no RAW decoding
/// when the file has one), decoded and converted to the window's color space
/// off the main thread, and kept while the app runs (up to a bound).
actor SourceThumbnails {
    static let shared = SourceThumbnails()
    private var cache: [URL: CGImage] = [:]
    private static let limit = 4000

    func thumbnail(for url: URL, pixelSize: Int, colorSpace: CGColorSpace?) async -> CGImage? {
        if let cached = cache[url], cached.width >= pixelSize || cached.height >= pixelSize { return cached }
        var image: CGImage?
        if FileKind(pathExtension: url.pathExtension) == .video {
            image = try? await VideoFrames.poster(of: url, longEdge: pixelSize)
        } else {
            image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
                else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
        }
        // Converted before it reaches a layer, or Core Animation converts it
        // on the main thread at commit.
        if let decoded = image, let colorSpace {
            image = await Task.detached(priority: .userInitiated) {
                PreviewDiskCache.converted(decoded, to: colorSpace) ?? decoded
            }.value
        }
        if let image {
            if cache.count > Self.limit { cache.removeAll() }
            cache[url] = image
        }
        return image
    }
}
