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
///
/// The player is never asked where it is on the main thread: with a dozen
/// clips, `currentTime()` waited about 0.7 s a frame on a lock the player
/// holds while it prepares its tracks, the playhead fell behind, the sound
/// was set going again, and the player prepared again (29 September 2026,
/// two frames a second). Jumps are judged from where the sound was set
/// going and when; the player's own place comes from a time observer, which
/// the player reports in its own time.
@MainActor
final class AudioPreview {
    private var player: AVPlayer?
    private var observer: Any?
    private var mix: AudioComposition?
    private var clips: [AudioClip] = []
    private var isPlaying = false
    /// Where in the sound it was last set going, and when on the host clock.
    private var started = (time: 0.0, clock: 0.0)
    /// The player's own place as it last reported it, and when.
    private var reported: (time: Double, clock: Double)?
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
        // Kept in step while silent, so turning the sound back on in
        // Settings is heard in its place.
        player.isMuted = !AppSettings.shared.playsSound
        let clock = CACurrentMediaTime()
        if !isPlaying {
            start(player, at: time, clock: clock)
        } else if time < length - Self.drift {
            // A jump (a loop, a scrub) is followed at once: the playhead is
            // no longer where the sound set going would be.
            let expected = started.time + (clock - started.clock)
            if abs(expected - time) > Self.jump { return start(player, at: time, clock: clock) }
            // A small stray, once the sound has settled, from what the
            // player last said, carried on to now.
            guard clock >= settlesAt, let reported, reported.clock >= settlesAt else { return }
            let heard = reported.time + (clock - reported.clock)
            if abs(heard - time) > Self.drift { start(player, at: time, clock: clock) }
        }
    }

    /// Plays from `time`, lined up with the host clock: the sound reaches
    /// `time + lead` at `clock + lead`, as the playhead will.
    private func start(_ player: AVPlayer, at time: Double, clock: Double) {
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let at = CMTimeAdd(host, CMTime(seconds: Self.lead, preferredTimescale: 1_000_000_000))
        player.setRate(1, time: CMTime(seconds: time + Self.lead, preferredTimescale: 48000), atHostTime: at)
        isPlaying = true
        started = (time, clock)
        reported = nil
        settlesAt = clock + Self.settle
    }

    private func rebuild(_ project: Project) {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player = nil
        let media = Dictionary(project.media.compactMap { a in locate(a.id).map { (a.id, $0) } }, uniquingKeysWith: { a, _ in a })
        let mix = AudioComposition(clips: clips, media: media)
        guard !mix.isEmpty else { self.mix = nil; return }
        self.mix = mix
        length = mix.composition.duration.seconds
        let item = AVPlayerItem(asset: mix.composition)
        item.audioMix = mix.audioMix
        let player = AVPlayer(playerItem: item)
        // Needed for starting at a set moment, and a local file never stalls.
        player.automaticallyWaitsToMinimizeStalling = false
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.reported = (t.seconds, CACurrentMediaTime())
            }
        }
        self.player = player
    }
}
