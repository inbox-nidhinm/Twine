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
    /// Motion blur on the movement this action makes (its moves, scales,
    /// turns, skews and tilts): how long the shutter stays open, as a share
    /// of a frame, 0.5 being a 180° shutter. Nil is off, and is left out of
    /// files.
    public var motionBlur: Double?

    /// A new action's Motion Blur amount: a 180° shutter.
    public static let standardMotionBlur = 0.5

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
    case color(ColorAction)
    case stroke(StrokeAction)
    case trim(TrimAction)
    case cornerRadius(CornerRadiusAction)
    case shadow(ShadowAction)
    /// The first inner shadow, shapes and frames only.
    case innerShadow(ShadowAction)
    case layerBlur(LayerBlurAction)
    case backgroundBlur(BackgroundBlurAction)
    case letterSpacing(LetterSpacingAction)
    case lineHeight(LineHeightAction)
    case counter(CounterAction)
    case changeText(ChangeTextAction)
    case arc(ArcAction)
    case star(StarAction)
    case path(PathAction)
    case play(PlayAction)
    case volume(VolumeAction)
    case skew(SkewAction)
    case tilt(TiltAction)
    /// Z, in a frame in 3D.
    case depth(DepthAction)
    case bend(BendAction)
    /// A frame in 3D's camera and depth look.
    case camera(CameraAction)
    /// When a template frame plays (see `TemplateSetup`).
    case template(TemplatePlay)
    /// One of a template frame's settings moving over its bar.
    case templateSetting(TemplateSettingAction)
    case dash(DashAction)
    /// A ready-made animation on one bar: several properties at once, with
    /// the settings its preset offers. See `PresetAction`.
    case preset(PresetAction)

    public var kind: ActionKind {
        switch self {
        case .move: return .move
        case .scale: return .scale
        case .rotate: return .rotate
        case .opacity: return .opacity
        case .resize: return .resize
        case .visibility: return .visibility
        case .color: return .color
        case .stroke: return .stroke
        case .trim: return .trim
        case .cornerRadius: return .cornerRadius
        case .shadow: return .shadow
        case .innerShadow: return .innerShadow
        case .layerBlur: return .layerBlur
        case .backgroundBlur: return .backgroundBlur
        case .letterSpacing: return .letterSpacing
        case .lineHeight: return .lineHeight
        case .counter: return .counter
        case .changeText: return .changeText
        case .arc: return .arc
        case .star: return .star
        case .path: return .path
        case .play: return .play
        case .volume: return .volume
        case .skew: return .skew
        case .tilt: return .tilt
        case .depth: return .depth
        case .bend: return .bend
        case .camera: return .camera
        case .template: return .template
        case .templateSetting: return .templateSetting
        case .dash: return .dash
        case .preset: return .preset
        }
    }
}

public enum ActionKind: String, Codable, Sendable, CaseIterable {
    case move, scale, rotate, opacity, resize, visibility
    case color, stroke, trim, dash, cornerRadius, shadow, innerShadow
    case layerBlur, backgroundBlur
    case letterSpacing, lineHeight, counter, changeText
    case arc, star, path
    case play, volume
    case skew, tilt
    case depth, bend, camera
    /// Added with its template, never from Add Action.
    case template
    /// A template frame's setting, offered on template frames only.
    case templateSetting
    /// Added from Add Preset, never from Add Action.
    case preset

    public var defaultName: String {
        switch self {
        case .move: return "Move"
        case .scale: return "Scale"
        case .rotate: return "Rotate"
        case .opacity: return "Opacity"
        case .resize: return "Resize"
        case .visibility: return "Hide/Show"
        case .color: return "Colour"
        case .stroke: return "Stroke"
        case .trim: return "Trim"
        case .dash: return "Dashes"
        case .cornerRadius: return "Corner Radius"
        case .shadow: return "Shadow"
        case .innerShadow: return "Inner Shadow"
        case .layerBlur: return "Layer Blur"
        case .backgroundBlur: return "Background Blur"
        case .letterSpacing: return "Letter Spacing"
        case .lineHeight: return "Line Height"
        case .counter: return "Counter"
        case .changeText: return "Change Text"
        case .arc: return "Arc"
        case .star: return "Star"
        case .path: return "Path"
        case .play: return "Play"
        case .volume: return "Volume"
        case .skew: return "Skew"
        case .tilt: return "Tilt"
        case .depth: return "Depth"
        case .bend: return "Bend"
        case .camera: return "Camera"
        case .template: return "Template"
        case .templateSetting: return "Template Setting"
        case .preset: return "Preset"
        }
    }

