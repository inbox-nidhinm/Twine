import Foundation
import AVFoundation

/// The composition's sound from a moment on, mixed and kept under the
/// ceiling exactly as an export hears it (`AudioMixdown`), a piece at a time:
/// what the editor's preview plays, so loud overlaps never crackle there
/// either (4 October 2026; until then the preview was an `AVPlayer` mixing
/// the clips itself, with nothing to limit the sum).
///
/// Each piece is stamped with its place in the composition, so a renderer
/// on the composition's clock plays it where it belongs. Read it on one
/// queue at a time.
public final class LimitedMix: @unchecked Sendable {
    private let mix: AudioComposition
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private var limiter = PeakLimiter()
    /// Where the next piece starts in the composition, in frames at 48 kHz.
    private var frame: Int64
    private var finished = false

    /// The sound from `start` seconds to the end. Nil when there is nothing
    /// to hear from there, or it cannot be read.
    public init?(_ mix: AudioComposition, from start: Double) {
        let end = mix.composition.duration
        let first = Int64((max(start, 0) * 48000).rounded())
        guard !mix.isEmpty, end.isNumeric, CMTime(value: first, timescale: 48000) < end,
              let reader = try? AVAssetReader(asset: mix.composition) else { return nil }
        let output = AVAssetReaderAudioMixOutput(audioTracks: mix.tracks, audioSettings: AudioMixdown.floatSettings)
        output.audioMix = mix.audioMix
        reader.timeRange = CMTimeRange(start: CMTime(value: first, timescale: 48000), end: end)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        self.mix = mix
        self.reader = reader
        self.output = output
        frame = first
    }

    /// The next piece, limited and stamped with its place in the
    /// composition; nil once everything has been handed over.
    public func next() -> CMSampleBuffer? {
        while !finished {
            let limited: [Float]
            if let sample = output.copyNextSampleBuffer() {
                limited = limiter.process(AudioMixdown.floats(in: sample))
            } else {
                finished = true
                limited = limiter.flush()
            }
            guard !limited.isEmpty else { continue }
            let piece = AudioMixdown.sample(limited, at: frame)
            frame += Int64(limited.count / 2)
            return piece
        }
        return nil
    }

    /// Stops reading; `next` hands over nothing more.
    public func cancel() {
        finished = true
        reader.cancelReading()
    }
}
