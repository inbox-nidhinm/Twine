import Foundation
import AVFoundation
import QuartzCore
import MotionModel
import MotionEvaluation
import MotionExport

/// The composition's sound while it plays in the editor: the same clips an
/// export writes, played by one player that follows the playhead. It starts
/// and stops with playback, and jumps when the playhead jumps (a loop, a
/// scrub) or drifts more than a few frames from it.
///
/// The sound is set going at a moment on the host clock, the one the
/// playhead's display clock runs on, a little ahead so it is ready, and
/// drift is only judged once it has had time to start, and not at all past
/// where the sound runs out. The stutter was the player, stopped at its end,
/// being sought on every frame and then, on the next loop, only nudged
/// along in jumps without ever playing again.
@MainActor
final class AudioPreview {
    private var player: AVPlayer?
    private var mix: AudioComposition?
    private var clips: [AudioClip] = []
    private var isPlaying = false
    /// Where the sound runs out: past it the player has stopped by itself
    /// and there is nothing to line up until the playhead comes back.
    private var length = 0.0
    /// When, on the host clock, the sound last set going has had time to
    /// start.
    private var settlesAt = 0.0
    private let locate: (UUID) -> URL?

    /// How far ahead the sound is set going, for the player to be ready.
    private static let lead = 0.05
    /// How long a start is left alone before drift is judged.
    private static let settle = 0.3
    /// How far the sound may stray from the playhead before it jumps.
    private static let drift = 0.12
    /// Further than this is the playhead jumping, not the sound straying.
    private static let jump = 0.3

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
        // A player still opening its files cannot start at a set moment;
        // the next tick tries again, a frame or two on.
        guard let player, player.status == .readyToPlay else { return }
        let clock = CACurrentMediaTime()
        if !isPlaying {
            start(player, at: time, clock: clock)
        } else if time < length - Self.drift {
            // A jump (a loop, a scrub) is followed at once; a small stray
            // only once the sound has settled.
            let off = abs(player.currentTime().seconds - time)
            if off > Self.jump || (clock >= settlesAt && off > Self.drift) {
                start(player, at: time, clock: clock)
            }
        }
    }

    /// Plays from `time`, lined up with the host clock: the sound reaches
    /// `time + lead` at `clock + lead`, as the playhead will.
    private func start(_ player: AVPlayer, at time: Double, clock: Double) {
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let at = CMTimeAdd(host, CMTime(seconds: Self.lead, preferredTimescale: 1_000_000_000))
        player.setRate(1, time: CMTime(seconds: time + Self.lead, preferredTimescale: 48000), atHostTime: at)
        isPlaying = true
        settlesAt = clock + Self.settle
    }

    private func rebuild(_ project: Project) {
        player?.pause()
        player = nil
        let media = Dictionary(project.media.compactMap { a in locate(a.id).map { (a.id, $0) } }, uniquingKeysWith: { a, _ in a })
        guard let mix = AudioComposition(clips: clips, media: media) else { self.mix = nil; return }
        self.mix = mix
        length = mix.composition.duration.seconds
        let item = AVPlayerItem(asset: mix.composition)
        item.audioMix = mix.audioMix
        let player = AVPlayer(playerItem: item)
        // Needed for starting at a set moment, and a local file never stalls.
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
    }
}
