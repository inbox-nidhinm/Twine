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
    FileManager.default.temporaryDirectory.appendingPathComponent("Twine-media-\(UUID().uuidString).\(ext)")
}

/// A one-second, 30 fps, 64 by 64 movie of Twine's own making: black, with
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

/// A 20 by 20 picture in four colours, so which way up and which way round
/// it is drawn shows: red top-left, green top-right, blue bottom-left and
/// white bottom-right.
private func quarteredPicture() throws -> URL {
    let url = temporaryURL("png")
    let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Core Graphics counts rows from the bottom.
    for (x, y, color) in [(0, 10, (1.0, 0.0, 0.0)), (10, 10, (0.0, 1.0, 0.0)), (0, 0, (0.0, 0.0, 1.0)), (10, 0, (1.0, 1.0, 1.0))] {
        context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fill(CGRect(x: x, y: y, width: 10, height: 10))
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return url
}

private func pictureShape(_ paint: ImagePaint) -> ShapeContent {
    ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .image(paint))])
}

/// A 64 by 64 still of one picture-filled square, 40 across with its
/// top-left at the origin, as the colour names of the pixels asked for.
private func pictureColours(_ paint: (UUID) -> ImagePaint, at points: [(Int, Int)],
                            file: URL, pixels: (Int, Int)) throws -> [String] {
    let asset = MediaAsset(kind: .image, fileName: "q.png", originalName: "q.png", contentHash: "q",
                           pixelWidth: pixels.0, pixelHeight: pixels.1)
    var layer = Layer(name: "Q", content: .shape(pictureShape(paint(asset.id))), size: Size2(40, 40), position: .zero)
    layer.transform.anchor = .zero
    let project = Project(composition: Composition(width: 64, height: 64, background: Background(isTransparent: true)),
                          layers: [layer], media: [asset])
    let url = temporaryURL("png")
    defer { try? FileManager.default.removeItem(at: url) }
    try Exporter.export(project, settings: ExportSettings(format: .png), to: url, media: [asset.id: file])
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    return points.map { x, y in
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - 64 + 1, width: 64, height: 64))
        let (r, g, b, a) = (bytes[0] > 128, bytes[1] > 128, bytes[2] > 128, bytes[3] > 128)
        switch (r, g, b, a) {
        case (_, _, _, false): return "clear"
        case (true, false, false, _): return "red"
        case (false, true, false, _): return "green"
        case (false, false, true, _): return "blue"
        case (true, true, true, _): return "white"
        default: return "\(bytes)"
        }
    }
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

    @Test func volumeFadesAreHeardInTheMovie() async throws {
        let sound = try tone(seconds: 2)
        defer { try? FileManager.default.removeItem(at: sound) }
        let asset = MediaAsset(kind: .audio, fileName: "t.wav", originalName: "t.wav", contentHash: "v", duration: 2)
        let layer = Layer(name: "Tone", content: .audio(AudioContent(mediaID: asset.id)), size: Size2(0, 0), position: .zero)
        let play = Action(target: layer.id, start: 0, duration: 2, spec: .play(PlayAction()))
        // Down to nothing, evenly, from 0.5 s to 1.5 s.
        let fade = Action(target: layer.id, start: 0.5, duration: 1, easing: .linear, spec: .volume(VolumeAction(end: 0)))
        let project = Project(composition: Composition(width: 64, height: 64, frameRate: .fps30, duration: 2),
                              layers: [layer], actions: [play, fade], media: [asset])
        for format in [ExportFormat.h264, .proRes422] {
            let url = temporaryURL(format.fileExtension)
            defer { try? FileManager.default.removeItem(at: url) }
            try Exporter.export(project, settings: ExportSettings(format: format), to: url, media: [asset.id: sound])
            let levels = try await loudness(of: url)
            try #require(levels.count >= 18, "\(format)")
            // A sine of amplitude 0.5 has a loudness of about 0.35.
            let full = levels[2]
            #expect(full > 0.3, "full before the fade, \(format)")
            #expect(abs(levels[10] / full - 0.5) < 0.08, "half way through the fade, \(format): \(levels[10] / full)")
            #expect(levels[17] < 0.01, "silent after it, \(format)")
        }
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
        var layer = Layer(name: "Red", content: .shape(pictureShape(ImagePaint(mediaID: asset.id))), size: Size2(40, 20), position: .zero)
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

    // The corners of the 40 pixel square, then its middle row.
    private let quarters = [(10, 10), (30, 10), (10, 30), (30, 30)]

    @Test func aFilledPictureIsTheRightWayUpAndRound() throws {
        let file = try quarteredPicture()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try pictureColours({ ImagePaint(mediaID: $0) }, at: quarters, file: file, pixels: (20, 20))
                == ["red", "green", "blue", "white"])
    }

    @Test func aTurnedPictureTurnsClockwise() throws {
        let file = try quarteredPicture()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try pictureColours({ ImagePaint(mediaID: $0, quarterTurns: 1) }, at: quarters, file: file, pixels: (20, 20))
                == ["blue", "red", "white", "green"])
    }

    @Test func aFittedPictureLeavesTheRestOfTheBoxEmpty() throws {
        let file = try redPicture()
        defer { try? FileManager.default.removeItem(at: file) }
        // 20 by 10 fits the 40 square as 40 by 20, from 10 to 30 down.
        #expect(try pictureColours({ ImagePaint(mediaID: $0, mode: .fit) }, at: [(20, 5), (20, 20), (20, 35)],
                                   file: file, pixels: (20, 10)) == ["clear", "red", "clear"])
        // Filling, it covers the square and spills over the sides.
        #expect(try pictureColours({ ImagePaint(mediaID: $0, mode: .fill) }, at: [(20, 5), (20, 20), (20, 35)],
                                   file: file, pixels: (20, 10)) == ["red", "red", "red"])
    }

    @Test func aTiledPictureRepeatsAtItsScale() throws {
        let file = try quarteredPicture()
        defer { try? FileManager.default.removeItem(at: file) }
        // Tiles of 10 pixels, each with 5 pixel quarters.
        #expect(try pictureColours({ ImagePaint(mediaID: $0, mode: .tile, tileScale: 0.5) },
                                   at: [(2, 2), (7, 2), (12, 2), (2, 7), (37, 37)], file: file, pixels: (20, 20))
                == ["red", "green", "red", "blue", "white"])
    }

    @Test func aCroppedPictureShowsOnlyItsPart() throws {
        let file = try quarteredPicture()
        defer { try? FileManager.default.removeItem(at: file) }
        // Twice the box's size and pulled up and left by a box: only the
        // picture's bottom-right quarter shows.
        let crop = ImageCrop(x: -1, y: -1, width: 2, height: 2)
        #expect(try pictureColours({ ImagePaint(mediaID: $0, mode: .crop, crop: crop) }, at: [(3, 3), (36, 36), (45, 20)],
                                   file: file, pixels: (20, 20)) == ["white", "white", "clear"])
    }
}
