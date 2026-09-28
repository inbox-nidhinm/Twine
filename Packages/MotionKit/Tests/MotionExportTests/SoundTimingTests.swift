import Foundation
import Testing
import AVFoundation
import MotionModel
@testable import MotionExport

private func temporaryURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("Twine-timing-\(UUID().uuidString).\(ext)")
}

/// A mono WAV at 48 kHz: silence, with one full-scale sample at each of
/// `clicks` (seconds), or a quiet tone throughout with `tone`.
private func sound(seconds: Double, clicks: [Double] = [], tone: Bool = false) throws -> URL {
    let url = temporaryURL("wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(seconds * 48000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frames) { data[i] = tone ? Float(sin(Double(i) * 2 * .pi * 440 / 48000) * 0.3) : 0 }
    for click in clicks { data[Int(click * 48000)] = 0.9 }
    try file.write(from: buffer)
    return url
}

/// Every sample of a movie's sound, the left channel, as floats.
private func samples(of url: URL) async throws -> [Float] {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
    ])
    reader.add(output)
    reader.startReading()
    var out: [Float] = []
    while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        out += stride(from: 0, to: chunk.count, by: 2).map { chunk[$0] }
    }
    return out
}

@Suite struct SoundTimingTests {
    private func project(sound duration: Double, bar: (start: Double, length: Double), assetLength: Double? = nil)
        -> (Project, MediaAsset) {
        let asset = MediaAsset(kind: .audio, fileName: "s.wav", originalName: "s.wav", contentHash: UUID().uuidString,
                               duration: assetLength ?? duration)
        let layer = Layer(name: "S", content: .audio(AudioContent(mediaID: asset.id)), size: Size2(0, 0), position: .zero)
        let play = Action(target: layer.id, start: bar.start, duration: bar.length, spec: .play(PlayAction()))
        return (Project(composition: Composition(width: 64, height: 64, frameRate: .fps30, duration: 3),
                        layers: [layer], actions: [play], media: [asset]), asset)
    }

    @Test func aClickLandsOnItsOwnSampleInARange() async throws {
        // A click 0.75 s into the sound, whose bar starts at 0.5 s: 1.25 s
        // into the composition, so 0.25 s into a movie of 1 s to 2 s.
        let file = try sound(seconds: 1.5, clicks: [0.75])
        defer { try? FileManager.default.removeItem(at: file) }
        let (project, asset) = project(sound: 1.5, bar: (0.5, 1.5))
        let url = temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let range = ExportTiming.frames(from: 1, to: 2, in: project.composition)
        try Exporter.export(project, settings: ExportSettings(format: .proRes422), frames: range, to: url,
                            media: [asset.id: file])
        let heard = try await samples(of: url)
        let loudest = try #require(heard.indices.max { abs(heard[$0]) < abs(heard[$1]) })
        #expect(abs(loudest - 12_000) <= 1, "the click at sample \(loudest), not 12000")
    }

    @Test func aSoundShorterThanItsBarStillExports() async throws {
        // A phone clip's sound often stops a little before its picture, so
        // the bar, as long as the clip, outruns the sound.
        let file = try sound(seconds: 1, tone: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let (project, asset) = project(sound: 1, bar: (0, 1.5), assetLength: 1.5)
        let url = temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(project, settings: ExportSettings(format: .proRes422), to: url, media: [asset.id: file])
        let heard = try await samples(of: url)
        #expect(heard[12_000..<24_000].contains { abs($0) > 0.2 }, "the tone while it lasts")
        if heard.count > 60_000 { #expect(heard[60_000...].allSatisfy { abs($0) < 0.01 }, "silence after") }
    }
}
