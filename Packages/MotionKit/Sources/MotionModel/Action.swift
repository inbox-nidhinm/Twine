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
    case color(ColorAction)
    case stroke(StrokeAction)
    case trim(TrimAction)
    case cornerRadius(CornerRadiusAction)
    case shadow(ShadowAction)
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
        case .preset: return .preset
        }
    }
}

public enum ActionKind: String, Codable, Sendable, CaseIterable {
    case move, scale, rotate, opacity, resize, visibility
    case color, stroke, trim, cornerRadius, shadow
    case layerBlur, backgroundBlur
    case letterSpacing, lineHeight, counter, changeText
    case arc, star, path
    case play, volume
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
        case .cornerRadius: return "Corner Radius"
        case .shadow: return "Shadow"
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
        case .preset: return "Preset"
        }
    }

    /// The group it is listed under when adding an action.
    public var category: ActionCategory {
        switch self {
        case .move, .scale, .rotate, .opacity, .resize, .visibility: return .transform
        case .color, .stroke, .trim, .cornerRadius, .shadow: return .style
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
    case transform, style, blur, text, shape, media

    public var title: String {
        switch self {
        case .transform: return "Transform"
        case .style: return "Style"
        case .blur: return "Blur"
        case .text: return "Text"
        case .shape: return "Shape"
        case .media: return "Media"
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

/// How much of a stroke is drawn, as fractions of the path's length from its
/// start. 0 to 1 draws all of it; 0 to 0 draws none.
public struct TrimRange: AnimatableValue {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public static let whole = TrimRange(start: 0, end: 1)
}

/// The first stroke's trim, for lines that draw themselves on.
public struct TrimAction: Codable, Sendable, Equatable {
    public var initial: TrimRange?
    public var end: TrimRange

    public init(initial: TrimRange? = nil, end: TrimRange) {
        self.initial = initial
        self.end = end
    }
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

    public init(preset: PresetKind, direction: PresetDirection? = nil, distance: Double? = nil, scale: Double? = nil,
                angle: Double? = nil, blur: Double? = nil, fades: Bool? = nil) {
        self.preset = preset
        self.direction = direction
        self.distance = distance
        self.scale = scale
        self.angle = angle
        self.blur = blur
        self.fades = fades
    }
}

/// Every preset there is. The raw values are what files store.
public enum PresetKind: String, Codable, Sendable, CaseIterable {
    case fadeIn = "fade-in", slideIn = "slide-in", scalePop = "scale-pop", rotateIn = "rotate-in"
    case blurIn = "blur-in", dropIn = "drop-in"
    case fadeOut = "fade-out", slideOut = "slide-out", scaleOut = "scale-out", blurOut = "blur-out"
    case fadeSoundIn = "fade-sound-in", fadeSoundOut = "fade-sound-out"
    case pulse, bounce, shake, wiggle
}

public enum PresetDirection: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom
}

extension ActionSpec: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, move, scale, rotate, opacity, resize, visibility
        case color, stroke, trim, cornerRadius, shadow, layerBlur, backgroundBlur
        case letterSpacing, lineHeight, counter, changeText, arc, star, path, play, volume, preset
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
        case .cornerRadius: self = .cornerRadius(try c.decode(CornerRadiusAction.self, forKey: .cornerRadius))
        case .shadow: self = .shadow(try c.decode(ShadowAction.self, forKey: .shadow))
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
        case .cornerRadius(let v): try c.encode(v, forKey: .cornerRadius)
        case .shadow(let v): try c.encode(v, forKey: .shadow)
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
        case .preset(let v): try c.encode(v, forKey: .preset)
        }
    }
}
