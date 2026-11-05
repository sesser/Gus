import AVFoundation
import Observation

/// The video loupe's player as the rest of the window sees it: View ▸ Play /
/// Pause, Space, the video loupe's context menu and its VoiceOver action all
/// toggle it here, and menus title themselves by `isPlaying`.
@MainActor
@Observable
final class VideoPlayback {
    @ObservationIgnored private weak var player: AVPlayer?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// The video loupe's player is playing.
    private(set) var isPlaying = false

    /// The video loupe shows `player` (it replaces any earlier one).
    func attach(_ player: AVPlayer) {
        observation?.invalidate()
        self.player = player
        // AVPlayer reports changes on the thread that made them; the state is
        // read there and handed to the main actor with the player's identity
        // (AVPlayer isn't Sendable).
        observation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            let id = ObjectIdentifier(player)
            Task { @MainActor in
                guard let self, self.player.map(ObjectIdentifier.init) == id else { return }
                self.isPlaying = playing
            }
        }
    }

    /// The video loupe closed or moved to another video.
    func detach(_ player: AVPlayer) {
        guard self.player === player else { return }
        observation?.invalidate()
        observation = nil
        self.player = nil
        isPlaying = false
    }

    func toggle() {
        guard let player else { return }
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }
}
