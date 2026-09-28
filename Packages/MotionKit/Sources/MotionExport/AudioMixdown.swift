import Foundation
import AVFoundation
import MotionEvaluation

/// The composition's sound for one export: every clip laid on its own track
/// of a composition at its time and volume, read back mixed in floating
/// point, kept under the ceiling by a `PeakLimiter` so overlapping clips
/// never clip, and fed to the writer from its own queue while the frames are
/// drawn.
///
/// Movies in MP4 get AAC. MOVs, ProRes especially, get uncompressed 16-bit
/// sound, which is what editing apps expect alongside ProRes. Anything that
/// stops the sound being heard is an error, never a silent movie.
final class AudioMixdown: @unchecked Sendable {
    let input: AVAssetWriterInput
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let queue = DispatchQueue(label: "Twine.export.audio")
    private let done = DispatchSemaphore(value: 0)
    private var started = false
    private let mix: AudioComposition
    private var limiter = PeakLimiter()
    /// Limited sound waiting for the writer to take it.
    private var waiting: [Float]?
    private var finishedReading = false
    private var framesWritten: Int64 = 0
    private static let rate = 48000.0
    /// Why the sound could not be written, if it could not.
    private(set) var failure: String?

    /// The sound from `start` for `duration` seconds. Nil when there are no
    /// clips to hear; throws when there are and any of them cannot be read,
    /// naming them by `names`.
    init?(clips: [AudioClip], media: [UUID: URL], names: [UUID: String], start: Double = 0, duration: Double,
          compressed: Bool) throws {
        guard !clips.isEmpty else { return nil }
        let mix = AudioComposition(clips: clips, media: media)
        if !mix.unheard.isEmpty {
            throw ExportError.soundUnreadable(mix.unheard.map { names[$0] ?? "a sound" })
        }
        guard !mix.tracks.isEmpty else { return nil }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: mix.composition)
        } catch {
            throw ExportError.failed("The sound couldn't be read: \(error.localizedDescription)")
        }
        let output = AVAssetReaderAudioMixOutput(audioTracks: mix.tracks, audioSettings: Self.floatSettings)
        output.audioMix = mix.audioMix
        let offset = CMTime(seconds: start, preferredTimescale: 48000)
        reader.timeRange = CMTimeRange(start: offset, duration: CMTime(seconds: duration, preferredTimescale: 48000))
        guard reader.canAdd(output) else { throw ExportError.failed("The sound couldn't be mixed.") }
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
    }

    /// Stereo 32-bit float at 48 kHz, interleaved: room above full scale, so
    /// loud overlaps reach the limiter whole instead of already clipped.
    private static var floatSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ] }

    /// Starts feeding the writer. Call after the writer has started.
    func start(job: ExportJob) {
        guard reader.startReading() else {
            failure = "The sound couldn't be read: \(reader.error?.localizedDescription ?? "it wouldn't start")."
            input.markAsFinished()
            done.signal()
            return
        }
        started = true
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                if job.isCancelled {
                    reader.cancelReading()
                    finish()
                    return
                }
                if let ready = waiting {
                    waiting = nil
                    guard append(ready) else { return }
                    continue
                }
                if finishedReading {
                    finish()
                    return
                }
                if let sample = output.copyNextSampleBuffer() {
                    let limited = limiter.process(Self.floats(in: sample))
                    if !limited.isEmpty { waiting = limited }
                } else {
                    if reader.status == .failed {
                        failure = "The sound couldn't be read: \(reader.error?.localizedDescription ?? "reading stopped")."
                    }
                    finishedReading = true
                    let rest = limiter.flush()
                    if !rest.isEmpty { waiting = rest }
                }
            }
        }
    }

    private func append(_ frames: [Float]) -> Bool {
        guard let sample = Self.sample(frames, at: framesWritten) else {
            failure = "The sound couldn't be prepared for the movie."
            finish()
            return false
        }
        guard input.append(sample) else {
            failure = "The sound couldn't be written to the movie."
            finish()
            return false
        }
        framesWritten += Int64(frames.count / 2)
        return true
    }

    private func finish() {
        input.markAsFinished()
        done.signal()
    }

    func cancel() {
        reader.cancelReading()
    }

    /// Waits until every sample is written or reading stopped, or until
    /// `stopped` says the export has (cancelled, or the writer failed), when
    /// the writer may never ask for more and the wait would last for ever.
    func wait(until stopped: () -> Bool) {
        guard started else { return }
        while done.wait(timeout: .now() + 0.1) == .timedOut {
            if stopped() {
                cancel()
                return
            }
        }
    }

    /// The interleaved samples a reader handed over.
    private static func floats(in sample: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var out = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        out.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        return out
    }

    /// Interleaved stereo floats as a sample buffer starting `start` frames
    /// into the movie. Times are counted from zero, so a movie of part of
    /// the composition hears the sound from its own start.
    private static func sample(_ frames: [Float], at start: Int64) -> CMSampleBuffer? {
        var description = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32,
            mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr, let format else { return nil }
        let bytes = frames.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = frames.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                          dataLength: bytes)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames.count / 2,
            presentationTimeStamp: CMTime(value: start, timescale: CMTimeScale(rate)), packetDescriptions: nil,
            sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}

