import Foundation
import Testing
import AVFoundation
import CoreGraphics
@testable import MotionRendering

/// A 16 by 16 movie of plain colours, one a frame, each starting at its own
/// time: for files whose frames are not evenly spaced.
private func movie(_ frames: [(time: Double, color: (UInt8, UInt8, UInt8))], end: Double) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: 16, AVVideoHeightKey: 16,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16,
        kCVPixelBufferHeightKey as String: 16,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in frames {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<16 { for x in 0..<16 {
            let p = base + y * row + x * 4
            p[0] = frame.color.2; p[1] = frame.color.1; p[2] = frame.color.0; p[3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        adaptor.append(buffer, withPresentationTime: CMTime(seconds: frame.time, preferredTimescale: 600))
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
    await writer.finishWriting()
    return url
}

/// The strongest of red, green and blue in the middle of a picture.
private func colour(_ image: CGImage?) -> String {
    guard let image else { return "none" }
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let p = context.data!.assumingMemoryBound(to: UInt8.self) + (image.height / 2) * image.width * 4 + (image.width / 2) * 4
    return p[0] > 128 ? "red" : p[1] > 128 ? "green" : p[2] > 128 ? "blue" : "black"
}

private let red: (UInt8, UInt8, UInt8) = (255, 0, 0), green: (UInt8, UInt8, UInt8) = (0, 255, 0), blue: (UInt8, UInt8, UInt8) = (0, 0, 255)

@Suite struct VideoSeekTests {
    /// A file whose picture begins after its start is not read again from
    /// the start on every draw while the playhead rests before it, and its
    /// frames come when they are due.
    @Test func aLatePictureIsNotReadAgainOnEveryDraw() async throws {
        let url = try await movie([(1.0, red), (1.5, green)], end: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = try #require(VideoFrames(url))
        _ = frames.frame(at: 0)
        let started = frames.restarts
        for _ in 0..<5 { _ = frames.frame(at: 0) }
        #expect(frames.restarts == started)
        #expect(colour(frames.frame(at: 1.2)) == "red")
        #expect(colour(frames.frame(at: 1.6)) == "green")
    }

    /// Jumping into a long gap between frames shows the frame that is
    /// showing then, not the next one, and settles.
    @Test func aJumpIntoALongGapShowsTheFrameBeforeIt() async throws {
        let url = try await movie([(0, red), (3.0, green), (3.1, blue)], end: 3.2)
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = try #require(VideoFrames(url))
        #expect(colour(frames.frame(at: 2.0)) == "red")
        let started = frames.restarts
        for _ in 0..<5 { #expect(colour(frames.frame(at: 2.0)) == "red") }
        #expect(frames.restarts == started)
        #expect(colour(frames.frame(at: 3.05)) == "green")
        #expect(colour(frames.frame(at: 3.15)) == "blue")
        // And back again.
        #expect(colour(frames.frame(at: 1.0)) == "red")
    }
}
