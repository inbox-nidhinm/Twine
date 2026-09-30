import Foundation
import CoreMedia
import MotionModel

/// What an export writes: a movie in one of five codecs, or the frame under
/// the playhead as a picture.
public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case h264
    case hevc
    case hevcAlpha
    case proRes422
    case proRes4444
    /// An animated GIF, for Slack, Notion and prototypes. Silent, at most
    /// 50 fps, and see-through only fully or not at all.
    case gif
    /// VP9 in WebM, for the web, with Opus sound; made by the ffmpeg
    /// installed on the Mac.
    case webm
    case png

    public var title: String {
        switch self {
        case .h264: "MP4 (H.264)"
        case .hevc: "MP4 (HEVC)"
        case .hevcAlpha: "MOV (HEVC with transparency)"
        case .proRes422: "MOV (ProRes 422)"
        case .proRes4444: "MOV (ProRes 4444)"
        case .gif: "GIF (animated)"
        case .webm: "WebM (VP9)"
        case .png: "PNG (current frame)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .h264, .hevc: "mp4"
        case .hevcAlpha, .proRes422, .proRes4444: "mov"
        case .gif: "gif"
        case .webm: "webm"
        case .png: "png"
        }
    }

    public var isMovie: Bool { self != .png }

    /// Whether the file can carry the project's sound.
    public var carriesSound: Bool { isMovie && self != .gif }

    /// Made by the ffmpeg installed on the Mac rather than by macOS.
    public var needsFFmpeg: Bool { self == .webm }

    /// The fastest a GIF plays: its frame times are in hundredths of a
    /// second, and browsers slow anything under two to a tenth.
    public static let gifMaxRate = FrameRate.fps50

    /// Whether a transparent background stays transparent. The others are
    /// drawn over the background colour, which is kept for exactly this.
    public var keepsTransparency: Bool {
        switch self {
        case .hevcAlpha, .proRes4444, .png, .gif, .webm: true
        case .h264, .hevc, .proRes422: false
        }
    }

    /// Whether the file's size is set by a bitrate. ProRes sets its own, and
    /// a PNG is lossless.
    public var hasQuality: Bool {
        switch self {
        case .h264, .hevc, .hevcAlpha: true
        case .proRes422, .proRes4444, .png, .gif, .webm: false
        }
    }
}

/// How hard H.264 and HEVC squeeze the picture. Flat colour and clean edges
/// compress so well that Low is often enough; High is for gradients, blur
/// and fine detail.
public enum ExportQuality: String, Codable, Sendable, CaseIterable {
    case high, medium, low

    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    /// Bits for each pixel of each frame, for H.264. HEVC gets the same
    /// picture from about 60% of that.
    var bitsPerPixel: Double {
        switch self {
        case .high: 0.2
        case .medium: 0.1
        case .low: 0.05
        }
    }
}

/// Everything chosen before an export. Kept between exports, so the next one
/// starts where the last left off.
public struct ExportSettings: Codable, Sendable, Equatable {
    public var format: ExportFormat
    /// Output size as a multiple of the composition's: 0.5, 1 and 2 are
    /// offered, and any other can be typed. Held to 4K on export.
    public var scale: Double
    public var quality: ExportQuality
    /// Movies only: the composition's sound, when it has any.
    public var includesAudio: Bool
    /// Movies only: the rate to export at, nil for the composition's own.
    /// A different rate samples the same scene more or less often; timing
    /// stays exact.
    public var frameRate: FrameRate?

    public static let scales: [Double] = [0.5, 1, 2]
    /// The largest an export can be: 4K UHD, either way round.
    public static let maxLongSide = 3840
    public static let maxShortSide = 2160
    /// The smallest scale that can be typed.
    public static let minScale = 0.01

    /// The largest scale that keeps `composition` within 4K.
    public static func largestScale(for composition: Composition) -> Double {
        let long = Double(max(composition.width, composition.height, 1))
        let short = Double(max(min(composition.width, composition.height), 1))
        return min(Double(maxLongSide) / long, Double(maxShortSide) / short)
    }

    /// The scale an export uses: the one chosen, held to 4K.
    public func effectiveScale(for composition: Composition) -> Double {
        min(max(scale, Self.minScale), Self.largestScale(for: composition))
    }

    /// The rates offered for export by name, besides the composition's own.
    public static let frameRates: [FrameRate] = [.fps24, .fps25, .fps30, .fps50, .fps60]