    /// The group it is listed under when adding an action.
    public var category: ActionCategory {
        switch self {
        case .move, .scale, .rotate, .opacity, .resize, .visibility, .skew, .tilt, .depth, .bend: return .transform
        case .camera, .template, .templateSetting: return .space
        case .color, .stroke, .trim, .dash, .cornerRadius, .shadow, .innerShadow: return .style
        case .layerBlur, .backgroundBlur: return .blur
        case .letterSpacing, .lineHeight, .counter, .changeText: return .text
        case .arc, .star, .path: return .shape
        case .play, .volume: return .media
        // Never listed: presets have a menu of their own.
        case .preset: return .transform
        }
    }
}

public enum ActionCategory: String, Sendable, CaseIterable {
    case transform, style, blur, text, shape, media, space

    public var title: String {
        switch self {
        case .transform: return "Transform"
        case .style: return "Style"
        case .blur: return "Blur"
        case .text: return "Text"
        case .shape: return "Shape"
        case .media: return "Media"
        case .space: return "3D"
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
    /// Whether the layer turns as a curved path turns, from its own angle,
    /// as if steering along it. Only a curved path turns.
    public var turnsAlongPath: Bool

    public init(mode: ActionMode = .by, initial: Vec2? = nil, end: Vec2, curve: MotionCurve? = nil,
                turnsAlongPath: Bool = false) {
        self.mode = mode
        self.initial = initial
        self.end = end
        self.curve = curve
        self.turnsAlongPath = turnsAlongPath
    }

    private enum CodingKeys: String, CodingKey { case mode, initial, end, curve, turnsAlongPath }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(ActionMode.self, forKey: .mode)
        initial = try c.decodeIfPresent(Vec2.self, forKey: .initial)
        end = try c.decode(Vec2.self, forKey: .end)
        curve = try c.decodeIfPresent(MotionCurve.self, forKey: .curve)
        // Arrived after the first moves.
        turnsAlongPath = try c.decodeIfPresent(Bool.self, forKey: .turnsAlongPath) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(initial, forKey: .initial)
        try c.encode(end, forKey: .end)
        try c.encodeIfPresent(curve, forKey: .curve)
        // Left out when off, so older files read the same.
        if turnsAlongPath { try c.encode(turnsAlongPath, forKey: .turnsAlongPath) }
    }

    /// Whether it turns the layer: set to, and curved.
    public var turns: Bool { turnsAlongPath && curve != nil }
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

/// Shows or hides the layer at the action's start. A layer is shown until
/// something hides it, so a Show only brings a layer back.
public struct VisibilityAction: Codable, Sendable, Equatable {
    public var isVisible: Bool

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }
}

/// The first fill's paint: a colour, or a gradient whose stops, positions and
/// geometry all travel. A layer with no fill has nothing to act on.
public struct ColorAction: Codable, Sendable, Equatable {
    public var initial: Paint?
    public var end: Paint

    public init(initial: Paint? = nil, end: Paint) {
        self.initial = initial
        self.end = end
    }
}

/// The two parts of a stroke that animate together: how thick it is and what
/// it is painted with.
public struct StrokeLook: AnimatableValue {
    public var width: Double
    public var paint: Paint

    public init(width: Double, paint: Paint) {
        self.width = width
        self.paint = paint
    }

    /// A stroke's own width and paint.
    public init(_ stroke: Stroke) {
        self.init(width: stroke.width, paint: stroke.paint)
    }
}

/// The first stroke's width and paint.
public struct StrokeAction: Codable, Sendable, Equatable {
    public var initial: StrokeLook?
    public var end: StrokeLook

