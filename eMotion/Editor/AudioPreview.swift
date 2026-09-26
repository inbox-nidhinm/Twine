import Foundation
import AVFoundation
import MotionModel
import MotionEvaluation
import MotionExport

/// The composition's sound while it plays in the editor: the same clips an
/// export writes, played by one player that follows the playhead. It starts
/// and stops with playback, and jumps when the playhead jumps (a loop, a
/// scrub) or drifts more than a few frames from it.
@MainActor
final class AudioPreview {
    private var player: AVPlayer?
    private var mix: AudioComposition?
    private var clips: [AudioClip] = []
    private var isPlaying = false
    private let locate: (UUID) -> URL?

    init(locate: @escaping (UUID) -> URL?) {
        self.locate = locate
    }

    /// Brings the sound into line with the editor. Called on every tick of
    /// playback and whenever playback starts, stops or the playhead moves.
    func follow(_ project: Project, time: Double, playing: Bool) {
        guard playing else {
            if isPlaying {
                player?.pause()
                isPlaying = false
            }
            return
        }
        let now = audioClips(project)
        if now != clips || player == nil {
            clips = now
            rebuild(project)
            isPlaying = false
        }
        guard let player else { return }
        let target = CMTime(seconds: time, preferredTimescale: 48000)
        if !isPlaying {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            isPlaying = true
        } else if abs(player.currentTime().seconds - time) > 0.12 {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func rebuild(_ project: Project) {
        player?.pause()
        player = nil
        let media = Dictionary(project.media.compactMap { a in locate(a.id).map { (a.id, $0) } }, uniquingKeysWith: { a, _ in a })
        guard let mix = AudioComposition(clips: clips, media: media) else { self.mix = nil; return }
        self.mix = mix
        let item = AVPlayerItem(asset: mix.composition)
        item.audioMix = mix.audioMix
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
    }
}
