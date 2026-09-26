import Foundation
import Testing
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MotionModel
@testable import MotionExport
import MotionRendering

private func temporaryURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("eMotion-media-\(UUID().uuidString).\(ext)")
}

/// A one-second, 30 fps, 64 by 64 movie of eMotion's own making: black, with
/// a white bar whose height counts the frames, so a frame shows which one it
/// is. Frame n is n * 2 pixels tall.
private func countingProject() -> Project {
    var bar = Layer(name: "Bar", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                              fills: [Fill(paint: .color(.white))])),
                    size: Size2(64, 0), position: .zero)
    bar.transform.anchor = .zero
    let grow = Action(target: bar.id, start: 0, duration: 1, easing: .linear,
                      spec: .resize(ResizeAction(initial: Size2(64, 0), end: Size2(64, 60))))
    return Project(composition: Composition(width: 64, height: 64, frameRate: .fps30, duration: 1,
                                            background: Background(color: .black)),
                   layers: [bar], actions: [grow])
}

private func countingMovie() throws -> URL {
    let url = temporaryURL("mov")
    try Exporter.export(countingProject(), settings: ExportSettings(format: .proRes422), to: url)
    return url
}

/// A mono tone at 48 kHz, as a WAV file.
private func tone(seconds: Double) throws -> URL {
    let url = temporaryURL("wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(seconds * 48000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000) * 0.5) }
    try file.write(from: buffer)
    return url
}

private func redPicture() throws -> URL {
    let url = temporaryURL("png")
    let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return url
}

private func frames(of url: URL) async throws -> [CVPixelBuffer] {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(output)
    reader.startReading()
    var out: [CVPixelBuffer] = []
    while let sample = output.copyNextSampleBuffer() {
        if let buffer = CMSampleBufferGetImageBuffer(sample) { out.append(buffer) }
    }
    return out
}

/// How many rows from the bottom of column 32 are white: the bar's height.
private func barHeight(_ buffer: CVPixelBuffer) -> Int {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer), h = CVPixelBufferGetHeight(buffer)
    return (0..<h).filter { base[$0 * row + 32 * 4 + 1] > 128 }.count
}

/// The loudness of each tenth of a second of the movie's sound.
private func loudness(of url: URL) async throws -> [Double] {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
    ])
    reader.add(output)
    reader.startReading()
    var samples: [Float] = []
    while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
        samples += chunk
    }
    return stride(from: 0, to: samples.count, by: 4800).map { i in
        let window = samples[i..<min(i + 4800, samples.count)]
        return sqrt(window.map { Double($0 * $0) }.reduce(0, +) / Double(max(window.count, 1)))
    }
}

@Suite(.serialized) struct MediaExportTests {
    @Test func videoPlaysFromWhereItsPlayBarSays() async throws {
        let movie = try countingMovie()
        defer { try? FileManager.default.removeItem(at: movie) }
        let asset = MediaAsset(kind: .video, fileName: "c.mov", originalName: "c.mov", contentHash: "x",
                               pixelWidth: 64, pixelHeight: 64, duration: 1)
        var layer = Layer(name: "Clip", content: .video(VideoContent(mediaID: asset.id)), size: Size2(64, 64),
                          position: Vec2(32, 32))
        layer.transform.anchor = Vec2(32, 32)
        // Starts half a second in, from a third of a second into the file,
        // for a third of a second.
        let play = Action(target: layer.id, start: 0.5, duration: 1.0 / 3, spec: .play(PlayAction(trimStart: 1.0 / 3)))
        let project = Project(composition: Composition(width: 64, height: 64, frameRate: .fps30, duration: 1),
                              layers: [layer], actions: [play], media: [asset])
        let url = temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(project, settings: ExportSettings(format: .proRes422), to: url, media: [asset.id: movie])
        let out = try await frames(of: url).map(barHeight)
        #expect(out.count == 30)
        // Before its bar: the first frame it will play, file frame 10.
        #expect(abs(out[0] - 20) <= 1)
        // During: file frame 10 + n at output frame 15 + n.
        #expect(abs(out[20] - 30) <= 1)
        // After: resting on the last frame it played, file frame 20.
        #expect(abs(out[29] - 40) <= 1)
    }

