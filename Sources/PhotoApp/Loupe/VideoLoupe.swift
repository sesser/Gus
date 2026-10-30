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

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
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
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        view.player?.pause()
        view.player = nil
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
        case .toggleLoupe, .exitLoupe: model.closeLoupe()
        case .toggleZoom, .pageUp, .pageDown, nil: return false
        }
        return true
    }
}
