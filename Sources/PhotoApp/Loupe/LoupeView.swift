import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// Single-photo view: the AppKit canvas (or the video loupe), the film strip
/// (section 11 of docs/UI_REDESIGN.md), which review mode never shows, and
/// the caption at the bottom edge. While comparing
/// (docs/features/side-by-side-comparison) two panes take the canvas's
/// place and the caption is split at their seam.
struct LoupeView: View {
    let model: LibraryModel
    /// The loupe's whole height, for the strip's height cap.
    @State private var height: CGFloat = 0
    @State private var stripPresence = FilmStripPresence()

    private var wantsStrip: Bool { model.showsFilmStrip && !model.isReviewing }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !model.isComparing {
                    // A video whose original is offline shows its cached poster frame instead.
                    if let item = model.focusedItem, item.isVideo, let url = model.sourceURL(for: item) {
                        VideoLoupe(model: model, url: url)
                            .id(item.versionID)
                    } else {
                        LoupeCanvas(model: model)
                    }
                }
                // Over the single loupe for the moment its active photo
                // refits to the whole loupe (design §2 "Leaving").
                if model.isComparing || model.comparisonLeaving != nil {
                    ComparisonCanvas(model: model)
                        .allowsHitTesting(model.isComparing)
                }
            }
            if stripPresence.isPresent {
                filmStrip
            }
            if model.isComparing {
                ComparisonCaption(model: model)
            } else {
                LoupeCaption(model: model)
            }
        }
        .background(Color(nsColor: Palette.loupeBackground))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onAppear {
            stripPresence.model = model
            stripPresence.set(shown: wantsStrip, animated: false)
        }
        // The toggle and the menu slide it; review shows and hides it at once.
        .onChange(of: model.showsFilmStrip) { stripPresence.set(shown: wantsStrip, animated: true) }
        .onChange(of: model.isReviewing) { stripPresence.set(shown: wantsStrip, animated: false) }
    }

    /// The layout reserves the settled step's height (the canvas refits when
    /// that changes); the strip's view reaches above it for the handle and
    /// for drags, over the canvas's bottom margin.
    private var filmStrip: some View {
        let geometry = FilmStripGeometry(storedSize: model.filmStripSize, loupeHeight: Double(height))
        return Color.clear
            .frame(height: stripPresence.reservesSpace ? CGFloat(geometry.stripHeight) : 0)
            .overlay(alignment: .bottom) {
                FilmStripView(model: model, presence: stripPresence, geometry: geometry, loupeHeight: Double(height))
                    .frame(height: FilmStripView.frameHeight(loupeHeight: Double(height)))
            }
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
        context.coordinator.showCrop(model.editor.cropSession, image: model.editor.cropImage)
        context.coordinator.showMasks()
        // Part of the canvas's VoiceOver value (ml-denoise design §8).
        _ = model.editor.machineLearningNotApplied
        // The pixel magnifier follows these, as well as the pointer (design §20).
        _ = (model.editor.fringeSamplePixels?.byteCount, model.pixelMagnifierLevel, model.isWindowKey)
        context.coordinator.updateAccessibility()
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

    /// What the image view shows (`LoupeRendition`, shared with the
    /// comparison's panes).
    private typealias Rendition = LoupeRendition

    let model: LibraryModel
    let hostView = LoupeHostView()
    private let scrollView = LoupeScrollView()
    private let imageView = LoupeImageView()
    /// The picking slot the cursor rects were last made for.
    private var pickingSlotShown: Int?
    private var escapeMonitor: Any?
    private let magnifierView = PixelMagnifierView()
    /// Where the pointer is over the canvas, from mouse events; a level
    /// chosen in a menu keeps the magnifier where it was (design §20).
    private var magnifierPointer: NSPoint?
    /// The debug script's pointer: output unit coordinates, until a real move.
    private var magnifierDebugUnit: CGPoint?
    private var magnifierPlacement: PixelMagnifierPlacement?
    /// When the magnifier began waiting for pixels (its spinner after 0.5 s).
    private var magnifierSpinnerTask: Task<Void, Never>?
    /// What the magnifier shows, for the debug script.
    private(set) var magnifierState = MagnifierState()
    private let cropView = CropOverlayView()
    private let maskView = MaskOverlayView()
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
    private var zoom: Zoom = .fit {
        // Zoomed in, live frames are already stretched: drafts would make that worse.
        didSet {
            model.editor.allowsDrafts = zoom == .fit
            model.editor.loupeIsZoomed = zoom != .fit
            publishZoom()
        }
    }
    private var rendition = Rendition.placeholder
    private var loadTask: Task<Void, Never>?
    private var hdrTask: Task<Void, Never>?
    private var fullTask: Task<Void, Never>?
    /// Tells the latest full-rendition load from one it replaced.
    private var fullLoadGeneration = 0
    /// The model's HDR setting as last applied; changing it reloads the photo.
    var hdrSetting = true {
        didSet { if hdrSetting != oldValue { shownKey = nil } }
    }
    private var neighborTasks: [Task<Void, Never>] = []
    /// A refit before this time animates (`animateNextFit`).
    private var animatesFitUntil = Date.distantPast
    /// The canvas size the photo was last fitted to.
    private var fittedSize = NSSize.zero
    private var frameObserver: (any NSObjectProtocol)?
    private var screenObserver: (any NSObjectProtocol)?

    init(model: LibraryModel) {
        self.model = model
        super.init()
        // A new loupe starts at fit.
        model.editor.loupeIsZoomed = false
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
        cropView.translatesAutoresizingMaskIntoConstraints = false
        cropView.isHidden = true
        hostView.addSubview(cropView)
        NSLayoutConstraint.activate([
            cropView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            cropView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            cropView.topAnchor.constraint(equalTo: hostView.topAnchor),
            cropView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
        maskView.frame = imageView.bounds
        maskView.autoresizingMask = [.width, .height]
        maskView.editor = model.editor
        imageView.addSubview(maskView)
        cropView.onChangeRect = { [weak self] rect in self?.model.editor.setCropRect(rect) }
        cropView.onStraighten = { [weak self] angle, phase in self?.model.editor.straighten(angle, phase: phase) }
        hostView.controller = self
        scrollView.onClick = { [weak self] point in self?.toggleZoom(at: point) }
        scrollView.onDoubleClick = { [weak self] in self?.model.closeLoupe() }
        // While a fringe slot picks, a click picks at once instead of zooming
        // (chromatic-aberration design §4); drags still pan.
        scrollView.isPicking = { [weak self] in self?.model.editor.pixelMagnifierIsPicking == true }
        scrollView.onPick = { [weak self] point in self?.pickFringe(at: point) }
        scrollView.onPointerMoved = { [weak self] location in self?.movePointer(toWindowPoint: location) }
        magnifierView.isHidden = true
        hostView.addSubview(magnifierView)
        scrollView.photoRect = { [weak self] in
            guard let self, self.model.editor.pickingFringeSlot != nil else { return nil }
            return self.imageView.bounds
        }
        scrollView.onZoomScroll = { [weak self] factor, point in self?.zoom(by: factor, at: point) }

        scrollView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitIfNeeded() }
        }
        // Pans and zooms under a still pointer update the magnifier (R30).
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleRectChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(didEndMagnify(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(takeFocus(_:)),
                                               name: .browserShouldTakeFocus, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomRequested(_:)),
                                               name: .loupeShouldToggleZoom, object: model)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomStepRequested(_:)),
                                               name: .loupeShouldStepZoom, object: model)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomSetRequested(_:)),
                                               name: .loupeShouldSetZoom, object: model)
        NotificationCenter.default.addObserver(self, selector: #selector(animateNextFit(_:)),
                                               name: .loupeShouldAnimateNextFit, object: model)
    }

    /// The film strip changes the canvas's frame next: that refit animates,
    /// as long as it comes soon (otherwise a later window resize would).
    @objc private func animateNextFit(_ notification: Notification) {
        animatesFitUntil = Date().addingTimeInterval(0.5)
    }

    /// From the model, or from a view in this window (an inspector value field).
    @objc private func takeFocus(_ notification: Notification) {
        guard notification.object as AnyObject? === model || notification.object as AnyObject? === hostView.window else { return }
        if model.mode == .loupe { hostView.window?.makeFirstResponder(hostView) }
    }

    @objc private func zoomRequested(_ notification: Notification) {
        if model.mode == .loupe { toggleZoom() }
    }

    /// The toolbar's Fit / 100%.
    @objc private func zoomSetRequested(_ notification: Notification) {
        guard model.mode == .loupe, let fit = notification.userInfo?[LoupeZoomStep.fitKey] as? Bool else { return }
        zoom = fit ? .fit : .actualSize
        applyZoom(animated: true)
        if !fit { loadFullResolution() }
    }

    @objc private func zoomStepRequested(_ notification: Notification) {
        guard model.mode == .loupe, let zoomIn = notification.userInfo?[LoupeZoomStep.zoomInKey] as? Bool else { return }
        stepZoom(in: zoomIn)
    }

    func tearDown() {
        scrollView.cancelPendingClick()
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()
        model.loupeHDRHeadroom = nil
        model.editor.follow(nil)
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
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
        if !sameVersion {
            scrollView.cancelPendingClick()
            imageView.setTile(nil, unit: .zero)
            model.editor.loupeAwaitsFullRendition = false
            applyZoom(animated: false)
        }

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

    /// Shows the editor's newest frames while an edit is live, and goes back to
    /// the cached renditions when it is not: a whole frame (from the live
    /// session) goes on the base, a region frame goes on the tile over it. The
    /// editor drops the tile when a whole frame stands in for it (a map, a raw
    /// decode on its way); a whole frame of other values never replaces a
    /// tile that is still showing the change (`LiveFrameRules`).
    func showLiveFrame(revision: Int, active: Bool) {
        let editor = model.editor
        guard active, editor.item?.versionID == shownKey?.versionID, editor.frame != nil || editor.regionFrame != nil else {
            shownFrameRevision = nil
            if rendition == .live {
                rendition = .placeholder
                reloadsSameKey = true
                // The tile covers the swap until the full rendition is there;
                // no full load starts at fit (design §2.1, §3).
                editor.loupeAwaitsFullRendition = editor.loupeViewport != nil && zoom == .actualSize
                show(index: shownIndex)
            }
            // The sharp frame of the saved values stays until the full rendition lands.
            if editor.loupeAwaitsFullRendition, editor.loupeViewport != nil, let regionFrame = editor.regionFrame,
               regionFrame.adjustments == editor.savedAdjustments, !editor.showsOriginal,
               editor.item?.versionID == shownKey?.versionID {
                showTile(regionFrame)
            } else if imageView.hasTile {
                imageView.setTile(nil, unit: .zero)
            }
            return
        }
        guard revision != shownFrameRevision else { return }
        shownFrameRevision = revision
        loadTask?.cancel()
        hdrTask?.cancel()
        fullTask?.cancel()
        // A new change: the full rendition just cancelled isn't coming.
        editor.loupeAwaitsFullRendition = false
        rendition = .live
        if model.loupeHDRHeadroom != nil { model.loupeHDRHeadroom = nil }
        if let regionFrame = editor.regionFrame, editor.loupeViewport != nil {
            showTile(regionFrame)
        } else if imageView.hasTile {
            imageView.setTile(nil, unit: .zero)
        }
        if let frame = editor.frame,
           LiveFrameRules.wholeFrameGoesOnBase(wholeValues: frame.adjustments, tileValues: editor.regionFrame?.adjustments) {
            matchFrame(to: frame.image.cgImage, exact: false)
            imageView.setImage(frame.image.cgImage, extendedRange: false)
        }
        updateFiltering()
    }

    /// The sharp frame over the photo. Sized to one output pixel per view
    /// pixel at 100% (the size the full rendition gives the view).
    private func showTile(_ frame: LiveRegionRenderer.Frame) {
        matchFrame(toOutput: frame.outputSize)
        let size = frame.outputSize
        imageView.setTile(frame.image.cgImage, unit: CGRect(x: frame.region.minX / size.width, y: frame.region.minY / size.height,
                                                            width: frame.region.width / size.width, height: frame.region.height / size.height))
    }

    /// The selected mask's handles over the photo; reading the editor here
    /// registers the observation that redraws them.
    func showMasks() {
        let editor = model.editor
        _ = (editor.adjustments.local, editor.selectedMaskID, editor.isBrushing, editor.isSamplingColor,
             editor.maskFrameSize, editor.brushTemplate)
        updateMagnifier()
        // The crosshair over the photo while a fringe slot picks.
        if editor.pickingFringeSlot != pickingSlotShown {
            pickingSlotShown = editor.pickingFringeSlot
            scrollView.window?.invalidateCursorRects(for: scrollView)
            syncEscapeMonitor()
        }
        // Hidden under the sharpening map too: clicks then reach the canvas (zoom, pan), never a mask (R8).
        maskView.isHidden = editor.state != .ready || editor.cropSession != nil || editor.selectedMaskID == nil
            || editor.sharpeningMap.isShown || editor.pickingFringeSlot != nil
        maskView.refresh()
    }

    /// Shows the crop frame over the whole photo while a crop is edited.
    func showCrop(_ session: CropSession?, image: CGImage?) {
        guard let session, let image else {
            if !cropView.isHidden {
                cropView.isHidden = true
                cropView.reset()
                scrollView.isHidden = false
            }
            return
        }
        cropView.configure(session: session, image: image)
        if cropView.isHidden {
            cropView.isHidden = false
            scrollView.isHidden = true
        }
    }

    /// Keeps the image view in the proportions of what it shows, which a crop
    /// or a quarter turn changes. A full-resolution rendition sets its size
    /// exactly; others keep the current long edge.
    private func matchFrame(to image: CGImage?, exact: Bool) {
        guard let image, image.width > 0, image.height > 0 else { return }
        let backing = hostView.window?.backingScaleFactor ?? 2
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
        imageView.setFrameSize(size)
        applyZoom(animated: false)
    }

    /// Keeps the view at one output pixel per view pixel at 100% (a region
    /// frame's output size; `matchFrame(to:exact:)` for a full rendition).
    private func matchFrame(toOutput size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let backing = hostView.window?.backingScaleFactor ?? 2
        let target = NSSize(width: size.width / backing, height: size.height / backing)
        let current = imageView.frame.size
        guard abs(target.width - current.width) > 0.5 || abs(target.height - current.height) > 0.5 else { return }
        // The same place stays in the middle of the view: the swap changes
        // detail, never position (design §3).
        let visible = scrollView.documentVisibleRect
        let center = current.width > 0 && current.height > 0
            ? NSPoint(x: visible.midX / current.width, y: visible.midY / current.height) : NSPoint(x: 0.5, y: 0.5)
        imageView.setFrameSize(target)
        scrollView.setMagnification(scrollView.magnification, centeredAt: NSPoint(x: center.x * target.width, y: center.y * target.height))
        updateLoupeViewport()
    }

    /// Shows `image` unless something more detailed is already showing.
    private func display(_ image: CGImage?, as kind: Rendition) {
        guard kind >= rendition else { return }
        rendition = kind
        matchFrame(to: image, exact: kind == .full || kind == .hdrFull)
        imageView.setImage(image, extendedRange: kind.isHDR)
        let headroom = kind.isHDR ? image?.contentHeadroom : nil
        if model.loupeHDRHeadroom != headroom { model.loupeHDRHeadroom = headroom }
        updateFiltering()
        if kind == .full || kind == .hdrFull {
            // Real pixels of the saved values now under the tile: it has served.
            imageView.setTile(nil, unit: .zero)
            model.editor.loupeAwaitsFullRendition = false
        }
    }

    /// Nearest-neighbor only for real pixels above 100% (design §2.2): a
    /// frame that isn't the photo's own pixels enlarges smoothly, at every zoom.
    private func updateFiltering(magnification known: CGFloat? = nil) {
        let magnification = known ?? scrollView.magnification
        imageView.usesNearestFiltering = LiveFrameRules.usesNearestFiltering(
            magnification: Double(magnification), showsRealPixels: rendition == .full || rendition == .hdrFull,
            keepsShippedFiltering: rendition == .live && model.editor.liveFrameKeepsShippedFiltering)
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
        guard let index = shownIndex, model.items.indices.contains(index), rendition < .full else {
            model.editor.loupeAwaitsFullRendition = false
            return
        }
        let item = model.items[index]
        guard let request = model.previewRequest(for: item, tier: .preview), request.sourceURL != nil else {
            model.editor.loupeAwaitsFullRendition = false
            return
        }
        let previews = model.previews
        let hdr = hdrAllowed
        let key = shownKey
        fullTask?.cancel()
        fullLoadGeneration += 1
        let generation = fullLoadGeneration
        model.editor.loupeLoadsFullRendition = true
        fullTask = Task { [weak self] in
            // The last load to finish, however it ended, lets the texture's decode start.
            defer { if let self, self.fullLoadGeneration == generation { self.model.editor.loupeLoadsFullRendition = false } }
            if hdr, let image = try? await previews.hdrImage(for: request, fullResolution: true) {
                guard let self, self.shownKey == key else { return }
                self.display(image, as: .hdrFull)
                return
            }
            guard let image = try? await previews.fullResolutionImage(for: request) else {
                if !Task.isCancelled { self?.model.editor.loupeAwaitsFullRendition = false }
                return
            }
            guard let self, self.shownKey == key else { return }
            self.display(image, as: .full)
        }
    }

    // MARK: Zoom

    /// A click while a fringe slot picks, at `point` in the photo's view; a
    /// click on the surround does nothing (chromatic-aberration design §4).
    private func pickFringe(at point: NSPoint) {
        guard imageView.bounds.contains(point) else { return }
        let geometry = magnifierGeometry(atHostPoint: hostView.convert(point, from: imageView))
        model.editor.pickFringe(at: geometry.unit, devicePixelsAcross: geometry.devicePixelsAcross)
    }

    // MARK: Pixel magnifier

    /// What the debug script reads of the magnifier.
    struct MagnifierState {
        var isVisible = false
        var placement = PixelMagnifierPlacement()
        var frame = NSRect.zero
        var reading: PixelMagnifier.Reading?
        var picture: PixelMagnifier.Picture?
        var isReady = false
        var backing = 2
    }

    /// The photo's width on screen in device pixels.
    var devicePixelsAcross: Double {
        Double(imageView.bounds.width * scrollView.magnification * (hostView.window?.backingScaleFactor ?? 2))
    }

    /// The photo's width on screen in device pixels, and `point` (canvas
    /// points) as output unit coordinates: the middle of its device pixel
    /// (ruling 18 speaks of one screen pixel).
    private func magnifierGeometry(atHostPoint point: NSPoint) -> (unit: CGPoint, devicePixelsAcross: Double) {
        let backing = hostView.convertToBacking(point)
        let snapped = hostView.convertFromBacking(NSPoint(x: backing.x.rounded(.down) + 0.5, y: backing.y.rounded(.down) + 0.5))
        let inImage = imageView.convert(snapped, from: hostView)
        let size = imageView.bounds.size
        let unit = CGPoint(x: min(max(inImage.x / max(size.width, 1), 0), 0.999_999),
                           y: min(max(1 - inImage.y / max(size.height, 1), 0), 0.999_999))
        return (unit, devicePixelsAcross)
    }

    /// The pointer moved (`mouseMoved`, or a drag panning the photo).
    func movePointer(toWindowPoint point: NSPoint?) {
        magnifierDebugUnit = nil
        magnifierPointer = point.map { hostView.convert($0, from: nil) }
        updateMagnifier()
    }

    /// A click's geometry at output unit coordinates: the script's clicks take a real click's path.
    func clickGeometry(atUnit unit: CGPoint) -> (unit: CGPoint, devicePixelsAcross: Double) {
        let size = imageView.bounds.size
        return magnifierGeometry(atHostPoint: imageView.convert(NSPoint(x: unit.x * size.width, y: (1 - unit.y) * size.height),
                                                                to: hostView))
    }

    /// The debug script's `magnifier move`.
    func moveMagnifierPointer(toUnit unit: CGPoint) {
        magnifierDebugUnit = unit
        updateMagnifier()
    }

    /// Pixel Magnifier level from `-` and `=` while picking.
    private func handleMagnifierKey(_ event: NSEvent) -> Bool {
        guard model.isPixelMagnifierActive,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift).isEmpty else { return false }
        switch event.charactersIgnoringModifiers {
        case "=", "+": model.stepPixelMagnifierLevel(up: true)
        case "-": model.stepPixelMagnifierLevel(up: false)
        default: return false
        }
        return true
    }

    @objc private func visibleRectChanged(_ notification: Notification) {
        updateLoupeViewport()
        guard model.editor.pixelMagnifierIsPicking else { return }
        // The crosshair's area follows the photo on screen (design §4 step 2).
        scrollView.window?.invalidateCursorRects(for: scrollView)
        updateMagnifier()
    }

    /// Tells the editor the part of the photo on screen while at 100% or
    /// more, nil below: "covered" follows the toolbar's 100% within a
    /// percent, and a photo small enough that Fit is 100% counts too.
    private func updateLoupeViewport(magnification known: CGFloat? = nil) {
        let bounds = imageView.bounds
        guard bounds.width > 0, bounds.height > 0, model.mode == .loupe else {
            model.editor.setLoupeViewport(nil)
            return
        }
        let magnification = known ?? scrollView.magnification
        // Rounding in the scroll view: within a percent of 100% is 100% (design §4).
        guard magnification >= 0.99 else {
            model.editor.setLoupeViewport(nil)
            return
        }
        let visible = scrollView.documentVisibleRect.intersection(bounds)
        guard !visible.isEmpty else {
            model.editor.setLoupeViewport(nil)
            return
        }
        // The view is not flipped: unit coordinates count from the top.
        model.editor.setLoupeViewport(CGRect(x: visible.minX / bounds.width, y: 1 - visible.maxY / bounds.height,
                                             width: visible.width / bounds.width, height: visible.height / bounds.height))
    }

    /// While a tool is picking, Esc cancels it from wherever the keyboard is
    /// (design §4): an inspector button or a closed pop-up too. Text fields
    /// keep their own Esc first, and an open menu tracks its own events.
    private func syncEscapeMonitor() {
        let picking = model.editor.pixelMagnifierIsPicking
        if picking, escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.cancelsPicking(event) == true ? nil : event
            }
        } else if !picking, let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private func cancelsPicking(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, event.window === hostView.window, model.editor.pixelMagnifierIsPicking,
              !(event.window?.firstResponder is NSText) else { return false }
        model.editor.armFringePicker(nil)
        return true
    }

    /// Shows the magnifier for what is under the pointer now, or hides it
    /// (design §20 "When it shows"). Called for every change: pointer,
    /// pixels ready, level, pan, zoom, photo.
    func updateMagnifier() {
        let editor = model.editor
        guard editor.pixelMagnifierIsPicking, model.mode == .loupe, let point = magnifierHostPoint(),
              isOverPhoto(point), magnifierDebugUnit != nil || model.isWindowKey else {
            hideMagnifier()
            return
        }
        let geometry = magnifierGeometry(atHostPoint: point)
        let backing = Int(hostView.window?.backingScaleFactor ?? 2)
        var content = PixelMagnifierView.Content(level: model.pixelMagnifierLevel, backing: backing)
        var state = MagnifierState(isVisible: true, backing: backing)
        if let tool = editor.pixelMagnifierTool {
            if let reading = PixelMagnifier.reading(tool: tool, atOutput: geometry.unit,
                                                    devicePixelsAcross: geometry.devicePixelsAcross) {
                let picture = PixelMagnifier.picture(image: tool.image, center: reading.pixel, level: model.pixelMagnifierLevel,
                                                     deviceSize: Int(PixelMagnifierLayout.pictureDiameter) * backing)
                content.picture = picture
                content.values = reading.values
                content.verdict = reading.verdict
                content.note = reading.note
                state.reading = reading
                state.picture = picture
                state.isReady = true
            }
        }
        magnifierSpinner(waiting: !state.isReady)
        let placement = PixelMagnifierPlacement.place(pointer: CGPoint(x: point.x, y: hostView.bounds.height - point.y),
                                                      canvas: hostView.bounds.size, previous: magnifierPlacement)
        magnifierPlacement = placement
        let size = PixelMagnifierLayout.compositeSize
        magnifierView.setFrameOrigin(NSPoint(x: placement.origin.x.rounded(),
                                             y: (hostView.bounds.height - placement.origin.y - size.height).rounded()))
        magnifierView.isHidden = false
        magnifierView.show(content)
        state.placement = placement
        state.frame = magnifierView.frame
        magnifierState = state
    }

    private func hideMagnifier() {
        magnifierSpinner(waiting: false)
        magnifierPlacement = nil
        if !magnifierView.isHidden { magnifierView.isHidden = true }
        magnifierState = MagnifierState()
    }

    private func magnifierSpinner(waiting: Bool) {
        guard waiting else {
            magnifierSpinnerTask?.cancel()
            magnifierSpinnerTask = nil
            magnifierView.setSpinning(false)
            return
        }
        guard magnifierSpinnerTask == nil else { return }
        magnifierSpinnerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.magnifierView.setSpinning(true)
        }
    }

    /// The pointer on the canvas: the debug script's, or the last real one.
    private func magnifierHostPoint() -> NSPoint? {
        if let unit = magnifierDebugUnit {
            let size = imageView.bounds.size
            return imageView.convert(NSPoint(x: unit.x * size.width, y: (1 - unit.y) * size.height), to: hostView)
        }
        return magnifierPointer
    }

    /// The same area as the crosshair: the photo where the scroll view shows it.
    private func isOverPhoto(_ point: NSPoint) -> Bool {
        guard hostView.bounds.contains(point) else { return false }
        let inClip = scrollView.contentView.convert(point, from: hostView)
        guard scrollView.contentView.bounds.contains(inClip) else { return false }
        return imageView.bounds.contains(imageView.convert(point, from: hostView))
    }

    func toggleZoom(at point: NSPoint? = nil) {
        zoom = zoom == .fit ? .actualSize : .fit
        applyZoom(animated: true, centeredAt: point)
        if zoom == .actualSize { loadFullResolution() }
    }

    private var fitMagnification: CGFloat {
        let clip = scrollView.contentView.bounds.size
        let document = imageView.frame.size
        guard document.width > 0, document.height > 0, clip.width > 0 else { return 1 }
        // Fitted within a margin of the neutral surround (section 1 of docs/UI_REDESIGN.md).
        let margin: CGFloat = 24
        let clipSize = scrollView.frame.size
        let width = max(clipSize.width - margin * 2, 1)
        let height = max(clipSize.height - margin * 2, 1)
        return min(width / document.width, height / document.height, 1)
    }

    /// ⌘= / ⌘−: the next step (`LoupeZoomSteps`), keeping the visible center.
    func stepZoom(in zoomIn: Bool) {
        let current = scrollView.magnification
        let fit = fitMagnification
        guard let target = zoomIn ? LoupeZoomSteps.zoomIn(from: current, fit: fit)
                                  : LoupeZoomSteps.zoomOut(from: current, fit: fit) else { return }
        let visible = scrollView.documentVisibleRect
        updateFiltering(magnification: target)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            scrollView.animator().setMagnification(target, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.updateLoupeViewport() }
        })
        zoom = target > fit * 1.001 ? .actualSize : .fit
        if zoom == .actualSize { loadFullResolution() }
        publishZoom(magnification: target)
    }

    /// Tells the menus whether the loupe is zoomed and can zoom further.
    private func publishZoom(magnification: CGFloat? = nil) {
        let current = magnification ?? scrollView.magnification
        let fit = fitMagnification
        let state = LoupeZoomState(isZoomed: zoom != .fit,
                                   canZoomIn: LoupeZoomSteps.zoomIn(from: current, fit: fit) != nil,
                                   canZoomOut: zoom != .fit && LoupeZoomSteps.zoomOut(from: current, fit: fit) != nil,
                                   isActualSize: zoom != .fit && abs(current - 1) < 0.01)
        if model.loupeZoom != state { model.loupeZoom = state }
        updateLoupeViewport(magnification: current)
    }

    private func applyZoom(animated: Bool, centeredAt point: NSPoint? = nil) {
        let target: CGFloat = zoom == .fit ? fitMagnification : 1
        defer { publishZoom(magnification: target) }
        let center = point ?? NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        updateFiltering(magnification: target)
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                scrollView.animator().setMagnification(target, centeredAt: center)
            }, completionHandler: { [weak self] in
                // The animation's own bounds changes can end short of the target.
                MainActor.assumeIsolated { self?.updateLoupeViewport() }
            })
        } else {
            scrollView.setMagnification(target, centeredAt: center)
        }
    }

    /// The canvas's frame changed. A film strip change (shown, hidden or
    /// settled) changes it once, and that refit animates.
    private func fitIfNeeded() {
        let size = scrollView.frame.size
        guard size != fittedSize else { return }
        fittedSize = size
        model.loupeFitCount += 1
        let animated = Date() < animatesFitUntil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animatesFitUntil = .distantPast
        if zoom == .fit { applyZoom(animated: animated) }
    }

    @objc private func didEndMagnify(_ notification: Notification) {
        adoptMagnification()
        publishZoom()
    }

    /// Option-scroll zooms between fit and the largest magnification, keeping
    /// the image point under the pointer (`windowPoint`) where it is.
    func zoom(by factor: CGFloat, at windowPoint: NSPoint) {
        let old = scrollView.magnification
        let target = ScrollZoom.magnification(old, factor: factor, minimum: fitMagnification,
                                              maximum: scrollView.maxMagnification)
        guard abs(target - old) > 0.0001 else { return }
        let clip = scrollView.contentView
        let anchor = imageView.convert(windowPoint, from: nil)
        let origin = ScrollZoom.visibleOrigin(keeping: anchor, visibleOrigin: clip.bounds.origin, from: old, to: target)
        scrollView.magnification = target
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
        adoptMagnification()
        publishZoom()
    }

    /// Takes the zoom from a magnification a pinch or Option-scroll left:
    /// zooming past the preview's resolution switches to the full render.
    private func adoptMagnification() {
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

    // MARK: Accessibility

    /// The photo the canvas describes to VoiceOver.
    var accessibilityItem: CatalogItem? { model.focusedItem }
    private var describedValue: String?

    /// "Picked, 13 of 87"; "Sharpening map, Picked, 13 of 87" while the map is on screen;
    /// "Picked, Machine learning not applied, 13 of 87" (ml-denoise design §8).
    var accessibilityValue: String? {
        guard let item = accessibilityItem, let index = model.focusIndex else { return nil }
        let notes = model.editor.machineLearningNotApplied == nil ? [] : [MachineLearningText.canvasValue]
        let value = PhotoAccessibility.loupeValue(for: item, offline: model.isOffline(item), notes: notes, index: index,
                                                  count: model.items.count)
        if model.editor.pixelMagnifierIsPicking { return LensText.pickingCanvasValue(value) }
        if let fringeMap = model.editor.shownFringeMap { return LensText.canvasValue(fringeMap, photoValue: value) }
        guard let map = model.editor.shownSharpeningMap else { return value }
        return SharpeningMapText.canvasValue(map, photoValue: value)
    }

    /// Culling the photo on screen, or moving to another, changes the
    /// canvas's value; VoiceOver is told. (The move itself is announced by
    /// the key's handler, or with the culling result after auto-advance.)
    func updateAccessibility() {
        let value = accessibilityValue
        defer { describedValue = value }
        if describedValue != nil, value != nil, describedValue != value {
            NSAccessibility.post(element: hostView, notification: .valueChanged)
        }
    }

    /// The grid's culling actions, then Show Grid, Zoom and Show Original,
    /// titled for the current state.
    func accessibilityActions() -> [NSAccessibilityCustomAction]? {
        guard let item = accessibilityItem else { return nil }
        let zoomTitle = zoom == .fit ? String(localized: "Zoom to 100%") : String(localized: "Zoom to Fit")
        let originalTitle = model.editor.showsOriginal ? String(localized: "Show Adjustments")
                                                       : String(localized: "Show Original")
        var actions = PhotoAccessibility.cullingActions(forVersion: item.versionID, model: model) + [
            PhotoAccessibility.showGrid(model),
            PhotoAccessibility.action(zoomTitle) { [weak self] in self?.toggleZoom() },
            PhotoAccessibility.action(originalTitle) { [weak self] in self?.model.editor.toggleOriginal() },
        ]
        // Matches the context menu: listed only when it can act.
        if model.canShowSharpeningMap {
            let titles = SharpeningMapText.menuTitle
            actions.append(PhotoAccessibility.action(model.editor.showsSharpeningMap ? titles.hide : titles.show) {
                [weak self] in self?.model.toggleSharpeningMap(from: .menu)
            })
        }
        if model.canShowFringeMap {
            let titles = LensText.menuTitle
            actions.append(PhotoAccessibility.action(model.editor.showsFringeMap ? titles.hide : titles.show) {
                [weak self] in self?.model.toggleFringeMap(from: .menu)
            })
        }
        if model.isPixelMagnifierActive {
            if model.pixelMagnifierLevel.stepped(up: true) != nil {
                actions.append(PhotoAccessibility.action(PixelMagnifierText.zoomIn) { [weak self] in
                    self?.model.stepPixelMagnifierLevel(up: true)
                })
            }
            if model.pixelMagnifierLevel.stepped(up: false) != nil {
                actions.append(PhotoAccessibility.action(PixelMagnifierText.zoomOut) { [weak self] in
                    self?.model.stepPixelMagnifierLevel(up: false)
                })
            }
        }
        return actions
    }

    // MARK: Keys

    func handle(_ event: NSEvent) -> Bool {
        if model.editor.cropSession != nil {
            switch event.keyCode {
            case 36, 76:
                model.editor.endCrop(save: true)
                return true
            case 53:
                model.editor.endCrop(save: false)
                return true
            default:
                break
            }
        }
        if handleMagnifierKey(event) { return true }
        if let action = CullingKeymap.action(for: event) {
            model.perform(action)
            return true
        }
        let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if event.charactersIgnoringModifiers == "\\", bare {
            model.editor.toggleOriginal()
            return true
        }
        // Starts cropping, or finishes (as Return does).
        if event.charactersIgnoringModifiers?.lowercased() == "c", bare {
            model.crop()
            return true
        }
        // S: the loupe's photo beside its partner (side-by-side-comparison design §3).
        if ComparisonKey.isCompare(event) {
            model.toggleComparison()
            return true
        }
        switch NavigationKey.from(event) {
        case .left, .up: model.moveFocus(by: -1)
        case .right, .down: model.moveFocus(by: 1)
        case .home: model.setFocus(0)
        case .end: model.setFocus(model.items.count - 1)
        case .exitLoupe where model.editor.pickingFringeSlot != nil:
            // Esc backs out one level: the crop session (above), picking, the map, review, then the loupe.
            model.editor.armFringePicker(nil)
            return true
        case .exitLoupe where model.editor.showsFringeMap:
            model.setFringeMap(false, from: .key)
            return true
        case .exitLoupe where model.editor.showsSharpeningMap:
            model.setSharpeningMap(false, from: .key)
            return true
        case .exitLoupe where model.isReviewing:
            // Esc backs out one level: review first, then the loupe.
            model.exitReview()
            return true
        case .toggleLoupe, .exitLoupe:
            model.closeLoupe()
            return true
        case .toggleReview:
            model.toggleReview()
            return true
        case .toggleZoom:
            toggleZoom()
            return true
        case .pageUp, .pageDown, nil: return false
        }
        model.announceLoupePhoto()
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

    private var pointerArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        // The pixel magnifier follows the pointer (design §20).
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.movePointer(toWindowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.movePointer(toWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        controller?.movePointer(toWindowPoint: nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model = controller?.model, model.focusedItem != nil else { return nil }
        return PhotoContextMenu.loupe(model: model)
    }

    // MARK: Accessibility

    // The canvas is one image element: the scroll view and image view inside
    // it are hidden from VoiceOver; the crop and mask overlays are not.

    override func isAccessibilityElement() -> Bool { controller?.accessibilityItem != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { controller?.accessibilityItem.map(PhotoAccessibility.label) }

    override func accessibilityValue() -> Any? { controller?.accessibilityValue }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? { controller?.accessibilityActions() }

    override func accessibilityChildren() -> [Any]? {
        super.accessibilityChildren()?.filter { !($0 is LoupeScrollView) }
    }

    // Declared nonisolated, but AppKit asks accessibility questions on the main thread.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        let hit = super.accessibilityHitTest(point)
        guard let view = hit as? NSView else { return hit }
        let insideCanvas = MainActor.assumeIsolated {
            subviews.first { $0 is LoupeScrollView }.map(view.isDescendant(of:)) ?? false
        }
        return insideCanvas ? self : hit
    }
}

/// The document view: one layer showing the image stretched to the view's bounds,
/// which always have the image's aspect ratio. Its mouse events go up to the
/// `LoupeScrollView`.
final class LoupeImageView: NSView {
    var usesNearestFiltering = false {
        didSet { layer?.magnificationFilter = usesNearestFiltering ? .nearest : .linear }
    }

    /// Real pixels, over the base image: the sharp frame of the part on
    /// screen. Nearest-neighbor enlarges it above 100% (design §2.2); it
    /// swaps in place, with no animation (design §3).
    private let tileLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        tileLayer.contentsGravity = .resize
        tileLayer.magnificationFilter = .nearest
        tileLayer.minificationFilter = .trilinear
        tileLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "hidden": NSNull()]
        tileLayer.isHidden = true
        layer?.addSublayer(tileLayer)
    }

    /// Shows `image` over the part of the photo at `unit` (unit coordinates,
    /// origin at the top left); nil hides it. Below every other subview, so
    /// the mask handles stay on top.
    func setTile(_ image: CGImage?, unit: CGRect) {
        guard let image else {
            tileLayer.contents = nil
            tileLayer.isHidden = true
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = bounds.size
        // A view's layer has its origin at the bottom left unless the view is flipped.
        let y = (layer?.isGeometryFlipped ?? false) ? unit.minY * size.height : (1 - unit.maxY) * size.height
        tileLayer.frame = CGRect(x: unit.minX * size.width, y: y, width: unit.width * size.width, height: unit.height * size.height)
        tileLayer.contents = image
        tileLayer.isHidden = false
        CATransaction.commit()
    }

    var hasTile: Bool { !tileLayer.isHidden }

    /// The image layer's sublayers, back to front, for the debug script:
    /// the tile has to stay under the mask overlay's view.
    var debugLayerOrder: String {
        (layer?.sublayers ?? []).map { $0 === tileLayer ? "tile" : "view" }.joined(separator: ",")
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
}

/// Takes the mouse for the whole canvas, image and margins: a click toggles
/// zoom once the double-click interval has passed without a second click, a
/// double-click goes back to the grid, a drag pans and Option-scroll zooms.
/// Plain scrolling pans as usual.
final class LoupeScrollView: NSScrollView {
    /// Called with the clicked point in the document view.
    var onClick: ((NSPoint) -> Void)?
    var onDoubleClick: (() -> Void)?
    /// A fringe slot is picking: a click picks at once (`onPick`).
    var isPicking: (() -> Bool)?
    var onPick: ((NSPoint) -> Void)?
    /// The photo's rect in the document view while the crosshair shows over it.
    var photoRect: (() -> NSRect?)?
    /// The pointer moved during a drag (window coordinates).
    var onPointerMoved: ((NSPoint) -> Void)?
    /// When the last pick landed: the second click of a double-click is ignored.
    private var lastPick: TimeInterval?
    /// Called with the zoom factor of an Option-scroll and the pointer in window coordinates.
    var onZoomScroll: ((CGFloat, NSPoint) -> Void)?
    /// A mouse-down arrived: a comparison pane that was not the active one
    /// becomes it and answers true, and that click then does nothing more
    /// (side-by-side-comparison design §5); a drag from it still pans.
    var onActivate: (() -> Bool)?
    /// The click in progress only made its pane active.
    private var clickOnlyActivated = false
    /// How far the mouse moves before a click becomes a drag, in points.
    private static let dragThreshold: CGFloat = 3
    private var downLocation: NSPoint?
    private var dragOrigin: NSPoint?
    private var pendingClick: Task<Void, Never>?

    func cancelPendingClick() {
        pendingClick?.cancel()
        pendingClick = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let onZoomScroll {
            onZoomScroll(ScrollZoom.factor(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                           inverted: event.isDirectionInvertedFromDevice),
                         event.locationInWindow)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelPendingClick()
        downLocation = nil
        switch event.clickCount {
        case 1:
            clickOnlyActivated = onActivate?() ?? false
            downLocation = event.locationInWindow
            // The outline shows the pixel a click from here would take (R22).
            if isPicking?() == true { onPointerMoved?(event.locationInWindow) }
        case 2:
            // A habitual double-click right after a pick stays in the loupe.
            if let lastPick, event.timestamp - lastPick < NSEvent.doubleClickInterval { return }
            onDoubleClick?()
        default: break
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let rect = photoRect?(), let documentView else { return }
        addCursorRect(convert(documentView.convert(rect, to: self), to: self).intersection(bounds), cursor: .crosshair)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downLocation else { return }
        let location = event.locationInWindow
        if dragOrigin == nil {
            // Within the threshold this is still a click at `down`: the outline stays (R22).
            guard hypot(location.x - down.x, location.y - down.y) > Self.dragThreshold else { return }
            dragOrigin = down
            NSCursor.closedHand.push()
        }
        onPointerMoved?(location)
        guard let origin = dragOrigin else { return }
        var bounds = contentView.bounds.origin
        bounds.x -= (location.x - origin.x) / magnification
        bounds.y -= (location.y - origin.y) / magnification
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: bounds, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
        dragOrigin = location
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            downLocation = nil
            dragOrigin = nil
        }
        if dragOrigin != nil {
            NSCursor.pop()
            return
        }
        guard let down = downLocation, let point = documentView?.convert(down, from: nil) else { return }
        if clickOnlyActivated { return }
        if isPicking?() == true {
            lastPick = event.timestamp
            onPick?(point)
            return
        }
        pendingClick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, let self else { return }
            self.pendingClick = nil
            self.onClick?(point)
        }
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

/// One line under the photo, on the surround (section 1 of
/// docs/UI_REDESIGN.md): the position on the left; the stars, flag and color
/// label with its name in the middle; Filtered, Original, HDR and Offline on
/// the right. The file name is the window title; capture details are in the
/// Info tab.
struct LoupeCaption: View {
    let model: LibraryModel

    static let height: CGFloat = 28

    var body: some View {
        ZStack {
            if let item = model.focusedItem, let index = model.focusIndex {
                HStack {
                    Text(PhotoAccessibility.position(index, of: model.items.count))
                        .monospacedDigit()
                    Spacer()
                    badges(item)
                }
                CullingMarks(item: item)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: Self.height)
    }

    @ViewBuilder
    private func badges(_ item: CatalogItem) -> some View {
        HStack(spacing: 6) {
            if model.isFiltered {
                CaptionBadge(title: String(localized: "Filtered"),
                             help: String(localized: "A filter hides some of this source's photos"))
            }
            // The map takes Original's place; the two are never on screen together.
            if let map = model.editor.shownSharpeningMap {
                CaptionBadge(title: SharpeningMapText.badge(map), help: SharpeningMapText.badgeHelp(map))
            } else if let map = model.editor.shownFringeMap {
                CaptionBadge(title: LensText.badge(map), help: LensText.badgeHelp(map))
            } else if model.editor.showsOriginal {
                CaptionBadge(title: String(localized: "Original"),
                             help: String(localized: "Showing the photo without adjustments. Press \\ to show them again."))
            }
            // One spinner in one slot; the map's label wins when both wait (ml-denoise design §6).
            if let label = spinnerLabel {
                ProgressView()
                    .controlSize(.mini)
                    .help(label)
                    .accessibilityLabel(label)
            }
            if let headroom = model.loupeHDRHeadroom {
                CaptionBadge(title: String(localized: "HDR"),
                             help: String(localized: "Highlights up to \(headroom.formatted(.number.precision(.fractionLength(1))))× SDR white are shown with the display's extended range"))
            }
            if let reason = model.editor.machineLearningNotApplied {
                CaptionBadge(title: MachineLearningText.badge, help: MachineLearningText.badgeHelp(reason))
            }
            if model.isOffline(item) {
                CaptionBadge(title: String(localized: "Offline"),
                             help: String(localized: "The volume \(model.volumeName(for: item) ?? "") is not connected. Showing the cached preview."))
            }
            // The strip's toggle, 8 pt after the last badge; review hides both.
            if !model.isReviewing {
                FilmStripToggle(model: model)
                    .padding(.leading, 2)
            }
        }
    }
}

extension LoupeCaption {
    /// The caption spinner's label: the sharpening map's refinement, or a
    /// machine learning frame the loupe has waited on for more than 0.5 s.
    var spinnerLabel: String? {
        if model.editor.shownSharpeningMap != nil, model.editor.isRefiningSharpeningMap {
            return String(localized: "Refining the sharpening map",
                          comment: "Tooltip and VoiceOver label of the loupe caption's spinner")
        }
        if model.editor.shownFringeMap != nil, model.editor.isRefiningSharpeningMap { return LensText.refiningMap }
        if model.editor.isRefiningPickPreview { return LensText.refiningPhoto }
        if model.editor.isAwaitingMachineLearningFrame { return MachineLearningText.spinner }
        // Last, so the maps and machine learning keep their labels (design §2.1).
        return model.editor.isAwaitingSharpFrame ? LensText.refiningPhoto : nil
    }
}

/// A small outlined text badge.
struct CaptionBadge: View {
    let title: String
    let help: String

    var body: some View {
        Text(title)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.6)))
            .help(help)
    }
}

/// Stars (SF Symbols), the flag, and the color label's dot with its name.
struct CullingMarks: View {
    let item: CatalogItem

    var body: some View {
        HStack(spacing: 10) {
            // Five slots, the unused ones invisible: the flag and label stay put.
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .opacity(index < item.rating.rawValue ? 1 : 0)
                }
            }
            .foregroundStyle(Color(nsColor: Palette.rating))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PhotoAccessibility.text(.rating(item.rating)))
            .accessibilityHidden(item.rating == .unrated)
            switch item.flag {
            case .picked:
                Image(systemName: "flag.fill").foregroundStyle(Color(nsColor: Palette.pick))
                    .help("Picked")
                    .accessibilityLabel(Text("Picked"))
            case .rejected:
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color(nsColor: Palette.reject))
                    .help("Rejected")
                    .accessibilityLabel(Text("Rejected"))
            case .none:
                EmptyView()
            }
            if let color = Palette.color(for: item.colorLabel) {
                HStack(spacing: 4) {
                    Circle().fill(Color(nsColor: color)).frame(width: 9, height: 9)
                    Text(ColorLabelText.name(item.colorLabel))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
