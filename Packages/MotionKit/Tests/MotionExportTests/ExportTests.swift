import Foundation
import Testing
import AVFoundation
import CoreGraphics
import ImageIO
import MotionModel
@testable import MotionExport

/// A small composition: a half-transparent red square that moves right by
/// 20 px over its one second, on a blue ground that can be switched off.
private func project(transparent: Bool, rate: FrameRate = .fps30, duration: Double = 1) -> Project {
    var square = Layer(name: "Square", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                    fills: [Fill(paint: .color(RGBA(1, 0, 0)))])),
                       size: Size2(16, 16), position: Vec2(8, 16))
    square.transform.anchor = .zero
    square.opacity = 0.5
    let move = Action(target: square.id, start: 0, duration: duration, easing: .linear,
                      spec: .move(MoveAction(mode: .by, end: Vec2(20, 0))))
    return Project(composition: Composition(width: 64, height: 48, frameRate: rate, duration: duration,
                                            background: Background(color: RGBA(0, 0, 1), isTransparent: transparent)),
                   layers: [square], actions: [move])
}

private func temporaryURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("eMotion-export-\(UUID().uuidString).\(ext)")
}

/// Every decoded frame of the movie's video track, as BGRA pixel buffers,
/// with their presentation times.
private func frames(of url: URL) async throws -> [(time: CMTime, buffer: CVPixelBuffer)] {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(output)
    #expect(reader.startReading())
    var out: [(CMTime, CVPixelBuffer)] = []
    while let sample = output.copyNextSampleBuffer() {
        if let buffer = CMSampleBufferGetImageBuffer(sample) {
            out.append((CMSampleBufferGetPresentationTimeStamp(sample), buffer))
        }
    }
    return out
}

/// One pixel as it comes out of the decoder, 0 to 255.
private func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let row = CVPixelBufferGetBaseAddress(buffer)!.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
    let p = row.assumingMemoryBound(to: UInt8.self).advanced(by: x * 4)
    return (Int(p[2]), Int(p[1]), Int(p[0]), Int(p[3]))
}

@Suite struct ExportTimingTests {
    @Test func framesLastExactlyOneFrameAtBroadcastRates() {
        let timing = ExportTiming(Composition(frameRate: .fps29_97, duration: 10))
        #expect(timing.frameCount == 300)
        #expect(timing.presentationTime(ofFrame: 1) == CMTime(value: 1001, timescale: 30000))
        #expect(timing.presentationTime(ofFrame: 299) == CMTime(value: 299 * 1001, timescale: 30000))
        #expect(timing.frameDuration == CMTime(value: 1001, timescale: 30000))
        #expect(timing.duration == CMTime(value: 300 * 1001, timescale: 30000))
        // The drawn time is the playhead's time for that frame.
        #expect(abs(timing.time(ofFrame: 150) - 150 * 1001.0 / 30000) < 1e-12)
    }

    @Test func moviesAreEvenSizedAndStillsExact() {
        let composition = Composition(width: 101, height: 57)
        #expect(ExportSettings(format: .h264).pixelSize(of: composition) == (102, 58))
        #expect(ExportSettings(format: .proRes4444, scale: 0.5).pixelSize(of: composition) == (50, 28))
        #expect(ExportSettings(format: .png).pixelSize(of: composition) == (101, 57))
        #expect(ExportSettings(format: .png, scale: 2).pixelSize(of: composition) == (202, 114))
    }

    @Test func settingsSurviveBeingStored() throws {
        let settings = ExportSettings(format: .hevcAlpha, scale: 2, quality: .low)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ExportSettings.self, from: data) == settings)
    }
}

