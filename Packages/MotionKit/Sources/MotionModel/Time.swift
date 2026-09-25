import Foundation

/// Frames per second as an exact fraction, so broadcast rates like 29.97 are
/// 30000/1001 rather than a rounded decimal that drifts a frame every few
/// minutes. Time everywhere else in the model is plain seconds as a `Double`:
/// evaluation must work at any moment, not only on frame boundaries, because
/// motion blur will sample between frames.
public struct FrameRate: Codable, Sendable, Hashable {
    public var frames: Int
    public var seconds: Int

    public init(frames: Int, seconds: Int = 1) {
        precondition(frames > 0 && seconds > 0, "a frame rate needs a positive fraction")
        self.frames = frames
        self.seconds = seconds
    }

    public static let fps24 = FrameRate(frames: 24)
    public static let fps25 = FrameRate(frames: 25)
    public static let fps30 = FrameRate(frames: 30)
    public static let fps50 = FrameRate(frames: 50)
    public static let fps60 = FrameRate(frames: 60)
    public static let fps23_976 = FrameRate(frames: 24000, seconds: 1001)
    public static let fps29_97 = FrameRate(frames: 30000, seconds: 1001)
    public static let fps59_94 = FrameRate(frames: 60000, seconds: 1001)

    /// The rates offered by name. Anything else is a custom rate.
    public static let presets: [FrameRate] = [.fps23_976, .fps24, .fps25, .fps29_97, .fps30, .fps50, .fps59_94, .fps60]

    public var perSecond: Double { Double(frames) / Double(seconds) }
    public var frameDuration: Double { Double(seconds) / Double(frames) }

    /// When frame `index` starts. Computed from the fraction every time rather
    /// than by adding up frame durations, so frame 10,000 lands exactly where
    /// frame 10,000 should.
    public func time(ofFrame index: Int) -> Double {
        Double(index) * Double(seconds) / Double(frames)
    }

    /// The frame showing at `time`. A hair of tolerance keeps a time computed
    /// as `time(ofFrame: n)` from rounding down to frame n - 1.
    public func frame(at time: Double) -> Int {
        Int((time * perSecond + 1e-9).rounded(.down))
    }

    /// `time` moved onto the nearest frame boundary.
    public func snapped(_ time: Double) -> Double {
        self.time(ofFrame: Int((time * perSecond).rounded()))
    }

    /// How the rate reads in a menu: whole rates as integers, others to two places.
    public var label: String {
        if seconds == 1 { return "\(frames)" }
        return String(format: "%.2f", perSecond)
    }
}
