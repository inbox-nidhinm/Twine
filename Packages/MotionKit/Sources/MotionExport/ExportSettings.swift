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
    case png

    public var title: String {
        switch self {
        case .h264: "MP4 (H.264)"
        case .hevc: "MP4 (HEVC)"
        case .hevcAlpha: "MOV (HEVC with transparency)"
        case .proRes422: "MOV (ProRes 422)"
        case .proRes4444: "MOV (ProRes 4444)"
        case .png: "PNG (current frame)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .h264, .hevc: "mp4"
        case .hevcAlpha, .proRes422, .proRes4444: "mov"
        case .png: "png"
        }
    }

    public var isMovie: Bool { self != .png }

    /// Whether a transparent background stays transparent. The others are
    /// drawn over the background colour, which is kept for exactly this.
    public var keepsTransparency: Bool {
        switch self {
        case .hevcAlpha, .proRes4444, .png: true
        case .h264, .hevc, .proRes422: false
        }
    }

    /// Whether the file's size is set by a bitrate. ProRes sets its own, and
    /// a PNG is lossless.
    public var hasQuality: Bool {
        switch self {
        case .h264, .hevc, .hevcAlpha: true
        case .proRes422, .proRes4444, .png: false
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
    /// Output size as a multiple of the composition's: 0.5, 1 or 2.
    public var scale: Double
    public var quality: ExportQuality
    /// Movies only: the composition's sound, when it has any.
    public var includesAudio: Bool

    public static let scales: [Double] = [0.5, 1, 2]

    public init(format: ExportFormat = .h264, scale: Double = 1, quality: ExportQuality = .high, includesAudio: Bool = true) {
        self.format = format
        self.scale = scale
        self.quality = quality
        self.includesAudio = includesAudio
    }

    private enum CodingKeys: String, CodingKey { case format, scale, quality, includesAudio }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(ExportFormat.self, forKey: .format)
        scale = try c.decode(Double.self, forKey: .scale)
        quality = try c.decode(ExportQuality.self, forKey: .quality)
        includesAudio = try c.decodeIfPresent(Bool.self, forKey: .includesAudio) ?? true
    }

    /// The output's size in pixels. Movies are rounded to even numbers,
    /// since H.264, HEVC and ProRes 422 store colour at half resolution and
    /// cannot split an odd pixel.
    public func pixelSize(of composition: Composition) -> (width: Int, height: Int) {
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
/// the composition at the moment the playhead reads for frame `n`, and lasts
/// exactly one frame, counted in the rate's own fraction so 29.97 fps never
/// drifts.
public struct ExportTiming: Sendable, Equatable {
    public let frameRate: FrameRate
    public let frameCount: Int

    public init(_ composition: Composition) {
        frameRate = composition.frameRate
        frameCount = composition.frameCount
    }

    /// The composition time drawn for frame `index`.
    public func time(ofFrame index: Int) -> Double { frameRate.time(ofFrame: index) }

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