    public init(initial: StrokeLook? = nil, end: StrokeLook) {
        self.initial = initial
        self.end = end
    }
}

/// The way a trim draws its line: from the path's start to its end, from
/// its end back to its start, from both ends meeting in the middle, or from
/// the middle out to both ends.
public enum TrimDirection: String, Codable, Sendable, CaseIterable {
    case startToEnd = "start-to-end", endToStart = "end-to-start"
    case toMiddle = "to-middle", fromMiddle = "from-middle"
}

/// How much of a stroke is drawn, and which way it grows: `amount` is the
/// share of the path's length that shows, 0 none and 1 all of it, laid
/// from where `direction` starts. (Until 2 October 2026 a trim was a start
/// and an end along the path; older files are read as the nearest of these,
/// `TrimRange(start:end:)`.)
public struct TrimRange: AnimatableValue {
    public var direction: TrimDirection
    public var amount: Double

    public init(direction: TrimDirection = .startToEnd, amount: Double) {
        self.direction = direction
        self.amount = amount
    }

    public static let whole = TrimRange(amount: 1)

    /// The parts of the path that show, as fractions of its length, each
    /// with whether it grows towards the path's end (`forward`) or its start.
    public var pieces: [(start: Double, end: Double, forward: Bool)] {
        let a = min(max(amount, 0), 1)
        switch direction {
        case .startToEnd: return [(0, a, true)]
        case .endToStart: return [(1 - a, 1, false)]
        case .toMiddle: return [(0, a / 2, true), (1 - a / 2, 1, false)]
        case .fromMiddle: return [(0.5 - a / 2, 0.5, false), (0.5, 0.5 + a / 2, true)]
        }
    }

    /// An old start and end along the path, as the way it reads best:
    /// from the start when it starts there, to the end when it ends there,
    /// else from the middle; `certain` is false when the range says
    /// nothing of a way (all or none of the path).
    public static func reading(start: Double, end: Double) -> (range: TrimRange, certain: Bool) {
        let s = min(max(min(start, end), 0), 1), e = min(max(max(start, end), 0), 1)
        let near = { (a: Double, b: Double) in abs(a - b) < 1e-9 }
        if near(s, e) {
            return near(s, 1) ? (TrimRange(direction: .endToStart, amount: 0), true)
                : near(s, 0) ? (TrimRange(amount: 0), false) : (TrimRange(direction: .fromMiddle, amount: 0), true)
        }
        if near(s, 0) { return (TrimRange(amount: e), !near(e, 1)) }
        if near(e, 1) { return (TrimRange(direction: .endToStart, amount: 1 - s), true) }
        return (TrimRange(direction: .fromMiddle, amount: e - s), true)
    }

    private enum CodingKeys: String, CodingKey { case direction, amount, start, end }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let amount = try c.decodeIfPresent(Double.self, forKey: .amount) {
            self.init(direction: try c.decodeIfPresent(TrimDirection.self, forKey: .direction) ?? .startToEnd, amount: amount)
        } else {
            self = Self.reading(start: try c.decode(Double.self, forKey: .start), end: try c.decode(Double.self, forKey: .end)).range
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(direction, forKey: .direction)
        try c.encode(amount, forKey: .amount)
    }
}

/// The first stroke's trim, for lines that draw themselves on. Its two
/// values share one direction, which the inspector sets for both.
public struct TrimAction: Codable, Sendable, Equatable {
    public var initial: TrimRange?
    public var end: TrimRange

    public init(initial: TrimRange? = nil, end: TrimRange) {
        self.initial = initial
        self.end = end
    }

    private enum CodingKeys: String, CodingKey { case initial, end }
    private struct Old: Decodable { var start: Double?; var end: Double? }

    /// Older actions stored a start and an end each side; the way the
    /// action draws is read from whichever side tells it, and both take it,
    /// so an old draw-on or wipe still plays the same way.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let oldEnd = try c.decode(Old.self, forKey: .end)
        let oldInitial = try c.decodeIfPresent(Old.self, forKey: .initial)
        guard let es = oldEnd.start, let ee = oldEnd.end else {
            initial = try c.decodeIfPresent(TrimRange.self, forKey: .initial)
            end = try c.decode(TrimRange.self, forKey: .end)
            return
        }
        let readEnd = TrimRange.reading(start: es, end: ee)
        let readInitial = oldInitial.flatMap { o in o.start.flatMap { s in o.end.map { TrimRange.reading(start: s, end: $0) } } }
        let direction = readEnd.certain ? readEnd.range.direction
            : readInitial?.certain == true ? readInitial!.range.direction : readEnd.range.direction
        end = TrimRange(direction: direction, amount: readEnd.range.amount)
        initial = readInitial.map { TrimRange(direction: direction, amount: $0.range.amount) }
    }
}

