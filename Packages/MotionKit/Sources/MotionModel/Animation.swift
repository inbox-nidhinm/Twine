import Foundation

/// How an action moves from its starting value to its end value over its
/// duration.
///
/// A preset is a named feel with an intensity from 0 to 1; the curve it makes
/// is worked out when the scene is evaluated, so improving a preset later
/// improves every action that uses it. A custom easing stores its curve.
public enum Easing: Sendable, Equatable {
    case preset(EasingPreset, intensity: Double)
    case custom(CubicBezier)

    /// What a new action gets.
    public static let `default` = Easing.preset(.smooth, intensity: standardIntensity)
    /// The strength a preset is used at when it is picked. The inspector no
    /// longer sets one; actions made before keep theirs.
    public static let standardIntensity = 0.5
    /// Constant speed.
    public static let linear = Easing.preset(.none, intensity: 0)
}

extension Easing: Codable {
    private enum Kind: String, Codable { case preset, custom }
    private enum CodingKeys: String, CodingKey { case type, preset, intensity, curve }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .preset:
            self = .preset(try c.decode(EasingPreset.self, forKey: .preset),
                           intensity: try c.decode(Double.self, forKey: .intensity))
        case .custom:
            self = .custom(try c.decode(CubicBezier.self, forKey: .curve))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let preset, let intensity):
            try c.encode(Kind.preset, forKey: .type)
            try c.encode(preset, forKey: .preset)
            try c.encode(intensity, forKey: .intensity)
        case .custom(let curve):
            try c.encode(Kind.custom, forKey: .type)
            try c.encode(curve, forKey: .curve)
        }
    }
}

/// The named feels offered for an action, Jitter's list. More can be added
/// without changing the file format, since presets are stored by name.
public enum EasingPreset: String, Codable, Sendable, CaseIterable {
    /// Constant speed. Intensity does nothing.
    case none
    /// Eases in and out.
    case smooth
    /// Eases in and out more gently than Smooth, as things move by
    /// themselves.
    case natural
    /// Starts fast and eases into the end value.
    case slowDown
    /// Starts slowly and speeds up into the end value.
    case accelerate
    /// Passes the end value and settles back onto it.
    case overshoot
    /// Springs into place, bouncing more as intensity rises. Shown as
    /// Elastic, Jitter's name for it.
    case spring
    /// Falls onto the end value and bounces on it, as a dropped ball does,
    /// higher as intensity rises.
    case bounce
    /// Pulls back the other way first, then goes.
    case impulse
    /// Pulls back first, then passes the end value and settles onto it.
    case swing
    /// Passes the end value and comes back onto it, a bezier (the user's,
    /// 4 October 2026: 0.45, 1.45, 0.8, 1).
    case easeOutBack
    /// Dips back below the start, then goes, a bezier (the user's,
    /// 4 October 2026: 0.3, -0.05, 0.7, -0.5).
    case easeInBack
}

/// A CSS-style timing curve from (0, 0) to (1, 1) through two control points.
/// The y values may leave 0...1, which is how overshoot curves are made.
public struct CubicBezier: Codable, Sendable, Hashable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// Control points on the diagonal: a straight line.
    public static let linear = CubicBezier(1.0 / 3, 1.0 / 3, 2.0 / 3, 2.0 / 3)
    public static let easeInOut = CubicBezier(0.42, 0, 0.58, 1)
}

/// A damped spring released from 0 towards 1, fitted to a duration. The
/// Elastic preset used it before it took the designer's own list of points.
public struct Spring: Codable, Sendable, Hashable {
    public var stiffness: Double
    public var damping: Double
    public var mass: Double

    public init(stiffness: Double = 170, damping: Double = 26, mass: Double = 1) {
        self.stiffness = stiffness
        self.damping = damping
        self.mass = mass
    }
}
