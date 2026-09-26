import Foundation
import AVFoundation
import MotionEvaluation

/// The composition's sound for one export: every clip laid on its own track
/// of a composition at its time and volume, read back mixed, and fed to the
/// writer from its own queue while the frames are drawn.
///
/// Movies in MP4 get AAC. MOVs, ProRes especially, get uncompressed 16-bit
/// sound, which is what editing apps expect alongside ProRes.
final class AudioMixdown: @unchecked Sendable {
    let input: AVAssetWriterInput
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let queue = DispatchQueue(label: "eMotion.export.audio")
    private let done = DispatchSemaphore(value: 0)
    private var started = false
    private let mix: AudioComposition
    /// Where the movie starts in the composition: the sound is read from
    /// here and moved back to start at zero, with the frames.
    private let offset: CMTime

    /// The sound from `start` for `duration` seconds. Nil when there is
    /// nothing to hear: no clips, or none of their files.
    init?(clips: [AudioClip], media: [UUID: URL], start: Double = 0, duration: Double, compressed: Bool) {
        guard let mix = AudioComposition(clips: clips, media: media),
              let reader = try? AVAssetReader(asset: mix.composition) else { return nil }
        let output = AVAssetReaderAudioMixOutput(audioTracks: mix.tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix.audioMix
        let offset = CMTime(seconds: start, preferredTimescale: 48000)
        reader.timeRange = CMTimeRange(start: offset, duration: CMTime(seconds: duration, preferredTimescale: 48000))
        guard reader.canAdd(output) else { return nil }
        reader.add(output)

        let settings: [String: Any] = compressed
            ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
               AVEncoderBitRateKey: 256_000]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
               AVLinearPCMIsNonInterleaved: false]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        self.reader = reader
        self.output = output
        self.mix = mix
        self.offset = offset
    }

    /// A sample moved back by `offset`, so a movie of part of the
    /// composition hears the sound from its own start.
    private func shifted(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard offset != .zero else { return sample }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in timing.indices {
            timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - offset
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - offset }
        }
        var moved: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &moved)
        return moved
    }

    /// Starts feeding the writer. Call after the writer has started.
    func start(job: ExportJob) {
        guard reader.startReading() else {
            input.markAsFinished()
            done.signal()
            return
        }
        started = true
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                if job.isCancelled {
                    reader.cancelReading()
                    input.markAsFinished()
                    done.signal()
                    return
                }
                guard let sample = output.copyNextSampleBuffer().flatMap(shifted), input.append(sample) else {
                    input.markAsFinished()
                    done.signal()
                    return
                }
            }
        }
    }

    func cancel() {
        reader.cancelReading()
    }

    /// Waits until every sample is written, or reading stopped.
    func wait() {
        guard started else { return }
        done.wait()
    }
}

/// The composition's sound laid out for AVFoundation: each clip on its own
/// track of a composition, at its time, with its volume in an audio mix.
/// Export reads it; the editor's preview plays it.
public final class AudioComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let audioMix: AVMutableAudioMix
    let tracks: [AVAssetTrack]
    /// The files the clips come from, kept open for as long as the mix is
    /// used: a composition does not hold on to them itself.
    private let sources: [AVURLAsset]

    /// Nil when there is nothing to hear: no clips, or none of their files.
    public init?(clips: [AudioClip], media: [UUID: URL]) {
        let composition = AVMutableComposition()
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 48000) }
        var parameters: [AVMutableAudioMixInputParameters] = []
        var tracks: [AVAssetTrack] = []
        var opened: [URL: (AVURLAsset, AVAssetTrack?)] = [:]
        for clip in clips {
            guard let url = media[clip.mediaID] else { continue }
            if opened[url] == nil {
                let file = AVURLAsset(url: url)
                opened[url] = (file, Self.firstAudioTrack(of: file))
            }
            guard let source = opened[url]?.1,
                  let track = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            do {
                try track.insertTimeRange(CMTimeRange(start: time(clip.sourceStart), duration: time(clip.duration)),
                                          of: source, at: time(clip.start))
            } catch {
                continue
            }
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(Float(clip.volume), at: .zero)
            parameters.append(p)
            tracks.append(track)
        }
        guard !tracks.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        self.composition = composition
        audioMix = mix
        self.tracks = tracks
        sources = opened.values.map(\.0)
    }

    private static func firstAudioTrack(of asset: AVURLAsset) -> AVAssetTrack? {
        let box = TrackBox()
        let wait = DispatchSemaphore(value: 0)
        let job = AssetBox(asset: asset)
        Task.detached {
            box.track = try? await job.asset.loadTracks(withMediaType: .audio).first
            wait.signal()
        }
        wait.wait()
        return box.track
    }
}

private final class TrackBox: @unchecked Sendable {
    var track: AVAssetTrack?
}

private struct AssetBox: @unchecked Sendable {
    let asset: AVURLAsset
}