/// Which way moving dashes travel along the path.
public enum DashDirection: String, Codable, Sendable, CaseIterable {
    case forward, backward
}

/// Sets a dashed or dotted first stroke moving along its path, at `speed`
/// pixels a second for the length of the bar (eased as the bar is; Linear
/// is a steady flow). With `followsTrim` the dashes travel the way the
/// stroke's trim draws it, each part of it towards its growing tip, and
/// `direction` is not used.
public struct DashAction: Codable, Sendable, Equatable {
    public var speed: Double
    public var direction: DashDirection
    public var followsTrim: Bool

    public init(speed: Double = DashAction.standardSpeed, direction: DashDirection = .forward, followsTrim: Bool = false) {
        self.speed = speed
        self.direction = direction
        self.followsTrim = followsTrim
    }

    public static let standardSpeed = 40.0
}

/// A rectangle's corners, in pixels.
public struct CornerRadiusAction: Codable, Sendable, Equatable {
    public var initial: CornerRadii?
    public var end: CornerRadii
    /// Whether one number sets all four corners.
    public var isLinked: Bool

    public init(initial: CornerRadii? = nil, end: CornerRadii, isLinked: Bool = true) {
        self.initial = initial
        self.end = end
        self.isLinked = isLinked
    }
}

/// The first drop shadow. A layer designed without one starts from no shadow
/// at all: transparent, with no offset, blur or spread.
public struct ShadowAction: Codable, Sendable, Equatable {
    public var initial: DropShadow?
    public var end: DropShadow

    public init(initial: DropShadow? = nil, end: DropShadow) {
        self.initial = initial
        self.end = end
    }
}

/// The first layer blur's radius. A layer designed without one starts from 0.
public struct LayerBlurAction: Codable, Sendable, Equatable {
    public var initial: Double?
    public var end: Double

    public init(initial: Double? = nil, end: Double) {
        self.initial = initial
        self.end = end
    }
}

/// The first background blur. A layer designed without one starts from none.
public struct BackgroundBlurAction: Codable, Sendable, Equatable {
    public var initial: BackgroundBlur?
    public var end: BackgroundBlur

    public init(initial: BackgroundBlur? = nil, end: BackgroundBlur) {
        self.initial = initial
        self.end = end
    }
}

/// Extra space between letters, in pixels.
public struct LetterSpacingAction: Codable, Sendable, Equatable {
    public var initial: Double?
    public var end: Double

    public init(initial: Double? = nil, end: Double) {
        self.initial = initial
        self.end = end
    }
}

/// Baseline to baseline, in pixels. A layer whose line height is the font's
/// own starts from that.
public struct LineHeightAction: Codable, Sendable, Equatable {
    public var initial: Double?
    public var end: Double

    public init(initial: Double? = nil, end: Double) {
        self.initial = initial
        self.end = end
    }
}

/// How the whole layer changes from one text to the next.
public enum TextTransition: String, Codable, Sendable, CaseIterable {
    /// Swaps at once.
    case none
    case fade
    /// Out moves up and fades; in rises from below and fades up.
    case slide
    /// Out shrinks and fades; in grows from smaller and fades up.
    case scale
}

/// Counts from one number to another in the layer's text, keeping the text's
/// look: `$1,200.50` counts as dollars with a thousands separator and two
/// decimals; `007` keeps its zeros.
public struct CounterAction: Codable, Sendable, Equatable {
    /// Nil starts from the number in the text when the action begins, or 0.
    public var from: Double?
    public var to: Double
    /// The amount each change adds. Always positive; the count goes whichever
    /// way `to` is.
    public var step: Double
    /// How each number gives way to the next. Slide and fade roll
    /// continuously, like an odometer.
    public var transition: TextTransition

    public init(from: Double? = nil, to: Double, step: Double = 1, transition: TextTransition = .none) {
        self.from = from
        self.to = to
        self.step = step
        self.transition = transition
    }
}

/// Replaces the layer's text. The old text goes out in the first half of the
/// action and the new comes in during the second, or both at once when they
/// overlap.
public struct ChangeTextAction: Codable, Sendable, Equatable {
    public var text: String
    public var transitionOut: TextTransition
    public var transitionIn: TextTransition
    public var overlaps: Bool