    public init(format: ExportFormat = .h264, scale: Double = 1, quality: ExportQuality = .high, includesAudio: Bool = true,
                frameRate: FrameRate? = nil) {
        self.format = format
        self.scale = scale
        self.quality = quality
        self.includesAudio = includesAudio
        self.frameRate = frameRate
    }

    /// The composition as it is exported: at the chosen rate, if one is.
    public func exported(_ composition: Composition) -> Composition {
        guard format.isMovie else { return composition }
        var c = composition
        if let frameRate { c.frameRate = frameRate }
        if format == .gif, c.frameRate.perSecond > ExportFormat.gifMaxRate.perSecond + 1e-9 { c.frameRate = ExportFormat.gifMaxRate }
        return c
    }

    private enum CodingKeys: String, CodingKey { case format, scale, quality, includesAudio, frameRate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(ExportFormat.self, forKey: .format)
        scale = try c.decode(Double.self, forKey: .scale)
        quality = try c.decode(ExportQuality.self, forKey: .quality)
        includesAudio = try c.decodeIfPresent(Bool.self, forKey: .includesAudio) ?? true
        frameRate = try c.decodeIfPresent(FrameRate.self, forKey: .frameRate)
    }

    /// The output's size in pixels, never past 4K. Movies are rounded to
    /// even numbers, since H.264, HEVC and ProRes 422 store colour at half
    /// resolution and cannot split an odd pixel; 4K's sides are even, so
    /// rounding never takes a movie past it.
    public func pixelSize(of composition: Composition) -> (width: Int, height: Int) {
        let scale = effectiveScale(for: composition)
        func side(_ length: Int) -> Int {
            let scaled = Double(length) * scale
            return format.isMovie ? max(2, Int((scaled / 2).rounded()) * 2) : max(1, Int(scaled.rounded()))
        }
        return (side(composition.width), side(composition.height))
    }

    /// Average bits per second for the codecs that take one.
    func bitRate(width: Int, height: Int, frameRate: FrameRate) -> Int {
        let codec = format == .h264 ? 1 : 0.6
        return Int(Double(width * height) * frameRate.perSecond * quality.bitsPerPixel * codec)
    }
}

/// When each frame of a movie is drawn and when it is shown. Frame `n` shows
/// the composition at the moment the playhead reads for frame `n` (counted
/// from the start of the range being exported), and lasts exactly one frame,
/// counted in the rate's own fraction so 29.97 fps never drifts. The movie
/// always starts at zero, whatever part of the composition it holds.
public struct ExportTiming: Sendable, Equatable {
    public let frameRate: FrameRate
    /// The composition frame the movie starts on.
    public let firstFrame: Int
    public let frameCount: Int

    /// The whole composition, or only `frames` of it (clamped to it, and
    /// never empty).
    public init(_ composition: Composition, frames: Range<Int>? = nil) {
        frameRate = composition.frameRate
        let all = composition.frameCount
        let first = min(max(frames?.lowerBound ?? 0, 0), max(all - 1, 0))
        let end = min(max(frames?.upperBound ?? all, first + 1), max(all, first + 1))
        firstFrame = first
        frameCount = end - first
    }

    /// The composition frames from `start` to `end` in seconds: the frame
    /// under `start`, up to but not including the frame under `end`.
    public static func frames(from start: Double, to end: Double, in composition: Composition) -> Range<Int> {
        let rate = composition.frameRate
        let first = rate.frame(at: rate.snapped(max(start, 0)))
        let last = rate.frame(at: rate.snapped(min(end, composition.duration)))
        return first..<max(last, first + 1)
    }

    /// The composition time drawn for frame `index` of the movie.
    public func time(ofFrame index: Int) -> Double { frameRate.time(ofFrame: firstFrame + index) }

    /// Where the movie starts in the composition, in seconds.
    public var startTime: Double { frameRate.time(ofFrame: firstFrame) }

    /// When frame `index` appears in the file.
    public func presentationTime(ofFrame index: Int) -> CMTime {
        CMTime(value: CMTimeValue(index * frameRate.seconds), timescale: CMTimeScale(frameRate.frames))
    }

    public var frameDuration: CMTime {
        CMTime(value: CMTimeValue(frameRate.seconds), timescale: CMTimeScale(frameRate.frames))
    }

    /// The end of the last frame, which is the movie's length.
    public var duration: CMTime { presentationTime(ofFrame: frameCount) }
}