/// The composition's sound laid out for AVFoundation: each clip on its own
/// tracks of a composition (one for every sound track its file has), at its
/// time, with its volume, or its fades as volume ramps, in an audio mix.
/// Export reads it; the editor's preview plays it.
public final class AudioComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let audioMix: AVMutableAudioMix
    let tracks: [AVAssetTrack]
    /// The media of clips that could not be heard: a file missing, without
    /// sound, or unreadable. Export refuses to go on without them.
    public let unheard: [UUID]
    /// Nothing to hear.
    public var isEmpty: Bool { tracks.isEmpty }
    /// The files the clips come from, kept open for as long as the mix is
    /// used: a composition does not hold on to them itself.
    private let sources: [AVURLAsset]

    public init(clips: [AudioClip], media: [UUID: URL]) {
        let composition = AVMutableComposition()
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 48000) }
        var parameters: [AVMutableAudioMixInputParameters] = []
        var tracks: [AVAssetTrack] = []
        var unheard: [UUID] = []
        var opened: [URL: (AVURLAsset, [AVAssetTrack])] = [:]
        for clip in clips {
            guard let url = media[clip.mediaID] else {
                if !unheard.contains(clip.mediaID) { unheard.append(clip.mediaID) }
                continue
            }
            if opened[url] == nil {
                let file = AVURLAsset(url: url)
                opened[url] = (file, Self.audioTracks(of: file))
            }
            let sources = opened[url]?.1 ?? []
            if sources.isEmpty, !unheard.contains(clip.mediaID) { unheard.append(clip.mediaID) }
            for source in sources {
                guard let track = composition.addMutableTrack(withMediaType: .audio,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                do {
                    try track.insertTimeRange(CMTimeRange(start: time(clip.sourceStart), duration: time(clip.duration)),
                                              of: source, at: time(clip.start))
                } catch {
                    if !unheard.contains(clip.mediaID) { unheard.append(clip.mediaID) }
                    composition.removeTrack(track)
                    continue
                }
                let p = AVMutableAudioMixInputParameters(track: track)
                let points = clip.envelope
                if let first = points.first {
                    // A fade is a run of straight ramps between the envelope's
                    // points; the level holds before the first and after the last.
                    if first.time > 0 { p.setVolume(Float(first.volume), at: .zero) }
                    for (a, b) in zip(points, points.dropFirst()) where b.time > a.time {
                        p.setVolumeRamp(fromStartVolume: Float(a.volume), toEndVolume: Float(b.volume),
                                        timeRange: CMTimeRange(start: time(a.time), end: time(b.time)))
                    }
                } else {
                    p.setVolume(Float(clip.volume), at: .zero)
                }
                parameters.append(p)
                tracks.append(track)
            }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        self.composition = composition
        audioMix = mix
        self.tracks = tracks
        self.unheard = unheard
        sources = opened.values.map(\.0)
    }

    private static func audioTracks(of asset: AVURLAsset) -> [AVAssetTrack] {
        let box = TrackBox()
        let wait = DispatchSemaphore(value: 0)
        let job = AssetBox(asset: asset)
        Task.detached {
            box.tracks = (try? await job.asset.loadTracks(withMediaType: .audio)) ?? []
            wait.signal()
        }
        wait.wait()
        return box.tracks
    }
}

private final class TrackBox: @unchecked Sendable {
    var tracks: [AVAssetTrack] = []
}

private struct AssetBox: @unchecked Sendable {
    let asset: AVURLAsset
}
