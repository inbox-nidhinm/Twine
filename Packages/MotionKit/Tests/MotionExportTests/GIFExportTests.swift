import Foundation
import Testing
import CoreGraphics
import ImageIO
import MotionModel
@testable import MotionExport

/// A red square moving right over a grey ground, with a gradient bar that
/// never moves, for GIF and WebM exports.
private func movingProject(transparent: Bool = false, rate: FrameRate = .fps30) -> Project {
    var square = Layer(name: "Square", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                    fills: [Fill(paint: .color(RGBA(1, 0, 0)))])),
                       size: Size2(16, 16), position: Vec2(8, 8))
    square.transform.anchor = .zero
    var bar = Layer(name: "Bar", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .linearGradient(
        Gradient(stops: [GradientStop(position: 0, color: RGBA(0, 0, 0)), GradientStop(position: 1, color: RGBA(1, 1, 1))])))])),
                    size: Size2(64, 8), position: Vec2(0, 36))
    bar.transform.anchor = .zero
    let move = Action(target: square.id, start: 0, duration: 1, easing: .linear,
                      spec: .move(MoveAction(mode: .by, end: Vec2(32, 0))))
    return Project(composition: Composition(width: 64, height: 48, frameRate: rate, duration: 1,
                                            background: Background(color: RGBA(0.5, 0.5, 0.5), isTransparent: transparent)),
                   layers: [bar, square], actions: [move])
}

private func temporaryURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("Twine-gif-\(UUID().uuidString).\(ext)")
}

/// The frames of a GIF as the system decodes them (each whole, with what
/// earlier frames left), and each frame's delay.
private func decoded(_ url: URL) throws -> [(image: CGImage, delay: Double)] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return (0..<CGImageSourceGetCount(source)).compactMap { i in
        guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
        return (image, delay)
    }
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
}

@Suite struct GIFExportTests {
    @Test func aMovingSquareComesOutFrameByFrameAtItsTimes() throws {
        let url = temporaryURL("gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(movingProject(), settings: ExportSettings(format: .gif), to: url)
        let frames = try decoded(url)
        #expect(frames.count == 30)
        // 30 fps in hundredths: 3s and 4s taking turns, a second in all.
        let total = frames.reduce(0) { $0 + $1.delay }
        #expect(abs(total - 1) < 0.011)
        for (image, _) in [frames[0], frames[15], frames[29]] {
            #expect(image.width == 64 && image.height == 48)
        }
        // The square at its place in each frame, the ground grey behind it.
        let first = pixel(frames[0].image, 12, 12), later = pixel(frames[15].image, 12 + 16, 12)
        #expect(first.r > 240 && first.g < 20 && first.b < 20)
        #expect(later.r > 240 && later.g < 20)
        let ground = pixel(frames[15].image, 12, 12)
        #expect(abs(ground.r - 128) < 6 && abs(ground.g - 128) < 6 && abs(ground.b - 128) < 6)
        // The gradient keeps its dark and light ends.
        let dark = pixel(frames[29].image, 1, 40), light = pixel(frames[29].image, 62, 40)
        #expect(dark.r < 30 && light.r > 225)
    }

    @Test func aTransparentGroundStaysSeeThrough() throws {
        let url = temporaryURL("gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(movingProject(transparent: true), settings: ExportSettings(format: .gif), to: url)
        let frames = try decoded(url)
        #expect(pixel(frames[20].image, 2, 2).a == 0)
        #expect(pixel(frames[0].image, 12, 12).a == 255)
        // Where the square was, cleared again once it moved on.
        #expect(pixel(frames[20].image, 10, 10).a == 0)
    }

    @Test func gifsPlayAtMostFiftyFramesASecond() {
        let c = ExportSettings(format: .gif).exported(Composition(frameRate: .fps60))
        #expect(c.frameRate == ExportFormat.gifMaxRate)
        #expect(ExportSettings(format: .gif).exported(Composition(frameRate: .fps24)).frameRate == .fps24)
    }

    @Test func webmComesOutAsVP9WithEveryFrame() throws {
        guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: FileManager.default.isExecutableFile(atPath:)),
              let ffprobe = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"].first(where: FileManager.default.isExecutableFile(atPath:))
        else { return }
        let url = temporaryURL("webm")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.export(movingProject(), settings: ExportSettings(format: .webm), to: url, ffmpeg: URL(fileURLWithPath: ffmpeg))
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: ffprobe)
        probe.arguments = ["-v", "error", "-count_frames", "-select_streams", "v:0",
                           "-show_entries", "stream=codec_name,nb_read_frames,width,height", "-of", "default=noprint_wrappers=1", url.path]
        let out = Pipe()
        probe.standardOutput = out
        try probe.run()
        probe.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(text.contains("codec_name=vp9"))
        #expect(text.contains("nb_read_frames=30"))
        #expect(text.contains("width=64") && text.contains("height=48"))
    }
}
