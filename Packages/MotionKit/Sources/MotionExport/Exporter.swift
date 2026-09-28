import Foundation
import AVFoundation
import CoreVideo
import VideoToolbox
import ImageIO
import Accelerate
import UniformTypeIdentifiers
import Synchronization
import MotionModel
import MotionEvaluation
import MotionRendering

/// Why an export stopped, in words a person can act on.
public enum ExportError: LocalizedError, Equatable {
    case cancelled
    case noGPU
    case tooLarge(format: ExportFormat, width: Int, height: Int)
    /// Sounds in the composition that could not be read, by name.
    case soundUnreadable([String])
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: "The export was cancelled."
        case .noGPU: "The export couldn't start."
        case .tooLarge: "The export is too large for this format."
        case .soundUnreadable: "The sound couldn't be read."
        case .failed: "The export couldn't be finished."
        }
    }

    public var failureReason: String? {
        switch self {
        case .cancelled: nil
        case .noGPU: "There is no graphics processor available to draw the frames."
        case .tooLarge(let format, let width, let height):
            "\(format.title) can't encode a \(width) × \(height) picture. Try a smaller size, or "
                + (format == .h264 ? "HEVC or ProRes." : "ProRes.")
        case .soundUnreadable(let names):
            "\(names.joined(separator: ", ")) couldn't be heard: \(names.count == 1 ? "its file is" : "their files are") missing or unreadable. Nothing was exported, so no movie is missing its sound."
        case .failed(let reason): reason
        }
    }

    /// What an alert shows under the title. AppKit's alerts read this rather
    /// than the failure reason.
    public var recoverySuggestion: String? { failureReason }
}

/// One export in flight, so another thread can stop it. Cancelling is
/// checked before every frame.
public final class ExportJob: Sendable {
    private let cancelled = Mutex(false)

    public init() {}

    public func cancel() { cancelled.withLock { $0 = true } }
    public var isCancelled: Bool { cancelled.withLock { $0 } }
}

