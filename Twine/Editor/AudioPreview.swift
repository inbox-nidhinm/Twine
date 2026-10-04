import Foundation
import AVFoundation
import QuartzCore
import MotionModel
import MotionEvaluation
import MotionExport

/// The composition's sound while it plays in the editor: the same clips an
/// export writes, mixed and kept under the ceiling as an export's are
/// (`LimitedMix`), so loud overlaps never crackle and what is heard is what
/// exports (4 October 2026; an `AVPlayer` mixed them before, with nothing
/// to limit the sum). It starts and stops with playback, and jumps when the
/// playhead jumps (a loop, a scrub) or drifts more than a few frames from it.
///
/// The sound is set going at a moment on the host clock, the one the
/// playhead's display clock runs on, a little ahead so it is ready, and
/// drift is only judged once it has had time to start, and not at all past
/// where the sound runs out. The stutter was the player, stopped at its end,
/// being sought on every frame and then, on the next loop, only nudged
/// along in jumps without ever playing again.
///
/// Nothing that reads the files runs on the main thread: with a dozen clips
/// the old player's `currentTime()` waited about 0.7 s a frame on a lock it
/// held while preparing its tracks (29 September 2026, two frames a second).
/// Reading and handing the sound over happen on `queue`; the renderer plays
/// it on the synchronizer's clock, which is the host clock, read at no cost.
@MainActor
final class AudioPreview {
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let renderer = AVSampleBufferAudioRenderer()
    private var mix: AudioComposition?
    private var clips: [AudioClip] = []
    private var isPlaying = false
    /// Where in the sound it was last set going, and when on the host clock.
    private var started = (time: 0.0, clock: 0.0)
    /// Where the sound runs out: past it there is nothing to line up until
    /// the playhead comes back.
    private var length = 0.0
    /// When, on the host clock, the sound last set going has had time to
    /// start.
    private var settlesAt = 0.0
    private let locate: (UUID) -> URL?
    /// Reading and handing over, one after another, so a restart's flush
    /// always comes after the old reading's last piece.
    private let queue = DispatchQueue(label: "Twine.preview.audio", qos: .userInteractive)
    private let feed: AudioFeed

    /// How far ahead the sound is set going, for the reading to be ready.
    private static let lead = 0.1
    /// How long a start is left alone before drift is judged.
    private static let settle = 0.3
    /// How far the sound may stray from the playhead before it jumps.
    private static let drift = 0.12
    /// Further than this is the playhead jumping, not the sound straying.
    private static let jump = 0.3

    init(locate: @escaping (UUID) -> URL?) {
        self.locate = locate
        feed = AudioFeed(renderer: renderer, queue: queue)
        synchronizer.addRenderer(renderer)
    }

    /// Brings the sound into line with the editor. Called on every tick of
    /// playback and whenever playback starts, stops or the playhead moves.
    func follow(_ project: Project, time: Double, playing: Bool) {
        guard playing else {
            if isPlaying { stop() }
            return
        }
        let now = audioClips(project)
        if now != clips {
            clips = now
            rebuild(project)
            if isPlaying { stop() }
        }
        guard let mix else { return }
        // Kept in step while silent, so turning the sound back on in
        // Settings is heard in its place.
        renderer.isMuted = !AppSettings.shared.playsSound
        let clock = CACurrentMediaTime()
        if !isPlaying {
            start(mix, at: time, clock: clock)
        } else if time < length - Self.drift {
            // A jump (a loop, a scrub) is followed at once: the playhead is
            // no longer where the sound set going would be.
            let expected = started.time + (clock - started.clock)
            if abs(expected - time) > Self.jump { return start(mix, at: time, clock: clock) }
            // A small stray, once the sound has settled, from the
            // synchronizer's own clock.
            guard clock >= settlesAt else { return }
            let heard = CMTimebaseGetTime(synchronizer.timebase).seconds
            if abs(heard - time) > Self.drift { start(mix, at: time, clock: clock) }
        }
    }

    /// Plays from `time`, lined up with the host clock: the sound reaches
    /// `time + lead` at `clock + lead`, as the playhead will.
    private func start(_ mix: AudioComposition, at time: Double, clock: Double) {
        let from = time + Self.lead
        feed.begin(mix, from: from, due: CACurrentMediaTime() + Self.lead)
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let at = CMTimeAdd(host, CMTime(seconds: Self.lead, preferredTimescale: 1_000_000_000))
        synchronizer.setRate(1, time: CMTime(seconds: from, preferredTimescale: 48000), atHostTime: at)
        isPlaying = true
        started = (time, clock)
        settlesAt = clock + Self.settle
    }

    #if SELFTEST
    /// For the test kit: the renderer's state, the synchronizer's place
    /// and rate, and how the reading under way is going.
    var state: String {
        let place = CMTimebaseGetTime(synchronizer.timebase).seconds
        return "status=\(renderer.status.rawValue) rate=\(synchronizer.rate) at=\(String(format: "%.3f", place))"
            + " playing=\(isPlaying) muted=\(renderer.isMuted) clips=\(clips.count) " + feed.counts.withLock { $0 }
    }
    #endif

    private func stop() {
        synchronizer.rate = 0
        feed.stop()
        isPlaying = false
    }

    private func rebuild(_ project: Project) {
        let media = Dictionary(project.media.compactMap { a in locate(a.id).map { (a.id, $0) } }, uniquingKeysWith: { a, _ in a })
        let mix = AudioComposition(clips: clips, media: media)
        self.mix = mix.isEmpty ? nil : mix
        length = mix.isEmpty ? 0 : mix.composition.duration.seconds
    }
}

/// Reads the limited sound and hands it to the renderer as it asks, all
/// on `queue`.
nonisolated private final class AudioFeed: @unchecked Sendable {
    private let renderer: AVSampleBufferAudioRenderer
    private let queue: DispatchQueue
    /// The reading under way; touched only on `queue`.
    private var reading: LimitedMix?
    #if SELFTEST
    /// For the test kit: pieces handed over in this reading, and how long
    /// before it was due to be heard the first one was ready.
    let counts = Locked("pieces=0 early=-")
    /// Touched only on `queue`.
    private var pieces = 0
    #endif

    init(renderer: AVSampleBufferAudioRenderer, queue: DispatchQueue) {
        self.renderer = renderer
        self.queue = queue
    }

    /// Drops what was handed over and reads from `from` instead.
    /// `due` is when, on the host clock, its first moment is to be heard.
    func begin(_ mix: AudioComposition, from: Double, due: Double) {
        queue.async { [self] in
            halt()
            guard let next = LimitedMix(mix, from: from) else { return }
            reading = next
            #if SELFTEST
            pieces = 0
            #endif
            // Weakly, so a preview let go while playing takes its renderer with it.
            renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard let self else { return }
                while renderer.isReadyForMoreMediaData {
                    guard reading === next, let piece = next.next() else {
                        renderer.stopRequestingMediaData()
                        return
                    }
                    renderer.enqueue(piece)
                    #if SELFTEST
                    pieces += 1
                    let count = pieces
                    let early = count == 1 ? String(format: "%.3f", due - CACurrentMediaTime()) : nil
                    counts.withLock { line in
                        let before = line.components(separatedBy: "early=").last ?? "-"
                        line = "pieces=\(count) early=\(early ?? before)"
                    }
                    #endif
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in halt() }
    }

    private func halt() {
        renderer.stopRequestingMediaData()
        reading?.cancel()
        reading = nil
        renderer.flush()
    }
}
