import Foundation

/// A property that can hold one value, or change over time through keyframes.
///
/// With no keyframes, `value` is the property. With keyframes, the keyframes
/// are the property and `value` is kept only as what the property returns to if
/// the stopwatch is switched off. Keyframes are kept sorted by time.
public struct AnimatableProperty<Value: AnimatableValue>: Sendable, Equatable {
    public var value: Value
    public private(set) var keyframes: [Keyframe<Value>]

    public init(_ value: Value, keyframes: [Keyframe<Value>] = []) {
        self.value = value
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public var isAnimated: Bool { !keyframes.isEmpty }

    /// Replaces every keyframe, keeping them in time order.
    public mutating func setKeyframes(_ new: [Keyframe<Value>]) {
        keyframes = new.sorted { $0.time < $1.time }
    }
}

extension AnimatableProperty: Codable {
    private enum CodingKeys: String, CodingKey { case value, keyframes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(Value.self, forKey: .value),
                  keyframes: try c.decodeIfPresent([Keyframe<Value>].self, forKey: .keyframes) ?? [])
    }

    /// A property that is not animated writes only its value, which keeps a
    /// document of mostly static layers small and readable.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        if !keyframes.isEmpty { try c.encode(keyframes, forKey: .keyframes) }
    }
}

/// A value at a moment. `easing` shapes the segment that runs from this
/// keyframe to the next one; the last keyframe's easing is kept but unused.
public struct Keyframe<Value: AnimatableValue>: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Composition time in seconds.
    public var time: Double
    public var value: Value
    public var easing: Easing

    public init(id: UUID = UUID(), time: Double, value: Value, easing: Easing = .default) {
        self.id = id
        self.time = time
        self.value = value
        self.easing = easing
    }
}

/// How one keyframe segment moves from its start value to its end value.
public enum Easing: Sendable, Equatable {
    case linear
    /// Stays at the start value, then jumps at the next keyframe.
    case hold
    case bezier(CubicBezier)
    case spring(Spring)

    /// What a new keyframe gets.
    public static let `default` = Easing.bezier(.easeInOut)
}

extension Easing: Codable {
    private enum Kind: String, Codable { case linear, hold, bezier, spring }
    private enum CodingKeys: String, CodingKey { case type, curve, spring }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .linear: self = .linear
        case .hold: self = .hold
        case .bezier: self = .bezier(try c.decode(CubicBezier.self, forKey: .curve))
        case .spring: self = .spring(try c.decode(Spring.self, forKey: .spring))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .linear: try c.encode(Kind.linear, forKey: .type)
        case .hold: try c.encode(Kind.hold, forKey: .type)
        case .bezier(let curve):
            try c.encode(Kind.bezier, forKey: .type)
            try c.encode(curve, forKey: .curve)
        case .spring(let spring):
            try c.encode(Kind.spring, forKey: .type)
            try c.encode(spring, forKey: .spring)
        }
    }
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

    public static let easeIn = CubicBezier(0.42, 0, 1, 1)
    public static let easeOut = CubicBezier(0, 0, 0.58, 1)
    public static let easeInOut = CubicBezier(0.42, 0, 0.58, 1)
}

/// A named curve offered in the easing menu. The document stores the curve,
/// not the name, so a preset edited by hand is simply a custom curve.
public struct EasingPreset: Sendable, Identifiable {
    public let name: String
    public let curve: CubicBezier
    public var id: String { name }

    public static let all: [EasingPreset] = [
        .init(name: "Ease In", curve: .easeIn),
        .init(name: "Ease Out", curve: .easeOut),
        .init(name: "Ease In Out", curve: .easeInOut),
        .init(name: "Strong In", curve: CubicBezier(0.5, 0, 0.75, 0)),
        .init(name: "Strong Out", curve: CubicBezier(0.25, 1, 0.5, 1)),
        .init(name: "Strong In Out", curve: CubicBezier(0.76, 0, 0.24, 1)),
        .init(name: "Expo In", curve: CubicBezier(0.7, 0, 0.84, 0)),
        .init(name: "Expo Out", curve: CubicBezier(0.16, 1, 0.3, 1)),
        .init(name: "Expo In Out", curve: CubicBezier(0.87, 0, 0.13, 1)),
        .init(name: "Back In", curve: CubicBezier(0.36, 0, 0.66, -0.56)),
        .init(name: "Back Out", curve: CubicBezier(0.34, 1.56, 0.64, 1)),
        .init(name: "Back In Out", curve: CubicBezier(0.68, -0.6, 0.32, 1.6)),
    ]

    /// The preset this curve is, if it is one.
    public static func named(_ curve: CubicBezier) -> EasingPreset? {
        all.first { $0.curve == curve }
    }
}

/// A damped spring from the segment's start value to its end value.
///
/// A spring has its own natural settling time. When one is applied, the next
/// keyframe is moved to where the spring settles (its duration is derived).
/// If that keyframe is then dragged, the spring's motion is stretched or
/// squeezed to fit the new gap (its duration is overridden), so the motion
/// never jumps. Neither needs storing: the segment's length says which it is.
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