/// Writes exports. Everything here blocks until the file is written, and is
/// meant to run off the main thread. Frames are drawn one after another from
/// `evaluate`, never from playback, so a slow machine takes longer but writes
/// the same file.
///
/// The file is written beside its destination under a temporary name and
/// only moved into place once it is complete, so a cancelled or failed
/// export never leaves half a movie, or destroys the file it would replace.
public enum Exporter {
    /// Writes `settings.format` to `url`. For a movie that is the whole
    /// composition, or only `frames` of it; for a PNG it is the frame at
    /// `time`. A movie is made at `settings.frameRate` when one is chosen,
    /// and `frames` count at that rate. `progress` is called
    /// from the exporting thread after each frame, from 0 to 1.
    /// `media` locates each imported file by its id, for pictures, video
    /// frames and sound.
    public static func export(_ project: Project, settings: ExportSettings, at time: Double = 0,
                              frames: Range<Int>? = nil, to url: URL,
                              media: [UUID: URL] = [:], job: ExportJob = ExportJob(),
                              progress: (Double) -> Void = { _ in }) throws {
        var project = project
        project.composition = settings.exported(project.composition)
        if !settings.format.keepsTransparency {
            project.composition.background.isTransparent = false
        }
        let fileManager = FileManager.default
        let folder = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                         appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: folder) }
        let temporary = folder.appendingPathComponent(url.lastPathComponent)

        let library = MediaLibrary(locate: { media[$0] })
        if settings.format.isMovie {
            try writeMovie(project, settings: settings, frames: frames, library: library, media: media, to: temporary,
                           job: job, progress: progress)
        } else {
            try writeStill(project, settings: settings, library: library, at: time, to: temporary)
            progress(1)
        }
        if job.isCancelled { throw ExportError.cancelled }

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    // MARK: Still

    private static func writeStill(_ project: Project, settings: ExportSettings, library: MediaLibrary, at time: Double,
                                   to url: URL) throws {
        let (width, height) = settings.pixelSize(of: project.composition)
        guard let renderer = OffscreenRenderer(pixelWidth: width, pixelHeight: height) else { throw ExportError.noGPU }
        renderer.media = library
        let snapped = project.composition.frameRate.snapped(time)
        guard let image = renderer.image(of: evaluate(project, at: snapped)),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ExportError.failed("The frame couldn't be drawn.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.failed("The picture couldn't be saved.")
        }
    }

    // MARK: Movie

    private static func writeMovie(_ project: Project, settings: ExportSettings, frames: Range<Int>?,
                                   library: MediaLibrary, media: [UUID: URL], to url: URL, job: ExportJob,
                                   progress: (Double) -> Void) throws {
        let composition = project.composition
        let timing = ExportTiming(composition, frames: frames)
        let (width, height) = settings.pixelSize(of: composition)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: isMOV(settings.format) ? .mov : .mp4)
        } catch {
            throw ExportError.failed(error.localizedDescription)
        }
        let output = videoSettings(settings, width: width, height: height, frameRate: composition.frameRate)
        guard writer.canApply(outputSettings: output, forMediaType: .video) else {
            throw ExportError.tooLarge(format: settings.format, width: width, height: height)
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: output)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(input) else {
            throw ExportError.tooLarge(format: settings.format, width: width, height: height)
        }
        writer.add(input)
        // Only once the encoder has agreed to the size, so a size it refuses
        // never takes the memory for a picture that large.
        guard let renderer = OffscreenRenderer(pixelWidth: width, pixelHeight: height) else { throw ExportError.noGPU }
        renderer.media = library

        // The sound, mixed from its clips and read alongside the frames.
        let names = Dictionary(project.media.map { ($0.id, $0.originalName) }, uniquingKeysWith: { a, _ in a })
        let sound = settings.includesAudio
            ? try AudioMixdown(clips: audioClips(project), media: media, names: names, start: timing.startTime,
                               duration: timing.duration.seconds, compressed: !isMOV(settings.format))
            : nil
        if let sound {
            guard writer.canAdd(sound.input) else { throw ExportError.failed("The sound couldn't be added to the movie.") }
            writer.add(sound.input)
        }

        // An encoder may accept the settings and refuse the size only while
        // finishing, with no useful message. A failure at a size past what
        // H.264 and HEVC hardware encodes is put down to the size.
        func failure() -> ExportError {
            if max(width, height) > 4096 && settings.format.hasQuality {
                return .tooLarge(format: settings.format, width: width, height: height)
            }
            return .failed(writer.error?.localizedDescription ?? "The movie couldn't be written.")
        }
        guard writer.startWriting() else { throw failure() }
        writer.startSession(atSourceTime: .zero)
        sound?.start(job: job)

        for frame in 0..<timing.frameCount {
            while !input.isReadyForMoreMediaData {
                if job.isCancelled || writer.status == .failed { break }
                Thread.sleep(forTimeInterval: 0.001)
            }
            if job.isCancelled {
                sound?.cancel()
                writer.cancelWriting()
                throw ExportError.cancelled
            }
            guard writer.status == .writing else { throw failure() }

            var made: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess, let buffer = made
            else { throw ExportError.failed("There wasn't enough memory for the next frame.") }
            renderer.render(evaluate(project, at: timing.time(ofFrame: frame)), into: buffer)
            if settings.format.keepsTransparency { unpremultiply(buffer) }
            describe(buffer)
            guard adaptor.append(buffer, withPresentationTime: timing.presentationTime(ofFrame: frame)) else {
                throw failure()
            }
            progress(Double(frame + 1) / Double(timing.frameCount))
        }

        input.markAsFinished()
        sound?.wait()
        if job.isCancelled {
            writer.cancelWriting()
            throw ExportError.cancelled
        }
        // A movie missing its sound is not finished.
        if let problem = sound?.failure {
            writer.cancelWriting()
            throw ExportError.failed(problem)
        }
        // The last frame lasts one frame, not until the movie's first.
        writer.endSession(atSourceTime: timing.duration)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw failure() }
    }

    static func isMOV(_ format: ExportFormat) -> Bool { format.fileExtension == "mov" }

    /// Rec. 709 throughout, as video players expect. The composition's sRGB
    /// colours go in unchanged: the two share their primaries.
    private static let colorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ]

    static func videoSettings(_ settings: ExportSettings, width: Int, height: Int,
                              frameRate: FrameRate) -> [String: Any] {
        var output: [String: Any] = [
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: colorProperties,
        ]
        let keyFrames = max(1, Int((frameRate.perSecond * 2).rounded()))
        let bitRate = settings.bitRate(width: width, height: height, frameRate: frameRate)
        switch settings.format {
        case .h264:
            output[AVVideoCodecKey] = AVVideoCodecType.h264
            output[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: keyFrames,
                AVVideoExpectedSourceFrameRateKey: frameRate.perSecond,
            ] as [String: Any]
        case .hevc, .hevcAlpha:
            output[AVVideoCodecKey] = settings.format == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.hevcWithAlpha
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
                AVVideoMaxKeyFrameIntervalKey: keyFrames,
                AVVideoExpectedSourceFrameRateKey: frameRate.perSecond,
            ]
            if settings.format == .hevcAlpha {
                compression[kVTCompressionPropertyKey_AlphaChannelMode as String] =
                    kVTAlphaChannelMode_StraightAlpha as String
                compression[kVTCompressionPropertyKey_TargetQualityForAlpha as String] = 1.0
            }
            output[AVVideoCompressionPropertiesKey] = compression
        case .proRes422:
            output[AVVideoCodecKey] = AVVideoCodecType.proRes422
        case .proRes4444:
            output[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        case .png:
            break
        }
        return output
    }

    /// Core Animation draws premultiplied colour, where a half-transparent
    /// red is stored as half red. Movies with transparency store straight
    /// colour, full red at half opacity, which is what ProRes specifies and
    /// what editing apps expect; given premultiplied colour they draw dark
    /// fringes round every soft edge.
    private static func unpremultiply(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        var image = vImage_Buffer(data: base, height: vImagePixelCount(CVPixelBufferGetHeight(buffer)),
                                  width: vImagePixelCount(CVPixelBufferGetWidth(buffer)),
                                  rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        // Alpha is the last byte, as in RGBA, and the colour order does not matter.
        vImageUnpremultiplyData_RGBA8888(&image, &image, vImage_Flags(kvImageNoFlags))
    }

    /// Tells the encoder what the pixels are: already in the movie's colour
    /// space, so nothing is converted, and straight alpha.
    private static func describe(_ buffer: CVPixelBuffer) {
        let attachments: [CFString: CFString] = [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            kCVImageBufferAlphaChannelModeKey: kCVImageBufferAlphaChannelMode_StraightAlpha,
        ]
        for (key, value) in attachments {
            CVBufferSetAttachment(buffer, key, value, .shouldPropagate)
        }
    }
}