    public init(text: String, transitionOut: TextTransition = .fade, transitionIn: TextTransition = .fade,
                overlaps: Bool = false) {
        self.text = text
        self.transitionOut = transitionOut
        self.transitionIn = transitionIn
        self.overlaps = overlaps
    }
}

/// An ellipse's slice and hole.
public struct ArcAction: Codable, Sendable, Equatable {
    public var initial: EllipseArc?
    public var end: EllipseArc

    public init(initial: EllipseArc? = nil, end: EllipseArc) {
        self.initial = initial
        self.end = end
    }
}

/// A star's points, inner radius and corner radius. The number of points
/// changes a whole point at a time.
public struct StarAction: Codable, Sendable, Equatable {
    public var initial: StarShape?
    public var end: StarShape

    public init(initial: StarShape? = nil, end: StarShape) {
        self.initial = initial
        self.end = end
    }
}

/// A pen path's shape: its points and handles, in the layer's own pixel
/// space. It blends point by point, so the end keeps the design's points,
/// only moved; a path with other points holds rather than morphing.
public struct PathAction: Codable, Sendable, Equatable {
    public var initial: BezierPath?
    public var end: BezierPath

    public init(initial: BezierPath? = nil, end: BezierPath) {
        self.initial = initial
        self.end = end
    }
}

/// Plays a video or audio layer's media: from `trimStart` seconds into the
/// file, for the action's duration, starting at the action's start. Before
/// it, a video shows the frame it will start on; after it, the frame it
/// stopped on. Every media layer gets one when it is imported.
public struct PlayAction: Codable, Sendable, Equatable {
    public var trimStart: Double

    public init(trimStart: Double = 0) {
        self.trimStart = trimStart
    }
}

/// A video's or a sound's level, 0 to 1 (100%, the file's own), fading
/// along the action's easing. Heard in preview and exports alike.
public struct VolumeAction: Codable, Sendable, Equatable {
    public var initial: Double?
    public var end: Double

    public init(initial: Double? = nil, end: Double) {
        self.initial = initial
        self.end = end
    }
}

/// Skew angles in degrees, each way (see `Transform.skew`). In By mode
/// `end` is added to the skew it starts from.
public struct SkewAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Vec2?
    public var end: Vec2

    public init(mode: ActionMode = .to, initial: Vec2? = nil, end: Vec2) {
        self.mode = mode
        self.initial = initial
        self.end = end
    }
}

/// A turn in depth (see `Tilt`). In By mode the angles of `end` are added to
/// those it starts from; its depth is always where it ends.
public struct TiltAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Tilt?
    public var end: Tilt

    public init(mode: ActionMode = .to, initial: Tilt? = nil, end: Tilt) {
        self.mode = mode
        self.initial = initial
        self.end = end
    }
}

/// Z, towards the viewer, in pixels (see `Transform.z`). In By mode `end`
/// is added to the Z it starts from.
public struct DepthAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Double?
    public var end: Double

    public init(mode: ActionMode = .to, initial: Double? = nil, end: Double) {
        self.mode = mode
        self.initial = initial
        self.end = end
    }
}

/// Degrees of curve each way (see `Transform.bend`). In By mode `end` is
/// added to the bend it starts from.
public struct BendAction: Codable, Sendable, Equatable {
    public var mode: ActionMode
    public var initial: Vec2?
    public var end: Vec2

    public init(mode: ActionMode = .to, initial: Vec2? = nil, end: Vec2) {
        self.mode = mode
        self.initial = initial
        self.end = end
    }
}

/// A frame in 3D's camera, blended from its starting value to `end`: the
/// camera's distance, vanishing point and orbit, and its depth fade,
/// depth blur and backs. Whether it is isometric is not blended: that stays as the
/// frame has it where the action starts.
public struct CameraAction: Codable, Sendable, Equatable {
    public var initial: Space3D?
    public var end: Space3D

    public init(initial: Space3D? = nil, end: Space3D) {
        self.initial = initial
        self.end = end
    }
}

