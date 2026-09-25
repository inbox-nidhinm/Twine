import Foundation

/// One timed instruction to one layer, such as "move by 200 px over 0.5 s,
/// smoothly". Actions are how a project animates: a layer's own properties are
/// its design state, how it looks when nothing acts on it, and actions change
/// that state over time.
///
/// An action is not a keyframe. It has one optional starting value and one end
/// value and nothing in between. With no starting value it picks up from
/// wherever the property is when it starts, which is how actions chain. The
/// rules for how actions combine live with evaluation, in `ActionTracks`.
public struct Action: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var targetLayerID: UUID
    /// Composition seconds.
    public var start: Double
    /// Seconds. Zero is an instant change.
    public var duration: Double
    /// Ignored for instant changes and for Hide/Show.
    public var easing: Easing
    /// Shown on its bar. Starts as the kind's name; the user can rename it.
    public var name: String
    /// Off keeps the action but stops it acting, as the eye in the timeline.
    public var isEnabled: Bool
    /// Breaks ties between actions that start together, and orders rows the
    /// user has rearranged. Lower comes first.
    public var rowOrder: Int
    public var spec: ActionSpec

    public init(id: UUID = UUID(), target: UUID, start: Double, duration: Double,
                easing: Easing = .default, name: String? = nil, isEnabled: Bool = true,
                rowOrder: Int = 0, spec: ActionSpec) {
        self.id = id
        self.targetLayerID = target
        self.start = start
        self.duration = duration
        self.easing = easing
        self.name = name ?? spec.kind.defaultName
        self.isEnabled = isEnabled
        self.rowOrder = rowOrder
        self.spec = spec
    }

    public var end: Double { start + duration }

    /// Changes that happen at once, at their start: zero-length actions and
    /// every Hide/Show.
    public var isInstant: Bool { duration <= 0 || spec.kind == .visibility }
}

/// What an action does, with the values of its own type. Each kind carries
/// only its own settings, so a Move can never be handed a colour.
public enum ActionSpec: Sendable, Equatable {
    case move(MoveAction)
    case scale(ScaleAction)
    case rotate(RotateAction)
    case opacity(OpacityAction)
    case resize(ResizeAction)
    case visibility(VisibilityAction)

    public var kind: ActionKind {
        switch self {
        case .move: return .move
        case .scale: return .scale
        case .rotate: return .rotate
        case .opacity: return .opacity
        case .resize: return .resize
        case .visibility: return .visibility
        }
    }
}

public enum ActionKind: String, Codable, Sendable, CaseIterable {
    case move, scale, rotate, opacity, resize, visibility

    public var defaultName: String {
        switch self {
        case .move: return "Move"
        case .scale: return "Scale"
        case .rotate: return "Rotate"
        case .opacity: return "Opacity"
        case .resize: return "Resize"
        case .visibility: return "Hide/Show"
        }
    }
}

/// To sets an absolute end value. By adds to (for Scale, multiplies) the
/// value the action starts from, so a By action follows the layer wherever
/// its design state puts it.
public enum ActionMode: String, Codable, Sendable, CaseIterable {
    case to, by
}

/// Position, in the layer's parent space. In By mode `end` is an offset from
/// the starting position; `initial`, when set, is always an absolute position.
public struct MoveAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Vec2?
    public var end: Vec2
    /// A curved motion path. Nil moves in a straight line.
    public var curve: MotionCurve?

    public init(mode: ActionMode = .by, initial: Vec2? = nil, end: Vec2, curve: MotionCurve? = nil) {
        self.mode = mode
        self.initial = initial
        self.end = end
        self.curve = curve
    }
}

/// The two handles of a curved motion path, as offsets: the first from where
/// the move starts, the second from where it ends. Offsets rather than
/// positions, so the curve travels with a By move.
public struct MotionCurve: Codable, Sendable, Equatable {
    public var startHandle: Vec2
    public var endHandle: Vec2

    public init(startHandle: Vec2, endHandle: Vec2) {
        self.startHandle = startHandle
        self.endHandle = endHandle
    }
}

/// 1 is 100%. In By mode `end` multiplies the starting scale.
public struct ScaleAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Vec2?
    public var end: Vec2
    /// Whether editing one axis moves the other with it.
    public var isLinked: Bool

    public init(mode: ActionMode = .to, initial: Vec2? = nil, end: Vec2, isLinked: Bool = true) {
        self.mode = mode
        self.initial = initial
        self.end = end
        self.isLinked = isLinked
    }
}

/// Degrees, clockwise, never wrapped: 720 spins twice. In By mode `end` is
/// added to the starting rotation.
public struct RotateAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Double?
    public var end: Double

    public init(mode: ActionMode = .to, initial: Double? = nil, end: Double) {
        self.mode = mode
        self.initial = initial
        self.end = end
    }
}

/// 0 to 1.
public struct OpacityAction: Codable, Sendable, Equatable {
    public var initial: Double?
    public var end: Double

    public init(initial: Double? = nil, end: Double) {
        self.initial = initial
        self.end = end
    }
}

/// The layer's box in pixels. It grows and shrinks around the anchor point.
public struct ResizeAction: Codable, Sendable, Equatable {
    public var initial: Size2?
    public var end: Size2
    public var isLinked: Bool

    public init(initial: Size2? = nil, end: Size2, isLinked: Bool = false) {
        self.initial = initial
        self.end = end
        self.isLinked = isLinked
    }
}

/// Shows or hides the layer at the action's start. A layer whose first
/// visibility action is a Show stays hidden until it.
public struct VisibilityAction: Codable, Sendable, Equatable {
    public var isVisible: Bool

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }
}

extension ActionSpec: Codable {
    private enum CodingKeys: String, CodingKey { case type, move, scale, rotate, opacity, resize, visibility }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(ActionKind.self, forKey: .type) {
        case .move: self = .move(try c.decode(MoveAction.self, forKey: .move))
        case .scale: self = .scale(try c.decode(ScaleAction.self, forKey: .scale))
        case .rotate: self = .rotate(try c.decode(RotateAction.self, forKey: .rotate))
        case .opacity: self = .opacity(try c.decode(OpacityAction.self, forKey: .opacity))
        case .resize: self = .resize(try c.decode(ResizeAction.self, forKey: .resize))
        case .visibility: self = .visibility(try c.decode(VisibilityAction.self, forKey: .visibility))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .type)
        switch self {
        case .move(let v): try c.encode(v, forKey: .move)
        case .scale(let v): try c.encode(v, forKey: .scale)
        case .rotate(let v): try c.encode(v, forKey: .rotate)
        case .opacity(let v): try c.encode(v, forKey: .opacity)
        case .resize(let v): try c.encode(v, forKey: .resize)
        case .visibility(let v): try c.encode(v, forKey: .visibility)
        }
    }
}