    @Test func soundIsHeardOnlyDuringItsPlayBar() async throws {
        let sound = try tone(seconds: 2)
        defer { try? FileManager.default.removeItem(at: sound) }
        let asset = MediaAsset(kind: .audio, fileName: "t.wav", originalName: "t.wav", contentHash: "y", duration: 2)
        let layer = Layer(name: "Tone", content: .audio(AudioContent(mediaID: asset.id)), size: Size2(0, 0), position: .zero)
        let play = Action(target: layer.id, start: 0.5, duration: 1, spec: .play(PlayAction()))
        let project = Project(composition: Composition(width: 64, height: 64, frameRate: .fps30, duration: 2),
                              layers: [layer], actions: [play], media: [asset])
        for format in [ExportFormat.h264, .proRes4444] {
            let url = temporaryURL(format.fileExtension)
            defer { try? FileManager.default.removeItem(at: url) }
            try Exporter.export(project, settings: ExportSettings(format: format), to: url, media: [asset.id: sound])
            let levels = try await loudness(of: url)
            // The sound runs to the end of its last clip, then the movie
            // simply has none.
            try #require(levels.count >= 15, "\(format)")
            #expect(levels[2] < 0.01, "silent before its bar, \(format)")
            #expect(levels[8] > 0.2, "the tone during it, \(format)")
            #expect(levels.dropFirst(16).allSatisfy { $0 < 0.01 }, "silent after, \(format)")
        }
        // Muted, the movie has no sound at all.
        var muted = project
        muted.layers[0].content = .audio(AudioContent(mediaID: asset.id, isMuted: true))
        let url = temporaryURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(muted, settings: ExportSettings(format: .h264), to: url, media: [asset.id: sound])
        #expect(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func aRangeHoldsOnlyItsFrames() async throws {
        let url = temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(countingProject(), settings: ExportSettings(format: .proRes422), frames: 10..<20, to: url)
        let out = try await frames(of: url).map(barHeight)
        #expect(out.count == 10)
        // Frame n of the composition is n * 2 pixels tall.
        #expect(abs(out[0] - 20) <= 1)
        #expect(abs(out[9] - 38) <= 1)
    }

    @Test func aRangeCarriesItsOwnStretchOfSound() async throws {
        let sound = try tone(seconds: 2)
        defer { try? FileManager.default.removeItem(at: sound) }
        let asset = MediaAsset(kind: .audio, fileName: "t.wav", originalName: "t.wav", contentHash: "y", duration: 2)
        let layer = Layer(name: "Tone", content: .audio(AudioContent(mediaID: asset.id)), size: Size2(0, 0), position: .zero)
        // Heard from 0.5 to 1.5; the export runs from 1 to 2, so it is
        // heard for its first half second only.
        let play = Action(target: layer.id, start: 0.5, duration: 1, spec: .play(PlayAction()))
        let project = Project(composition: Composition(width: 64, height: 64, frameRate: .fps30, duration: 2),
                              layers: [layer], actions: [play], media: [asset])
        for format in [ExportFormat.h264, .proRes4444] {
            let url = temporaryURL(format.fileExtension)
            defer { try? FileManager.default.removeItem(at: url) }
            let range = ExportTiming.frames(from: 1, to: 2, in: project.composition)
            try Exporter.export(project, settings: ExportSettings(format: format), frames: range, to: url,
                                media: [asset.id: sound])
            let levels = try await loudness(of: url)
            try #require(levels.count >= 5, "\(format)")
            #expect(levels[2] > 0.2, "the tone at the start, \(format)")
            #expect(levels.dropFirst(6).allSatisfy { $0 < 0.01 }, "silent after its bar, \(format)")
            let video = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
            let length = try await video.load(.timeRange).duration.seconds
            #expect(abs(length - 1) < 0.001, "\(format)")
        }
    }

    @Test func picturesDrawAndMissingFilesShowGrey() throws {
        let picture = try redPicture()
        defer { try? FileManager.default.removeItem(at: picture) }
        let asset = MediaAsset(kind: .image, fileName: "r.png", originalName: "r.png", contentHash: "z",
                               pixelWidth: 20, pixelHeight: 10)
        var layer = Layer(name: "Red", content: .image(ImageContent(mediaID: asset.id)), size: Size2(40, 20), position: .zero)
        layer.transform.anchor = .zero
        let project = Project(composition: Composition(width: 64, height: 64, background: Background(isTransparent: true)),
                              layers: [layer], media: [asset])
        func pixel(_ media: [UUID: URL]) throws -> (Int, Int, Int) {
            let url = temporaryURL("png")
            defer { try? FileManager.default.removeItem(at: url) }
            try Exporter.export(project, settings: ExportSettings(format: .png), to: url, media: media)
            let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -30, y: -(64 - 10 - 1), width: 64, height: 64))
            return (Int(bytes[0]), Int(bytes[1]), Int(bytes[3]))
        }
        let red = try pixel([asset.id: picture])
        #expect(red.0 > 250 && red.1 < 5 && red.2 == 255)
        let missing = try pixel([:])
        #expect(missing.0 > 100 && missing.0 < 160 && missing.1 > 100 && missing.2 == 255)
    }
}
