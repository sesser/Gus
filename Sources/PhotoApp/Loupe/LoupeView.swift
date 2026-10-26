import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Single-photo view: the AppKit canvas with an info bar underneath.
struct LoupeView: View {
    let model: LibraryModel

    var body: some View {
        VStack(spacing: 0) {
            // A video whose original is offline shows its cached poster frame instead.
            if let item = model.focusedItem, item.isVideo, let url = model.sourceURL(for: item) {
                VideoLoupe(model: model, url: url)
                    .id(item.versionID)
            } else {
                LoupeCanvas(model: model)
            }
            LoupeInfoBar(model: model)
        }
        .background(Color(nsColor: Palette.loupeBackground))
    }
}

struct LoupeCanvas: NSViewRepresentable {
    let model: LibraryModel

    func makeCoordinator() -> LoupeController {
        LoupeController(model: model)
    }

    func makeNSView(context: Context) -> LoupeHostView {
        context.coordinator.hostView
    }

    func updateNSView(_ view: LoupeHostView, context: Context) {
        // Reading these registers observation, so focus changes from the keyboard,
        // auto-advance or the grid all land here.
        _ = model.itemsRevision
        context.coordinator.hdrSetting = model.showsHDR
        context.coordinator.show(index: model.focusIndex)
        context.coordinator.showLiveFrame(revision: model.editor.frameRevision, active: model.editor.showsLive)
    }

    static func dismantleNSView(_ view: LoupeHostView, coordinator: LoupeController) {
        coordinator.tearDown()
    }
}

/// Shows one version at fit or 1:1, loading the cached preview first and the full
/// resolution render when zoomed in. Neighbors are preloaded so stepping through
/// a shoot does not wait on decoding.
///
/// On a display with extended dynamic range, an HDR rendition rendered from the
/// master replaces the (SDR) cached preview once it is ready, and 1:1 renders
/// in HDR too.
///
/// While adjustments are being changed, the editor's live frames replace all of
/// these; once the change is saved the loupe loads the new edit's renditions.
@MainActor
final class LoupeController: NSObject {
    enum Zoom { case fit, actualSize }

    /// What the image view shows, from least to most detailed. A load only
    /// replaces a lesser rendition, so a slow SDR preview never hides an HDR one.
    /// Live frames of an edit in progress outrank them all.
    private enum Rendition: Int, Comparable {
        case placeholder, preview, hdrPreview, full, hdrFull, live

        static func < (lhs: Rendition, rhs: Rendition) -> Bool { lhs.rawValue < rhs.rawValue }
        var isHDR: Bool { self == .hdrPreview || self == .hdrFull }
    }

    let model: LibraryModel
    let hostView = LoupeHostView()
    private let scrollView = NSScrollView()
    private let imageView = LoupeImageView()
    /// The version and edit shown; a new edit hash loads new renditions.
    private var shownKey: ShownKey?
    private struct ShownKey: Equatable {
        var versionID: Int64
        var editStackHash: String
    }
    private var shownFrameRevision: Int?
    /// Loads the shown version's renditions again on the next `show`.
    private var reloadsSameKey = false
    private var shownIndex: Int?
    private var zoom: Zoom = .fit
    private var rendition = Rendition.placeholder
    private var loadTask: Task<Void, Never>?
    private var hdrTask: Task<Void, Never>?
    private var fullTask: Task<Void, Never>?
    /// The model's HDR setting as last applied; changing it reloads the photo.
    var hdrSetting = true {
        didSet { if hdrSetting != oldValue { shownKey = nil } }
    }
    private var neighborTasks: [Task<Void, Never>] = []
    private var frameObserver: (any NSObjectProtocol)?
    private var screenObserver: (any NSObjectProtocol)?