/// A preset on one bar. It remembers which preset it is and the settings
/// the inspector shows for it; what it does to the layer is worked out when
/// it plays (`PresetRecipe`, in MotionEvaluation), from the layer as it is
/// when the bar starts, so it suits a layer wherever it is. Stretching the
/// bar stretches every part of it together. A setting left empty is the
/// preset's own default; only those the preset uses mean anything.
public struct PresetAction: Codable, Sendable, Equatable {
    public var preset: PresetKind
    /// Where a slide comes from, or goes to.
    public var direction: PresetDirection?
    /// Pixels: how far a slide, drop, bounce or shake travels.
    public var distance: Double?
    /// 1 is 100%: where a scale starts (entrances), ends (exits) or peaks
    /// (Pulse).
    public var scale: Double?
    /// Degrees: how far a rotation turns.
    public var angle: Double?
    /// Figma's pixels: how blurred it starts or ends.
    public var blur: Double?
    /// Whether it fades as it moves.
    public var fades: Bool?
    /// On a text layer, what moves on its own: each letter, word or line in
    /// turn. Nil moves the whole layer.
    public var unit: TextUnit?
    /// The order the letters, words or lines go in; nil is forward.
    public var order: TextOrder?
    /// Seconds between one letter, word or line starting and the next; nil
    /// is the unit's own (`TextUnit.delay`).
    public var delay: Double?
    /// The corner a page curl lifts from.
    public var corner: PresetCorner?

    public init(preset: PresetKind, direction: PresetDirection? = nil, distance: Double? = nil, scale: Double? = nil,
                angle: Double? = nil, blur: Double? = nil, fades: Bool? = nil, unit: TextUnit? = nil,
                order: TextOrder? = nil, delay: Double? = nil, corner: PresetCorner? = nil) {
        self.preset = preset
        self.corner = corner
        self.direction = direction
        self.distance = distance
        self.scale = scale
        self.angle = angle
        self.blur = blur
        self.fades = fades
        self.unit = unit
        self.order = order
        self.delay = delay
    }
}

/// Every preset there is. The raw values are what files store.
public enum PresetKind: String, Codable, Sendable, CaseIterable {
    case fadeIn = "fade-in", slideIn = "slide-in", scalePop = "scale-pop", rotateIn = "rotate-in"
    case blurIn = "blur-in", dropIn = "drop-in"
    case fadeOut = "fade-out", slideOut = "slide-out", scaleOut = "scale-out", blurOut = "blur-out"
    case rotateOut = "rotate-out", dropOut = "drop-out"
    case shrinkIn = "shrink-in", shrinkOut = "shrink-out", twistIn = "twist-in", twistOut = "twist-out"
    case moveScaleIn = "move-scale-in", moveScaleOut = "move-scale-out"
    case maskRevealIn = "mask-reveal-in", maskRevealOut = "mask-reveal-out"
    case maskCenterIn = "mask-center-in", maskCenterOut = "mask-center-out"
    case maskResizeIn = "mask-resize-in", maskResizeOut = "mask-resize-out"
    case maskSlideIn = "mask-slide-in", maskSlideOut = "mask-slide-out"
    case maskShrinkIn = "mask-shrink-in", maskShrinkOut = "mask-shrink-out"
    case blurSlideIn = "blur-slide-in", blurSlideOut = "blur-slide-out"
    case blurScaleIn = "blur-scale-in", blurScaleOut = "blur-scale-out"
    case fadeSoundIn = "fade-sound-in", fadeSoundOut = "fade-sound-out"
    case pulse, bounce, shake, wiggle
    /// Each letter (or word, or line) appears at once, in turn, spread
    /// evenly across the bar; Out takes them away the same way.
    case typewriterIn = "typewriter-in", typewriterOut = "typewriter-out"
    /// Turns on one edge like a page on its spine, as the onboarding's
    /// pages do: In comes down from edge-on, Out lifts away to it.
    case pageTurnIn = "page-turn-in", pageTurnOut = "page-turn-out"
    /// Curls away from a corner like a page of Apple Books, as Flip's
    /// onboarding pictures turn, showing what is under it: Out curls it
    /// off, In lays it down the same way played backwards.
    case pageCurlIn = "page-curl-in", pageCurlOut = "page-curl-out"
    /// The 3D group. Flip turns over on a level or upright line; Swing
    /// falls into place from an edge with a spring; Fold unrolls from a
    /// curve; Tumble turns every way as it comes from deep; Fly comes from
    /// far away or goes past the viewer; Iso Lift rises from lying flat as
    /// on an isometric floor. Spin 3D (a whole turn in depth) and Float (a
    /// slow drift in depth) leave the layer where it was.
    case flipIn = "flip-in", flipOut = "flip-out", swingIn = "swing-in", swingOut = "swing-out"
    case foldIn = "fold-in", foldOut = "fold-out", tumbleIn = "tumble-in", tumbleOut = "tumble-out"
    case flyIn = "fly-in", flyOut = "fly-out", isoLiftIn = "iso-lift-in", isoLiftOut = "iso-lift-out"
    case spin3D = "spin-3d", float
}

