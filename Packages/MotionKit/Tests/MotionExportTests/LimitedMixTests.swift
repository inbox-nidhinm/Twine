import Foundation
import Testing
import AVFoundation
import MotionModel
import MotionEvaluation
@testable import MotionExport

/// A mono WAV at 48 kHz of a 440 Hz tone at `level`.
private func tone(seconds: Double, level: Float) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Twine-limited-\(UUID().uuidString).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(seconds * 48000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frames) { data[i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000)) * level }
    try file.write(from: buffer)
    return url
}

/// Everything a mix hands over: the first piece's time and every sample.
private func drain(_ mix: LimitedMix) -> (first: Double?, samples: [Float]) {
    var first: Double?
    var out: [Float] = []
    while let piece = mix.next() {
        if first == nil { first = CMSampleBufferGetPresentationTimeStamp(piece).seconds }
        out += AudioMixdown.floats(in: piece)
    }
    return (first, out)
}

@Suite struct LimitedMixTests {
    @Test func loudOverlapsStayUnderTheCeilingFromWhereReadingStarts() throws {
        // Three clips of a tone at 0.8, all at once: 2.4 at its peak unlimited.
        let file = try tone(seconds: 2, level: 0.8)
        let id = UUID()
        let clips = (0..<3).map { _ in AudioClip(mediaID: id, start: 0, sourceStart: 0, duration: 2, volume: 1) }
        let mix = AudioComposition(clips: clips, media: [id: file])
        let read = try #require(LimitedMix(mix, from: 0.5))
        let (first, samples) = drain(read)
        #expect(abs((first ?? -1) - 0.5) < 1e-6, "stamped with its place in the composition")
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak <= PeakLimiter.defaultCeiling + 1e-4)
        #expect(peak > 0.8, "still loud, only held under the ceiling")
        // A second and a half, both channels.
        #expect(abs(samples.count - 72_000 * 2) < 2_048)
    }

    @Test func aQuietClipPassesUntouched() throws {
        let file = try tone(seconds: 1, level: 0.3)
        let id = UUID()
        let mix = AudioComposition(clips: [AudioClip(mediaID: id, start: 0, sourceStart: 0, duration: 1, volume: 1)],
                                   media: [id: file])
        let (_, samples) = drain(try #require(LimitedMix(mix, from: 0)))
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(abs(peak - 0.3) < 0.01)
    }

    @Test func thereIsNothingToReadPastTheEnd() throws {
        let file = try tone(seconds: 1, level: 0.3)
        let id = UUID()
        let mix = AudioComposition(clips: [AudioClip(mediaID: id, start: 0, sourceStart: 0, duration: 1, volume: 1)],
                                   media: [id: file])
        #expect(LimitedMix(mix, from: 1.5) == nil)
        #expect(LimitedMix(AudioComposition(clips: [], media: [:]), from: 0) == nil)
    }
}
