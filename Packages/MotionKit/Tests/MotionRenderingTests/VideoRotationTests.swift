import Foundation
import Testing
import AVFoundation
import CoreGraphics
@testable import MotionRendering

/// A 40 by 20 movie in four colours (red top-left, green top-right, blue
/// bottom-left, white bottom-right) carrying `transform`, as a phone writes
/// one filmed upright or upside down.
private func quarteredMovie(transform: CGAffineTransform) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: 40, AVVideoHeightKey: 20,
    ])
    input.transform = transform
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 40,
        kCVPixelBufferHeightKey as String: 20,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<3 {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, 40, 20, kCVPixelFormatType_32BGRA, nil, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<20 { for x in 0..<40 {
            let (r, g, b): (UInt8, UInt8, UInt8) = y < 10 ? (x < 20 ? (255, 0, 0) : (0, 255, 0)) : (x < 20 ? (0, 0, 255) : (255, 255, 255))
            let p = base + y * row + x * 4
            p[0] = b; p[1] = g; p[2] = r; p[3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    return url
}

/// The colour at a fraction of the way across and down a picture, as the
/// strongest of red, green and blue ("white" when all are).
private func colour(_ image: CGImage, _ fx: Double, _ fy: Double) -> String {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let x = Int(Double(image.width) * fx), y = Int(Double(image.height) * fy)
    let p = data + y * image.width * 4 + x * 4
    let (r, g, b) = (p[0] > 128, p[1] > 128, p[2] > 128)
    if r && g && b { return "white" }
    return r ? "red" : g ? "green" : b ? "blue" : "black"
}

@Suite struct VideoRotationTests {
    @Test(arguments: [CGFloat.pi / 2, -CGFloat.pi / 2, CGFloat.pi])
    func aTurnedClipShowsAsAVFoundationShowsIt(angle: CGFloat) async throws {
        // The turn about the origin, moved back into view, as phones write it.
        var transform = CGAffineTransform(rotationAngle: angle)
        let box = CGRect(x: 0, y: 0, width: 40, height: 20).applying(transform)
        transform = transform.concatenating(CGAffineTransform(translationX: -box.minX, y: -box.minY))
        let url = try await quarteredMovie(transform: transform)
        defer { try? FileManager.default.removeItem(at: url) }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let expected = try await generator.image(at: CMTime(value: 1, timescale: 30)).image
        let library = MediaLibrary(locate: { _ in url })
        let shown = try #require(library.videoFrame(UUID(), at: 1.0 / 30))

        #expect(shown.width == expected.width && shown.height == expected.height)
        for (fx, fy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
            #expect(colour(shown, fx, fy) == colour(expected, fx, fy), "at \(fx), \(fy) for \(angle)")
        }
    }
}