extension PresetKind {
    /// True for one that brings a layer (or a sound) on, false for one that
    /// takes it off, nil for one that leaves it where it was.
    public var entering: Bool? {
        switch self {
        case .fadeIn, .slideIn, .scalePop, .rotateIn, .blurIn, .dropIn, .fadeSoundIn, .shrinkIn, .twistIn, .moveScaleIn,
             .maskRevealIn, .maskCenterIn, .maskResizeIn, .maskSlideIn, .maskShrinkIn, .blurSlideIn, .blurScaleIn,
             .typewriterIn, .pageTurnIn, .pageCurlIn,
             .flipIn, .swingIn, .foldIn, .tumbleIn, .flyIn, .isoLiftIn: true
        case .fadeOut, .slideOut, .scaleOut, .rotateOut, .blurOut, .dropOut, .fadeSoundOut, .shrinkOut, .twistOut, .moveScaleOut,
             .maskRevealOut, .maskCenterOut, .maskResizeOut, .maskSlideOut, .maskShrinkOut, .blurSlideOut, .blurScaleOut,
             .typewriterOut, .pageTurnOut, .pageCurlOut,
             .flipOut, .swingOut, .foldOut, .tumbleOut, .flyOut, .isoLiftOut: false
        case .pulse, .bounce, .shake, .wiggle, .spin3D, .float: nil
        }
    }

    public var isSound: Bool { self == .fadeSoundIn || self == .fadeSoundOut }

    /// Whether it can only move the whole layer, never a text's letters one
    /// by one: a sound fade, a page curl, which curls one picture, and a
    /// fold, which bends one.
    public var movesWholeLayer: Bool {
        isSound || self == .pageCurlIn || self == .pageCurlOut || self == .foldIn || self == .foldOut
    }
}

/// What of a text moves on its own in a preset.
public enum TextUnit: String, Codable, Sendable, CaseIterable {
    case letters, words, lines

    /// The gap between one starting and the next, unless set.
    public var delay: Double {
        switch self {
        case .letters: 0.03
        case .words: 0.08
        case .lines: 0.15
        }
    }
}

/// The order letters, words or lines go in.
public enum TextOrder: String, Codable, Sendable, CaseIterable {
    /// First to last.
    case forward
    /// Last to first.
    case backward
    /// From the middle out to both ends.
    case center
    /// From both ends in to the middle.
    case edges
    /// Shuffled, the same way every time.
    case random
}

public enum PresetDirection: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom
}

public enum PresetCorner: String, Codable, Sendable, CaseIterable {
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
}