@Suite(.serialized) struct MovieExportTests {
    @Test(arguments: [ExportFormat.h264, .hevc, .hevcAlpha, .proRes422, .proRes4444])
    func writesEveryFrameAtItsTime(_ format: ExportFormat) async throws {
        let url = temporaryURL(format.fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        var reported: [Double] = []
        try Exporter.export(project(transparent: false), settings: ExportSettings(format: format), to: url) {
            reported.append($0)
        }
        #expect(reported.count == 30 && reported.last == 1)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1) < 1e-6)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 64, height: 48))

        let decoded = try await frames(of: url)
        #expect(decoded.count == 30)
        #expect(decoded.map(\.time) == (0..<30).map { CMTime(value: CMTimeValue($0), timescale: 30) })

        // The ground is the background colour, and the square has moved by
        // two thirds of its 20 px at frame 20.
        let first = decoded[0].buffer, later = decoded[20].buffer
        let ground = pixel(first, 60, 4)
        #expect(ground.b > 235 && ground.r < 20 && ground.a == 255)
        let square = pixel(first, 12, 20)
        #expect(square.r > 110 && square.b > 110, "half red over blue")
        #expect(pixel(later, 12, 20).b > 235, "the square has moved on")
        #expect(pixel(later, 30, 20).r > 110)
    }

    @Test(arguments: [ExportFormat.hevcAlpha, .proRes4444])
    func keepsTransparency(_ format: ExportFormat) async throws {
        let url = temporaryURL(format.fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(project(transparent: true), settings: ExportSettings(format: format), to: url)
        let first = try #require(try await frames(of: url).first).buffer
        #expect(pixel(first, 60, 4).a < 5)
        let square = pixel(first, 12, 20)
        #expect(abs(square.a - 128) < 12)
        // Straight, so a half-transparent pure red is still pure red.
        #expect(square.r > 240 && square.b < 16)
    }

    @Test func transparentGroundIsFilledWhenTheFormatHasNoAlpha() async throws {
        let url = temporaryURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(project(transparent: true), settings: ExportSettings(format: .h264), to: url)
        let ground = pixel(try #require(try await frames(of: url).first).buffer, 60, 4)
        #expect(ground.b > 235 && ground.r < 20)
    }

    @Test func refusesSizesTheCodecCannotEncode() throws {
        let url = temporaryURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var huge = project(transparent: false, duration: 0.1)
        huge.composition.width = 8000
        huge.composition.height = 8000
        do {
            try Exporter.export(huge, settings: ExportSettings(format: .h264, scale: 2), to: url)
            Issue.record("a 16000 px H.264 export should not succeed")
        } catch let error as ExportError {
            #expect(error == .tooLarge(format: .h264, width: 16000, height: 16000))
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func scalesTheOutput() async throws {
        let url = temporaryURL("mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(project(transparent: false), settings: ExportSettings(format: .proRes422, scale: 2), to: url)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 128, height: 96))
    }

    @Test func cancellingLeavesTheOldFileAlone() throws {
        let url = temporaryURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("keep".utf8).write(to: url)
        let job = ExportJob()
        #expect(throws: ExportError.cancelled) {
            try Exporter.export(project(transparent: false), settings: ExportSettings(format: .h264), to: url,
                                job: job) { if $0 > 0.3 { job.cancel() } }
        }
        #expect(try Data(contentsOf: url) == Data("keep".utf8))
    }

    @Test func replacesAnExistingFile() async throws {
        let url = temporaryURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old".utf8).write(to: url)
        try Exporter.export(project(transparent: false), settings: ExportSettings(format: .h264), to: url)
        #expect(try await frames(of: url).count == 30)
    }
}

@Suite struct StillExportTests {
    @Test func writesTheFrameAtTheTimeGiven() throws {
        let url = temporaryURL("png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(project(transparent: true), settings: ExportSettings(format: .png, scale: 2),
                            at: 0.5, to: url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 128 && image.height == 96)
        #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst)

        // Half way through, the square has moved 10 px: its left edge is at
        // 18 px, 36 at this scale.
        var bytes = [UInt8](repeating: 0, count: 128 * 96 * 4)
        let context = try #require(CGContext(data: &bytes, width: 128, height: 96, bitsPerComponent: 8,
                                             bytesPerRow: 128 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 96))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * 128 + x) * 4 + 3] }
        #expect(alpha(34, 40) == 0)
        #expect(alpha(38, 40) > 100)
    }
}
