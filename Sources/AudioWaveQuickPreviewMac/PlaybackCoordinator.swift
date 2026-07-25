import AVFoundation
import Foundation

@MainActor
final class PlaybackCoordinator: NSObject {
    private(set) var player: AVAudioPlayer?
    var onStateChange: (() -> Void)?

    func load(url: URL) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        onStateChange?()
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    var currentTime: Double {
        player?.currentTime ?? 0
    }

    var duration: Double {
        player?.duration ?? 0
    }

    func playPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        onStateChange?()
    }

    /// Adjusts preview loudness without disturbing position or play state.
    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
        onStateChange?()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        onStateChange?()
    }
}

extension PlaybackCoordinator: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.onStateChange?()
        }
    }
}
