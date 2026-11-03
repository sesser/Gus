import AVKit
import PhotoCore
import SwiftUI

/// Plays a video in the loupe. Space plays and pauses; the arrow, culling,
/// Return and Escape keys work as they do for photos, and a double-click on the
/// picture goes back to the grid.
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
        view.player = AVPlayer(url: url)
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) {
            [weak view, weak model] event in
            guard let view, let model, let window = view.window, event.window === window else { return event }
            if event.type == .leftMouseDown {
                guard Self.isDoubleClickOnPicture(event, in: view) else { return event }
                model.closeLoupe()
                return nil
            }
            guard !(window.firstResponder is NSText) else { return event }
            return Self.handle(event, model: model, player: view.player) ? nil : event
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
        host.playerView.player?.pause()
        host.playerView.player = nil
    }

    /// A double-click on the picture or the margins around it. AVKit's playback
    /// controls are controls on visual effect views; clicks on them stay theirs.
    @MainActor
    static func isDoubleClickOnPicture(_ event: NSEvent, in view: AVPlayerView) -> Bool {
        guard event.clickCount == 2, let superview = view.superview else { return false }
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
    static func handle(_ event: NSEvent, model: LibraryModel, player: AVPlayer?) -> Bool {
        if event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            if player?.timeControlStatus == .playing { player?.pause() } else { player?.play() }
            return true
        }
        if let action = CullingKeymap.action(for: event) {
            model.perform(action)
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
    private weak var model: LibraryModel?
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
        let playing = playerView.player?.timeControlStatus == .playing
        let playTitle = playing ? String(localized: "Pause", comment: "VoiceOver action on a video")
                                : String(localized: "Play", comment: "VoiceOver action on a video")
        return PhotoAccessibility.cullingActions(forVersion: item.versionID, model: model) + [
            PhotoAccessibility.action(playTitle) { [weak self] in
                guard let player = self?.playerView.player else { return }
                if player.timeControlStatus == .playing { player.pause() } else { player.play() }
            },
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
