import Foundation
import AVFoundation

/// Each sound's loudness, read once per file in the background, for drawing
/// in its Play bars: a hundred peaks a second, from 0 to 1, where 1 is the
/// file's loudest.
@MainActor
final class Waveforms {
    nonisolated static let peaksPerSecond = 100.0

    private var peaks: [UUID: [Float]] = [:]
    private var reading: Set<UUID> = []
    /// Called when a file's peaks arrive, to draw them.
    var onChange: () -> Void = {}

    /// The peaks, or nil while they are still being read (or the file will
    /// not open).
    /// Lets go of the waveforms of sounds no layer plays any more.
    func keep(only used: Set<UUID>) {
        peaks = peaks.filter { used.contains($0.key) }
    }

    func peaks(for mediaID: UUID, at url: URL?) -> [Float]? {
        if let known = peaks[mediaID] { return known }
        guard let url, !reading.contains(mediaID) else { return nil }
        reading.insert(mediaID)
        Task.detached(priority: .utility) {
            let read = await Self.read(url)
            await MainActor.run {
                self.peaks[mediaID] = read
                self.onChange()
            }
        }
        return nil
    }

    /// The tracks are awaited, not waited for: a task blocked on a
    /// semaphore for another task holds one of the few shared threads, and
    /// enough sounds read at once could leave none to finish the loading.
    nonisolated private static func read(_ url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        // Every sound track mixed, as export hears them.
        guard !tracks.isEmpty, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let rate = 8000.0
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return [] }
        let perPeak = Int(rate / peaksPerSecond)
        var result: [Float] = []
        var loudest: Int16 = 0
        var count = 0
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let length = CMBlockBufferGetDataLength(block)
            var values = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &values)
            for v in values {
                loudest = max(loudest, v == Int16.min ? Int16.max : abs(v))
                count += 1
                if count == perPeak {
                    result.append(Float(loudest) / Float(Int16.max))
                    loudest = 0
                    count = 0
                }
            }
        }
        // Scaled to the file's own loudest moment, so a quiet recording
        // still shows its shape.
        let loudestPeak = result.max() ?? 0
        return loudestPeak > 0 ? result.map { $0 / loudestPeak } : result
    }
}