extension ActionSpec: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, move, scale, rotate, opacity, resize, visibility
        case color, stroke, trim, dash, cornerRadius, shadow, innerShadow, layerBlur, backgroundBlur
        case letterSpacing, lineHeight, counter, changeText, arc, star, path, play, volume, skew, tilt, depth, bend, camera, template, templateSetting, preset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(ActionKind.self, forKey: .type) {
        case .move: self = .move(try c.decode(MoveAction.self, forKey: .move))
        case .scale: self = .scale(try c.decode(ScaleAction.self, forKey: .scale))
        case .rotate: self = .rotate(try c.decode(RotateAction.self, forKey: .rotate))
        case .opacity: self = .opacity(try c.decode(OpacityAction.self, forKey: .opacity))
        case .resize: self = .resize(try c.decode(ResizeAction.self, forKey: .resize))
        case .visibility: self = .visibility(try c.decode(VisibilityAction.self, forKey: .visibility))
        case .color: self = .color(try c.decode(ColorAction.self, forKey: .color))
        case .stroke: self = .stroke(try c.decode(StrokeAction.self, forKey: .stroke))
        case .trim: self = .trim(try c.decode(TrimAction.self, forKey: .trim))
        case .dash: self = .dash(try c.decode(DashAction.self, forKey: .dash))
        case .cornerRadius: self = .cornerRadius(try c.decode(CornerRadiusAction.self, forKey: .cornerRadius))
        case .shadow: self = .shadow(try c.decode(ShadowAction.self, forKey: .shadow))
        case .innerShadow: self = .innerShadow(try c.decode(ShadowAction.self, forKey: .innerShadow))
        case .layerBlur: self = .layerBlur(try c.decode(LayerBlurAction.self, forKey: .layerBlur))
        case .backgroundBlur: self = .backgroundBlur(try c.decode(BackgroundBlurAction.self, forKey: .backgroundBlur))
        case .letterSpacing: self = .letterSpacing(try c.decode(LetterSpacingAction.self, forKey: .letterSpacing))
        case .lineHeight: self = .lineHeight(try c.decode(LineHeightAction.self, forKey: .lineHeight))
        case .counter: self = .counter(try c.decode(CounterAction.self, forKey: .counter))
        case .changeText: self = .changeText(try c.decode(ChangeTextAction.self, forKey: .changeText))
        case .arc: self = .arc(try c.decode(ArcAction.self, forKey: .arc))
        case .star: self = .star(try c.decode(StarAction.self, forKey: .star))
        case .path: self = .path(try c.decode(PathAction.self, forKey: .path))
        case .play: self = .play(try c.decode(PlayAction.self, forKey: .play))
        case .volume: self = .volume(try c.decode(VolumeAction.self, forKey: .volume))
        case .skew: self = .skew(try c.decode(SkewAction.self, forKey: .skew))
        case .tilt: self = .tilt(try c.decode(TiltAction.self, forKey: .tilt))
        case .depth: self = .depth(try c.decode(DepthAction.self, forKey: .depth))
        case .bend: self = .bend(try c.decode(BendAction.self, forKey: .bend))
        case .camera: self = .camera(try c.decode(CameraAction.self, forKey: .camera))
        case .template: self = .template(try c.decode(TemplatePlay.self, forKey: .template))
        case .templateSetting: self = .templateSetting(try c.decode(TemplateSettingAction.self, forKey: .templateSetting))
        case .preset: self = .preset(try c.decode(PresetAction.self, forKey: .preset))
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
        case .color(let v): try c.encode(v, forKey: .color)
        case .stroke(let v): try c.encode(v, forKey: .stroke)
        case .trim(let v): try c.encode(v, forKey: .trim)
        case .dash(let v): try c.encode(v, forKey: .dash)
        case .cornerRadius(let v): try c.encode(v, forKey: .cornerRadius)
        case .shadow(let v): try c.encode(v, forKey: .shadow)
        case .innerShadow(let v): try c.encode(v, forKey: .innerShadow)
        case .layerBlur(let v): try c.encode(v, forKey: .layerBlur)
        case .backgroundBlur(let v): try c.encode(v, forKey: .backgroundBlur)
        case .letterSpacing(let v): try c.encode(v, forKey: .letterSpacing)
        case .lineHeight(let v): try c.encode(v, forKey: .lineHeight)
        case .counter(let v): try c.encode(v, forKey: .counter)
        case .changeText(let v): try c.encode(v, forKey: .changeText)
        case .arc(let v): try c.encode(v, forKey: .arc)
        case .star(let v): try c.encode(v, forKey: .star)
        case .path(let v): try c.encode(v, forKey: .path)
        case .play(let v): try c.encode(v, forKey: .play)
        case .volume(let v): try c.encode(v, forKey: .volume)
        case .skew(let v): try c.encode(v, forKey: .skew)
        case .tilt(let v): try c.encode(v, forKey: .tilt)
        case .depth(let v): try c.encode(v, forKey: .depth)
        case .bend(let v): try c.encode(v, forKey: .bend)
        case .camera(let v): try c.encode(v, forKey: .camera)
        case .template(let v): try c.encode(v, forKey: .template)
        case .templateSetting(let v): try c.encode(v, forKey: .templateSetting)
        case .preset(let v): try c.encode(v, forKey: .preset)
        }
    }
}
