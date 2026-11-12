import AVKit
import PhotoCore
import SwiftUI

/// Plays a video in the loupe. Space plays and pauses; the arrow, culling,
/// Return and Escape keys work as they do for photos, a double-click on the
/// picture goes back to the grid, and a right-click or Control-click on it
/// shows the context menu.
///
/// AVKit gives keyboard focus to a view of its own, which would take the arrow
/// keys for scrubbing, and takes the mouse in views of its own, so those keys
/// and double-clicks are picked up by a local event monitor while the video is
/// on screen.
struct VideoLoupe: NSViewRepresentable {
    let model: LibraryModel
    let url: URL

    final class Coordinator {
        var monitor: Any?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> VideoLoupeHostView {
        let host = VideoLoupeHostView(model: model)
        let view = host.playerView
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        let player = AVPlayer(url: url)
        view.player = player
        model.playback.attach(player)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) {
            [weak host, weak view, weak model] event in
            guard let host, let view, let model, let window = view.window, event.window === window else { return event }
            let isContextClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            if isContextClick {
                // AVKit's views take the click otherwise; its controls keep theirs.
                guard let menu = host.menu(for: event) else { return event }
                NSMenu.popUpContextMenu(menu, with: event, for: host)
                return nil
            }
            if event.type == .leftMouseDown {
                guard event.clickCount == 2, Self.isOnPicture(event, in: view) else { return event }
                model.closeLoupe()
                return nil
            }
            guard !(window.firstResponder is NSText) else { return event }
            return Self.handle(event, model: model) ? nil : event
        }
        return host
    }

    func updateNSView(_ host: VideoLoupeHostView, context: Context) {
        // Reading this registers observation, so culling the video lands here.
        _ = model.itemsRevision
        host.updateAccessibility()
    }

    static func dismantleNSView(_ host: VideoLoupeHostView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        if let player = host.playerView.player {
            player.pause()
            host.model?.playback.detach(player)
        }
        host.playerView.player = nil
    }

    /// A click on the picture or the margins around it (double-clicks and the
    /// context menu). AVKit's playback controls are controls on visual effect
    /// views; clicks on them stay theirs.
    @MainActor
    static func isOnPicture(_ event: NSEvent, in view: AVPlayerView) -> Bool {
        guard let superview = view.superview else { return false }
        var hit = view.hitTest(superview.convert(event.locationInWindow, from: nil))
        guard hit != nil else { return false }
        while let current = hit, current !== view {
            if current is NSControl || current is NSVisualEffectView { return false }
            hit = current.superview
        }
        return true
    }

    /// Returns true when the key was handled.
    @MainActor
    static func handle(_ event: NSEvent, model: LibraryModel) -> Bool {
        if event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            model.playback.toggle()
            return true
        }
        if let action = CullingKeymap.action(for: event) {
            model.perform(action)
            return true
        }
        // S on a video says why it can't be compared (side-by-side-comparison design §3).
        if ComparisonKey.isCompare(event) {
            model.toggleComparison()
            return true
        }
        switch NavigationKey.from(event) {
        case .left, .up: model.moveFocus(by: -1)
        case .right, .down: model.moveFocus(by: 1)
        case .home: model.setFocus(0)
        case .end: model.setFocus(model.items.count - 1)
        case .exitLoupe where model.isReviewing:
            model.exitReview()
            return true
        case .toggleLoupe, .exitLoupe:
            model.closeLoupe()
            return true
        case .toggleReview:
            model.toggleReview()
            return true
        case .toggleZoom, .pageUp, .pageDown, nil: return false
        }
        model.announceLoupePhoto()
        return true
    }
}

/// Holds the player. To VoiceOver it is a group describing the video, with
/// the culling actions, Play / Pause and Show Grid; the player's own
/// controls stay inside it as its children.
final class VideoLoupeHostView: NSView {
    let playerView = AVPlayerView()
    private(set) weak var model: LibraryModel?
    private var describedValue: String?

    init(model: LibraryModel) {
        self.model = model
        super.init(frame: .zero)
        playerView.frame = bounds
        playerView.autoresizingMask = [.width, .height]
        addSubview(playerView)
        NotificationCenter.default.addObserver(self, selector: #selector(takeFocus(_:)),
                                               name: .browserShouldTakeFocus, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // Takes the keyboard like the photo canvas, so culling keys reach the
    // event monitor rather than a text field AppKit would pick instead.
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// From the model, or from a view in this window (an inspector value field).
    @objc private func takeFocus(_ notification: Notification) {
        let sender = notification.object as AnyObject?
        guard let window, sender === model || sender === window, model?.mode == .loupe else { return }
        window.makeFirstResponder(self)
    }

    private var item: CatalogItem? { model?.focusedItem }

    /// The photo items, Play / Pause and Show Grid, over the picture only.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, VideoLoupe.isOnPicture(event, in: playerView) else { return nil }
        return PhotoContextMenu.videoLoupe(model: model)
    }

    override func isAccessibilityElement() -> Bool { item != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { item.map(PhotoAccessibility.label) }

    override func accessibilityValue() -> Any? { currentValue }

    private var currentValue: String? {
        guard let model, let item, let index = model.focusIndex else { return nil }
        return PhotoAccessibility.loupeValue(for: item, offline: model.isOffline(item), index: index,
                                             count: model.items.count)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let model, let item else { return nil }
        let playTitle = model.playback.isPlaying ? String(localized: "Pause", comment: "VoiceOver action on a video")
                                                 : String(localized: "Play", comment: "VoiceOver action on a video")
        return PhotoAccessibility.cullingActions(forVersion: item.versionID, model: model) + [
            PhotoAccessibility.action(playTitle) { [weak model] in model?.playback.toggle() },
            PhotoAccessibility.showGrid(model),
        ]
    }

    /// Culling the video changes the value; VoiceOver is told.
    func updateAccessibility() {
        let value = currentValue
        defer { describedValue = value }
        if describedValue != nil, value != nil, describedValue != value {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
}