    init(model: LibraryModel) {
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: hostView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
        hostView.controller = self
        imageView.onDoubleClick = { [weak self] point in self?.toggleZoom(at: point) }

        scrollView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitIfNeeded() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(didEndMagnify(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(takeFocus(_:)),
                                               name: .browserShouldTakeFocus, object: model)
    }

    @objc private func takeFocus(_ notification: Notification) {
        if model.mode == .loupe { hostView.window?.makeFirstResponder(hostView) }
    }

    func tearDown() {
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()
        model.loupeHDRHeadroom = nil
        model.editor.follow(nil)
        neighborTasks.forEach { $0.cancel() }
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        NotificationCenter.default.removeObserver(self)
    }

    /// The view joined a window: whether HDR can be shown depends on its screen,
    /// so the photo shown before then, and after every move to another screen,
    /// is loaded again.
    func windowDidChange() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        guard let window = hostView.window else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    private func reload() {
        guard let index = shownIndex else { return }
        shownKey = nil
        show(index: index)
    }

    // MARK: Showing a version

    func show(index: Int?) {
        guard let index, model.items.indices.contains(index) else {
            shownKey = nil
            rendition = .placeholder
            display(nil, as: .placeholder)
            model.editor.follow(nil)
            return
        }
        let item = model.items[index]
        shownIndex = index
        model.editor.follow(item)
        let key = ShownKey(versionID: item.versionID, editStackHash: item.editStackHash)
        guard key != shownKey || reloadsSameKey else { return }
        let sameVersion = key.versionID == shownKey?.versionID
        shownKey = key
        reloadsSameKey = false
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()

        let backing = hostView.window?.backingScaleFactor ?? 2
        if let size = item.orientedSize, !sameVersion {
            imageView.setFrameSize(NSSize(width: size.width / backing, height: size.height / backing))
        }
        if rendition == .live, sameVersion {
            // The edit being shown live was saved; its frame stays until the
            // editor hands back to the cached renditions.
            rendition = .live
        } else {
            rendition = .placeholder
            let immediate = immediateImage(for: item)
            // After an edit, the old rendition stays until the new one is there.
            if immediate != nil || !sameVersion {
                display(immediate?.image, as: immediate?.rendition ?? .placeholder)
            }
        }
        if !sameVersion { applyZoom(animated: false) }

        if let request = model.previewRequest(for: item, tier: .preview) {
            let previews = model.previews
            loadTask = Task { [weak self] in
                guard let image = try? await previews.image(for: request, priority: .visible),
                      let self, self.shownKey == key, self.rendition <= .preview else { return }
                if item.orientedSize == nil {
                    self.imageView.setFrameSize(NSSize(width: CGFloat(image.width) / backing,
                                                       height: CGFloat(image.height) / backing))
                    self.applyZoom(animated: false)
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
        preloadNeighbors(of: index)
    }

    /// Whatever is already decoded: the HDR or SDR preview, or an enlarged thumbnail.
    private func immediateImage(for item: CatalogItem) -> (image: CGImage, rendition: Rendition)? {
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

    /// Shows the editor's newest frame while an edit is live, and goes back to
    /// the cached renditions when it is not.
    func showLiveFrame(revision: Int, active: Bool) {
        let editor = model.editor
        guard active, let frame = editor.frame, editor.item?.versionID == shownKey?.versionID else {
            shownFrameRevision = nil
            if rendition == .live {
                rendition = .placeholder
                reloadsSameKey = true
                show(index: shownIndex)
            }
            return
        }
        guard revision != shownFrameRevision else { return }
        shownFrameRevision = revision
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()
        rendition = .live
        imageView.setImage(frame.image.cgImage, extendedRange: false)
        if model.loupeHDRHeadroom != nil { model.loupeHDRHeadroom = nil }
    }

    /// Shows `image` unless something more detailed is already showing.
    private func display(_ image: CGImage?, as kind: Rendition) {
        guard kind >= rendition else { return }
        rendition = kind
        imageView.setImage(image, extendedRange: kind.isHDR)
        let headroom = kind.isHDR ? image?.contentHeadroom : nil
        if model.loupeHDRHeadroom != headroom { model.loupeHDRHeadroom = headroom }
    }

    /// HDR is shown when the setting is on and the window's display has extended
    /// dynamic range (its potential, not the headroom available right now).
    private var hdrAllowed: Bool {
        guard model.showsHDR, let screen = hostView.window?.screen else { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
    }

    private func preloadNeighbors(of index: Int) {
        neighborTasks.forEach { $0.cancel() }
        neighborTasks = []
        let previews = model.previews
        let hdr = hdrAllowed
        for neighbor in [index + 1, index - 1, index + 2] where model.items.indices.contains(neighbor) {
            guard let request = model.previewRequest(for: model.items[neighbor], tier: .preview) else { continue }
            let rendersHDR = hdr && neighbor != index + 2
            neighborTasks.append(Task {
                _ = try? await previews.image(for: request, priority: .prefetch)
                if rendersHDR { _ = try? await previews.hdrImage(for: request, priority: .prefetch) }
            })
        }
    }

    private func loadFullResolution() {
        guard let index = shownIndex, model.items.indices.contains(index), rendition < .full else { return }
        let item = model.items[index]
        guard let request = model.previewRequest(for: item, tier: .preview), request.sourceURL != nil else { return }
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

    // MARK: Zoom

    func toggleZoom(at point: NSPoint? = nil) {
        zoom = zoom == .fit ? .actualSize : .fit
        applyZoom(animated: true, centeredAt: point)
        if zoom == .actualSize { loadFullResolution() }
    }

    private var fitMagnification: CGFloat {
        let clip = scrollView.contentView.bounds.size
        let document = imageView.frame.size
        guard document.width > 0, document.height > 0, clip.width > 0 else { return 1 }
        let clipSize = scrollView.frame.size
        return min(clipSize.width / document.width, clipSize.height / document.height, 1)
    }

    private func applyZoom(animated: Bool, centeredAt point: NSPoint? = nil) {
        let target: CGFloat = zoom == .fit ? fitMagnification : 1
        let center = point ?? NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        imageView.usesNearestFiltering = target >= 1
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                scrollView.animator().setMagnification(target, centeredAt: center)
            }
        } else {
            scrollView.setMagnification(target, centeredAt: center)
        }
    }

    private func fitIfNeeded() {
        if zoom == .fit { applyZoom(animated: false) }
    }

    @objc private func didEndMagnify(_ notification: Notification) {
        imageView.usesNearestFiltering = scrollView.magnification >= 1
        // Pinching past the preview's resolution switches to the full render.
        if scrollView.magnification > fitMagnification * 1.05 {
            zoom = .actualSize
            loadFullResolution()
        } else {
            zoom = .fit
        }
    }

    // MARK: Keys

    func handle(_ event: NSEvent) -> Bool {
        if let action = CullingKeymap.action(for: event) {
            model.perform(action)
            return true
        }
        if event.charactersIgnoringModifiers == "\\", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            model.editor.toggleOriginal()
            return true
        }
        switch NavigationKey.from(event) {
        case .left, .up: model.moveFocus(by: -1)
        case .right, .down: model.moveFocus(by: 1)
        case .home: model.setFocus(0)
        case .end: model.setFocus(model.items.count - 1)
        case .toggleLoupe, .exitLoupe: model.closeLoupe()
        case .toggleZoom: toggleZoom()
        case .pageUp, .pageDown, nil: return false
        }
        return true
    }
}

final class LoupeHostView: NSView {
    weak var controller: LoupeController?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if controller?.handle(event) != true { super.keyDown(with: event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        controller?.windowDidChange()
    }
}

/// The document view: one layer showing the image stretched to the view's bounds,
/// which always have the image's aspect ratio. Drag to pan.
final class LoupeImageView: NSView {
    var onDoubleClick: ((NSPoint) -> Void)?
    private var dragOrigin: NSPoint?

    var usesNearestFiltering = false {
        didSet { layer?.magnificationFilter = usesNearestFiltering ? .nearest : .linear }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    /// `extendedRange` lets the layer show values above SDR white; it costs power,
    /// so it is only on while an HDR image is shown.
    func setImage(_ image: CGImage?, extendedRange: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        if let layer {
            if #available(macOS 26.0, *) {
                layer.preferredDynamicRange = extendedRange ? .high : .standard
            } else {
                layer.wantsExtendedDynamicRangeContent = extendedRange
            }
        }
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
            return
        }
        dragOrigin = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let clip = enclosingScrollView?.contentView else { return }
        let location = event.locationInWindow
        let magnification = enclosingScrollView?.magnification ?? 1
        var bounds = clip.bounds.origin
        bounds.x -= (location.x - origin.x) / magnification
        bounds.y -= (location.y - origin.y) / magnification
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: bounds, size: clip.bounds.size)).origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
        dragOrigin = location
    }

    override func mouseUp(with event: NSEvent) {
        if dragOrigin != nil { NSCursor.pop() }
        dragOrigin = nil
    }
}

/// Keeps a document smaller than the viewport centered in it.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
        if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
        return rect
    }
}

