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
    FileManager.default.temporaryDirectory.appendingPathComponent("Twine-export-\(UUID().uuidString).\(ext)")
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

    @Test func aRangeStartsTheMovieAtItsFirstFrame() {
        let composition = Composition(frameRate: .fps30, duration: 2)
        let frames = ExportTiming.frames(from: 0.5, to: 1.5, in: composition)
        #expect(frames == 15..<45)
        let timing = ExportTiming(composition, frames: frames)
        #expect(timing.frameCount == 30)
        #expect(timing.time(ofFrame: 0) == 0.5)
        #expect(timing.presentationTime(ofFrame: 0) == .zero)
        #expect(timing.duration.seconds == 1)
        // Past the end, or back to front, it still holds at least a frame of the composition.
        #expect(ExportTiming(composition, frames: 50..<90).frameCount == 10)
        #expect(ExportTiming.frames(from: 1, to: 1, in: composition).count == 1)
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

    @Test func anOversizedExportComesOutAt4K() async throws {
        let url = temporaryURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var huge = project(transparent: false, duration: 0.1)
        huge.composition.width = 8000
        huge.composition.height = 8000
        // 16000 px square would be past any encoder; it is held to 4K's short side.
        try Exporter.export(huge, settings: ExportSettings(format: .h264, scale: 2), to: url)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 2160, height: 2160))
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

@Suite struct ExportSizeTests {
    private func comp(_ w: Int, _ h: Int) -> Composition { Composition(width: w, height: h, frameRate: .fps30, duration: 1) }

    @Test func anyScaleCanBeTyped() {
        let settings = ExportSettings(format: .png, scale: 1.5)
        #expect(settings.pixelSize(of: comp(1920, 1080)) == (2880, 1620))
        let third = ExportSettings(format: .png, scale: 1.0 / 3)
        #expect(third.pixelSize(of: comp(1000, 500)) == (333, 167))
    }

    @Test func moviesStayEven() {
        let movie = ExportSettings(format: .h264, scale: 1.0 / 3)
        let (w, h) = movie.pixelSize(of: comp(1000, 500))
        #expect(w % 2 == 0 && h % 2 == 0)
        #expect(w == 334 && h == 166)
        let odd = ExportSettings(format: .proRes422, scale: 0.37)
        let size = odd.pixelSize(of: comp(1333, 777))
        #expect(size.width % 2 == 0 && size.height % 2 == 0)
    }

    @Test func nothingGoesPast4K() {
        let big = ExportSettings(format: .hevc, scale: 5)
        #expect(big.pixelSize(of: comp(1920, 1080)) == (3840, 2160))
        // Either way round.
        #expect(big.pixelSize(of: comp(1080, 1920)) == (2160, 3840))
        // A square is held by the short side.
        #expect(big.pixelSize(of: comp(1000, 1000)) == (2160, 2160))
        // A composition already past 4K is brought down to it at 100%.
        #expect(ExportSettings(format: .png, scale: 1).pixelSize(of: comp(7680, 4320)) == (3840, 2160))
        #expect(ExportSettings.largestScale(for: comp(1920, 1080)) == 2)
    }
}

@Suite struct ExportRateTests {
    @Test func aMovieCanBeMadeAtAnotherRate() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Twine-rate-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let box = Layer(name: "B", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                fills: [Fill(paint: .color(.white))])),
                        size: Size2(10, 10), position: Vec2(32, 32))
        let project = Project(composition: Composition(width: 64, height: 64, frameRate: .fps60, duration: 1), layers: [box])
        try Exporter.export(project, settings: ExportSettings(format: .h264, frameRate: .fps24), to: url)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let rate = try await track.load(.nominalFrameRate)
        #expect(abs(Double(rate) - 24) < 0.1)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 1) < 0.05)
    }

    @Test func aChosenRateIsRemembered() throws {
        let data = try JSONEncoder().encode(ExportSettings(format: .hevc, frameRate: .fps30))
        #expect(try JSONDecoder().decode(ExportSettings.self, from: data).frameRate == .fps30)
        // Settings saved before rates could be chosen still read.
        let old = #"{"format":"h264","scale":1,"quality":"high"}"#
        #expect(try JSONDecoder().decode(ExportSettings.self, from: Data(old.utf8)).frameRate == nil)
    }
}
