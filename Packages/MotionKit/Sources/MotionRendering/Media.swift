import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import VideoToolbox

/// Where a renderer gets the pictures for image and video layers.
public protocol MediaProvider: AnyObject {
    func image(_ mediaID: UUID) -> CGImage?
    /// The frame showing at `time` seconds into the file: the last one to
    /// start at or before it.
    func videoFrame(_ mediaID: UUID, at time: Double) -> CGImage?
}

/// Pictures and video frames read straight from the files, each file opened
/// once and kept. Used from one thread at a time: the canvas has one on the
/// main thread, and each export makes its own.
public final class MediaLibrary: MediaProvider {
    private let locate: (UUID) -> URL?
    private var images: [UUID: CGImage?] = [:]
    private var videos: [UUID: VideoFrames?] = [:]

    /// `locate` finds a file by its media id, or nil if it is missing.
    public init(locate: @escaping (UUID) -> URL?) {
        self.locate = locate
    }

    public func image(_ mediaID: UUID) -> CGImage? {
        if let cached = images[mediaID] { return cached }
        let loaded = locate(mediaID).flatMap(Self.loadImage)
        images[mediaID] = loaded
        return loaded
    }

    public func videoFrame(_ mediaID: UUID, at time: Double) -> CGImage? {
        if videos[mediaID] == nil { videos[mediaID] = .some(locate(mediaID).flatMap(VideoFrames.init)) }
        return videos[mediaID]??.frame(at: time)
    }

    /// Forgets a file, as when it has just been imported under an id that
    /// was missing before.
    public func forget(_ mediaID: UUID) {
        images[mediaID] = nil
        videos[mediaID] = nil
    }

    /// The whole picture, turned the way its camera says it should be, in
    /// sRGB like everything else the renderer draws.
    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let loaded: CGImage?
        if orientation == 1 {
            loaded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            let longest = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
            loaded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(longest, 1),
            ] as CFDictionary)
        }
        guard let image = loaded else { return nil }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        if image.colorSpace?.name == CGColorSpace.sRGB { return image }
        // Drawn into sRGB, so Core Graphics matches the colours; Core
        // Animation off screen would take the numbers as they are.
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}

/// One video file's frames, decoded in order. Asking for the next moment
/// reads on from where it is, which is quick enough for playback and exact
/// for export; asking for a moment behind it, or far ahead, starts reading
/// again from there.
final class VideoFrames {
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let duration: Double
    private let transform: CGAffineTransform
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// The frame showing now, and the next one, read but not yet due.
    private var current: (time: Double, buffer: CVPixelBuffer)?
    private var pending: (time: Double, buffer: CVPixelBuffer)?
    private var image: CGImage?
    private var readFrom = 0.0
    private let context = CIContext(options: [.cacheIntermediates: false,
                                              .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    init?(_ url: URL) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // Loaded synchronously: these reads happen on a worker thread in
        // export and once per file on the canvas.
        guard let track = Self.load({ try await asset.loadTracks(withMediaType: .video).first }) ?? nil,
              let duration = Self.load({ try await asset.load(.duration) }) else { return nil }
        self.asset = asset
        self.track = track
        self.duration = duration.seconds
        transform = Self.load({ try await track.load(.preferredTransform) }) ?? .identity
    }

    /// Runs an async load to completion from synchronous code. AVFoundation's
    /// loads never need the calling thread, so waiting here cannot stall
    /// them; the unchecked boxes carry values AVFoundation does not mark as
    /// sendable across that one hop and back.
    private static func load<T>(_ work: @escaping () async throws -> T) -> T? {
        let box = ResultBox<T>()
        let job = Unchecked(value: work)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = try? await job.value()
            done.signal()
        }
        done.wait()
        return box.value
    }

    func frame(at requested: Double) -> CGImage? {
        let t = min(max(requested, 0), max(duration - 1e-3, 0))
        if let current, current.time <= t + 1e-6, pending.map({ $0.time > t + 1e-6 }) ?? false {
            return picture()
        }
        let position = current?.time ?? readFrom
        if reader == nil || t + 1e-6 < position || t > position + 2 { restart(at: t) }
        guard let output else { return picture() }
        while true {
            let next: (time: Double, buffer: CVPixelBuffer)
            if let waiting = pending {
                next = waiting
                pending = nil
            } else if let sample = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                next = (CMSampleBufferGetPresentationTimeStamp(sample).seconds, buffer)
            } else {
                break    // the end of the file: the last frame stays
            }
            if next.time <= t + 1e-6 || current == nil {
                current = next
                image = nil
                if next.time > t + 1e-6 { break }
            } else {
                pending = next
                break
            }
        }
        return picture()
    }

    private func restart(at t: Double) {
        reader?.cancelReading()
        current = nil
        pending = nil
        image = nil
        // A little before, so the frame already showing at `t` is read too.
        readFrom = max(0, t - 0.5)
        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        reader.timeRange = CMTimeRange(start: CMTime(seconds: readFrom, preferredTimescale: 600), end: .positiveInfinity)
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else { return }
        self.reader = reader
        self.output = output
    }

    /// The current frame as a picture, the right way round for a phone
    /// video filmed upright.
    ///
    /// Its colours are taken as sRGB, as they come, whatever the file says
    /// or the decoder guesses: that is how an export writes them (sRGB values
    /// in a Rec. 709 file), so a movie made here comes back in unchanged, and
    /// a clip shows the colours its pixels hold rather than a conversion from
    /// a guessed standard.
    private func picture() -> CGImage? {
        if let image { return image }
        guard let buffer = current?.buffer else { return nil }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, sRGB, .shouldPropagate)
        if transform.isIdentity {
            var made: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &made)
            image = made
        } else {
            image = context.createCGImage(Self.upright(CIImage(cvPixelBuffer: buffer, options: [.colorSpace: sRGB]),
                                                       transform: transform),
                                          from: CGRect(origin: .zero, size: Self.uprightSize(buffer, transform)),
                                          format: .BGRA8, colorSpace: sRGB)
        }
        return image
    }
}

extension VideoFrames {
    /// A frame turned the way the file says it should show.
    ///
    /// The file's transform is written for pixels counted from the top-left,
    /// y running down, as AVFoundation counts them; Core Image counts from
    /// the bottom-left, y running up. Applied as it is, a quarter turn came
    /// out upside down (both ways round), so it is applied between two flips:
    /// into the file's way of counting, turned, and back.
    static func upright(_ frame: CIImage, transform: CGAffineTransform) -> CIImage {
        let height = frame.extent.height
        var turned = frame.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
            .transformed(by: transform)
        turned = turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
        return turned.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: turned.extent.height))
    }

    /// The size of a frame once turned.
    static func uprightSize(_ buffer: CVPixelBuffer, _ transform: CGAffineTransform) -> CGSize {
        let box = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            .applying(transform)
        return CGSize(width: abs(box.width).rounded(), height: abs(box.height).rounded())
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

private struct Unchecked<T>: @unchecked Sendable {
    let value: T
}