/// File name, capture details and culling state of the photo in the loupe.
struct LoupeInfoBar: View {
    let model: LibraryModel
    @State private var details: VersionDetails?

    var body: some View {
        HStack(spacing: 16) {
            if let item = model.focusedItem {
                CullingBadges(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let details {
                        Text(Self.captureLine(details))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if model.editor.showsOriginal {
                    Text("Original")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.2)))
                        .help("Showing the photo without adjustments. Press \\ to show them again.")
                }
                if let headroom = model.loupeHDRHeadroom {
                    Text("HDR")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary))
                        .help("Highlights up to \(headroom.formatted(.number.precision(.fractionLength(1))))× SDR white are shown with the display's extended range")
                }
                if let details {
                    Text(Self.exposureLine(details.image))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if model.isOffline(item) {
                    Label("Original offline", systemImage: "externaldrive.badge.xmark")
                        .foregroundStyle(.orange)
                        .help("The volume \(model.volumeName(for: item) ?? "") is not connected. Showing the cached preview.")
                }
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(white: 0.11))
        .task(id: model.focusedItem?.versionID) {
            guard let id = model.focusedItem?.versionID else { details = nil; return }
            details = try? await model.catalog.details(forVersion: id)
        }
    }

    static func captureLine(_ details: VersionDetails) -> String {
        var parts: [String] = []
        let image = details.image
        if let date = captureDateText(image) { parts.append(date) }
        if let camera = [image.cameraMake, image.cameraModel].compactMap({ $0 }).joined(separator: " ").nilIfEmpty {
            parts.append(camera)
        }
        if let lens = image.lensModel { parts.append(lens) }
        if let width = image.pixelWidth, let height = image.pixelHeight {
            parts.append(String(localized: "\(width) × \(height) px"))
        }
        return parts.joined(separator: "  ·  ")
    }

    static func captureDateText(_ image: ImageRecord) -> String? {
        guard let date = image.captureDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        // Times without an offset are floating local times stored as UTC.
        formatter.timeZone = image.captureOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func exposureLine(_ image: ImageRecord) -> String {
        var parts: [String] = []
        if let time = image.exposureTime, time > 0 {
            let duration = time < 1 ? "1/\(Int((1 / time).rounded()))" : time.formatted(.number.precision(.fractionLength(0...1)))
            parts.append(String(localized: "\(duration) s", comment: "Exposure time in seconds"))
        }
        if let aperture = image.fNumber {
            parts.append(String(localized: "ƒ/\(aperture.formatted(.number.precision(.fractionLength(0...1))))"))
        }
        if let iso = image.iso { parts.append(String(localized: "ISO \(iso)")) }
        if let focal = image.focalLength {
            parts.append(String(localized: "\(Int(focal.rounded())) mm", comment: "Focal length"))
        }
        return parts.joined(separator: "   ")
    }
}

struct CullingBadges: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 6) {
            Text(item.rating.rawValue > 0 ? RatingText.stars(item.rating.rawValue) : "☆")
                .foregroundStyle(item.rating.rawValue > 0 ? Color(nsColor: Palette.rating) : .secondary)
                .frame(minWidth: 64, alignment: .leading)
            switch item.flag {
            case .picked:
                Image(systemName: "flag.fill").foregroundStyle(Color(nsColor: Palette.pick))
                    .help("Picked")
            case .rejected:
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color(nsColor: Palette.reject))
                    .help("Rejected")
            case .none:
                EmptyView()
            }
            if let color = Palette.color(for: item.colorLabel) {
                Circle().fill(Color(nsColor: color)).frame(width: 10, height: 10)
            }
        }
        .font(.callout)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
