import Foundation
import MotionModel

/// A property of a layer that actions can drive. Each action drives exactly
/// one. Actions on different channels always run together; only actions on
/// the same channel of the same layer interact (see `walk`).
public enum Channel: String, Hashable, Sendable, CaseIterable {
    case position, scale, rotation, opacity, size, visibility
    case fill, stroke, trim, cornerRadius, shadow, layerBlur, backgroundBlur
    case letterSpacing, lineHeight, text, arc, star, path
    case media, volume
}

extension ActionKind {
    public var channel: Channel {
        switch self {
        case .move: return .position
        case .scale: return .scale
        case .rotate: return .rotation
        case .opacity: return .opacity
        case .resize: return .size
        case .visibility: return .visibility
        case .color: return .fill
        case .stroke: return .stroke
        case .trim: return .trim
        case .cornerRadius: return .cornerRadius
        case .shadow: return .shadow
        case .layerBlur: return .layerBlur
        case .backgroundBlur: return .backgroundBlur
        case .letterSpacing: return .letterSpacing
        case .lineHeight: return .lineHeight
        case .counter, .changeText: return .text
        case .arc: return .arc
        case .star: return .star
        case .path: return .path
        case .play: return .media
        case .volume: return .volume
        }
    }
}

/// The words a text layer shows at one moment, and, part way through a
/// Counter or a Change Text, the words on their way out.
public struct ShownText: Sendable, Equatable {
    public var text: String
    public var swap: TextSwap?
    /// Set while a Counter is counting, so its digits keep an even width.
    public var isCounting: Bool

    public init(text: String, swap: TextSwap? = nil, isCounting: Bool = false) {
        self.text = text
        self.swap = swap
        self.isCounting = isCounting
    }

    /// The text that takes up the box: the new one once it has begun to
    /// arrive, the old one before.
    public var visible: String {
        guard let swap else { return text }
        return swap.inProgress > 0 ? text : swap.previous
    }
}

/// One text giving way to another. The previous text shows until its
/// `outProgress` reaches 1, the current one from when its `inProgress`
/// passes 0, each with its transition at that point.
public struct TextSwap: Sendable, Equatable {
    public var previous: String
    public var transitionOut: TextTransition
    public var transitionIn: TextTransition
    public var outProgress: Double
    public var inProgress: Double

    public init(previous: String, transitionOut: TextTransition, transitionIn: TextTransition,
                outProgress: Double, inProgress: Double) {
        self.previous = previous
        self.transitionOut = transitionOut
        self.transitionIn = transitionIn
        self.outProgress = outProgress
        self.inProgress = inProgress
    }
}

/// The part of a layer that actions can change, at one moment: its design
/// state with every action applied.
public struct LayerState: Sendable, Equatable {
    public var position: Vec2
    public var scale: Vec2
    /// Degrees, clockwise, never wrapped.
    public var rotation: Double
    /// Not clamped here, so an overshooting fade still reads true; the scene
    /// clamps it to 0...1 for drawing.
    public var opacity: Double
    public var size: Size2
    public var isShown: Bool
    /// The first fill's paint, or nil for a layer with no fill: Colour acts
    /// on nothing then.
    public var fill: Paint?
    /// The first stroke's width and paint, nil without a stroke.
    public var stroke: StrokeLook?
    /// The first stroke's trim, nil without a stroke.
    public var trim: TrimRange?
    /// A rectangle's corners, nil for any other layer.
    public var cornerRadii: CornerRadii?
    /// The first shadow that is switched on, or `.noShadow`.
    public var shadow: DropShadow
    /// The first layer blur that is switched on, or 0.
    public var layerBlur: Double
    /// The first background blur that is switched on, or `.noBlur`.
    public var backgroundBlur: BackgroundBlur
    /// Text layers only: letter spacing, line height (the font's own when the
    /// design leaves it empty) and the words.
    public var letterSpacing: Double?
    public var lineHeight: Double?
    public var text: ShownText?
    /// An ellipse's slice and hole, nil for any other layer.
    public var arc: EllipseArc?
    /// A star's shape, nil for any other layer.
    public var star: StarShape?
    /// A pen path's points, nil for any other layer.
    public var path: BezierPath?
    /// Video and audio only: where in the file the layer is, in seconds.
    public var sourceTime: Double?
    /// Video and audio only: the sound's level, 1 being the file's own.
    public var volume: Double?

    /// The layer as it is designed, with no actions.
    public init(design layer: Layer) {
        position = layer.transform.position
        scale = layer.transform.scale
        rotation = layer.transform.rotation
        opacity = layer.opacity
        size = layer.size
        isShown = true
        if case .shape(let shape) = layer.content {
            fill = shape.fills.first?.paint
            stroke = shape.strokes.first.map { StrokeLook(width: $0.width, paint: $0.paint) }
            trim = shape.strokes.first.map { TrimRange(start: $0.trimStart, end: $0.trimEnd) }
            switch shape.geometry {
            case .rectangle(let radii): cornerRadii = radii
            case .ellipse(let a): arc = a
            case .star(let points, let inner, let corner):
                star = StarShape(points: points, innerRadius: inner, cornerRadius: corner)
            case .path(let p): path = p
            default: break
            }
        }
        switch layer.content {
        // Levels stop at the file's own; older projects could go higher.
        case .video(let v): sourceTime = 0; volume = min(v.volume, 1)
        case .audio(let a): sourceTime = 0; volume = min(a.volume, 1)
        default: break
        }
        if case .text(let t) = layer.content {
            // A text's colour is its fill, so Colour acts on it too.
            fill = .solid(t.color)
            letterSpacing = t.letterSpacing
            lineHeight = t.lineHeight ?? TextLayout.naturalLineHeight(TextStyle(t))
            text = ShownText(text: t.text)
        }
        shadow = .noShadow
        layerBlur = 0
        backgroundBlur = .noBlur
        for effect in layer.effects.reversed() where effect.isEnabled {
            switch effect.kind {
            case .dropShadow(let s): shadow = s
            case .layerBlur(let b): layerBlur = b.radius
            case .backgroundBlur(let b): backgroundBlur = b
            }
        }
    }
}

/// Every enabled action in a project, sorted into one track per layer and
/// channel, ready to be evaluated at any moment, including between frames.
public struct ActionTracks: Sendable {
    private var tracks: [UUID: [Channel: [Action]]] = [:]

    public init(_ actions: [Action]) {
        for action in actions where action.isEnabled {
            tracks[action.targetLayerID, default: [:]][action.spec.kind.channel, default: []].append(action)
        }
        for (layer, channels) in tracks {
            for (channel, list) in channels {
                tracks[layer]?[channel] = list.sorted(by: Self.order)
            }
        }
    }

    /// Earlier start first; actions that start together go in row order.
    /// The id settles anything still tied, so the order never depends on how
    /// the list happened to be stored.
    static func order(_ a: Action, _ b: Action) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.rowOrder != b.rowOrder { return a.rowOrder < b.rowOrder }
        return a.id.precedes(b.id)
    }

    public var isEmpty: Bool { tracks.isEmpty }

    /// `layer` at `time`, with every action on it applied.
    public func state(of layer: Layer, at time: Double) -> LayerState {
        state(of: layer, at: time) { _ in true }
    }

    /// What an action picks up from when it has no initial value of its own:
    /// the layer at the action's start, with only the actions before it on
    /// its channel applied. The inspector shows this as the placeholder for
    /// an empty starting value.
    public func inheritedState(for action: Action, of layer: Layer) -> LayerState {
        let channel = action.spec.kind.channel
        let earlier = Set((tracks[layer.id]?[channel] ?? []).prefix { $0.id != action.id }.map(\.id))
        return state(of: layer, at: action.start) { $0.spec.kind.channel != channel || earlier.contains($0.id) }
    }

    private func state(of layer: Layer, at time: Double, including: (Action) -> Bool) -> LayerState {
        var state = LayerState(design: layer)
        guard let channels = tracks[layer.id] else { return state }
        func list(_ channel: Channel) -> [Action] { (channels[channel] ?? []).filter(including) }

        state.position = walk(state.position, list(.position).compactMap(Self.positionStep), at: time)
        state.scale = walk(state.scale, list(.scale).compactMap(Self.scaleStep), at: time)
        state.rotation = walk(state.rotation, list(.rotation).compactMap(Self.rotationStep), at: time)
        state.opacity = walk(state.opacity, list(.opacity).compactMap(Self.opacityStep), at: time)
        state.size = walk(state.size, list(.size).compactMap(Self.sizeStep), at: time)
        state.isShown = walk(1, Self.visibilitySteps(list(.visibility)), at: time) > 0.5
        // Only what the layer has: a Colour on a layer with no fill does nothing.
        if let fill = state.fill { state.fill = walk(fill, list(.fill).compactMap(Self.fillStep), at: time) }
        if let stroke = state.stroke { state.stroke = walk(stroke, list(.stroke).compactMap(Self.strokeStep), at: time) }
        if let trim = state.trim { state.trim = walk(trim, list(.trim).compactMap(Self.trimStep), at: time) }
        if let radii = state.cornerRadii {
            state.cornerRadii = walk(radii, list(.cornerRadius).compactMap(Self.cornerStep), at: time)
        }
        state.shadow = walk(state.shadow, list(.shadow).compactMap(Self.shadowStep), at: time)
        state.layerBlur = walk(state.layerBlur, list(.layerBlur).compactMap(Self.layerBlurStep), at: time)
        state.backgroundBlur = walk(state.backgroundBlur, list(.backgroundBlur).compactMap(Self.backgroundBlurStep),
                                    at: time)
        if let spacing = state.letterSpacing {
            state.letterSpacing = walk(spacing, list(.letterSpacing).compactMap(Self.letterSpacingStep), at: time)
        }
        if let height = state.lineHeight {
            state.lineHeight = walk(height, list(.lineHeight).compactMap(Self.lineHeightStep), at: time)
        }
        if let shown = state.text { state.text = Self.shownText(design: shown.text, list(.text), at: time) }
        if let arc = state.arc { state.arc = walk(arc, list(.arc).compactMap(Self.arcStep), at: time) }
        if let star = state.star { state.star = walk(star, list(.star).compactMap(Self.starStep), at: time) }
        if let path = state.path { state.path = walk(path, list(.path).compactMap(Self.pathStep), at: time) }
        if let volume = state.volume { state.volume = walk(volume, list(.volume).compactMap(Self.volumeStep), at: time) }
        if state.sourceTime != nil { state.sourceTime = Self.sourceTime(list(.media), at: time) }
        return state
    }

    // MARK: Actions as steps

    private static func positionStep(_ a: Action) -> Step<Vec2>? {
        guard case .move(let m) = a.spec else { return nil }
        let travel: ((Vec2, Vec2, Double) -> Vec2)? = m.curve.map { curve in
            { from, to, p in cubic(from, from + curve.startHandle, to + curve.endHandle, to, p) }
        }
        return Step(a, initial: m.initial, target: m.mode == .to ? { _ in m.end } : { $0 + m.end }, travel: travel)
    }

    private static func scaleStep(_ a: Action) -> Step<Vec2>? {
        guard case .scale(let s) = a.spec else { return nil }
        return Step(a, initial: s.initial,
                    target: s.mode == .to ? { _ in s.end } : { Vec2($0.x * s.end.x, $0.y * s.end.y) })
    }

    private static func rotationStep(_ a: Action) -> Step<Double>? {
        guard case .rotate(let r) = a.spec else { return nil }
        return Step(a, initial: r.initial, target: r.mode == .to ? { _ in r.end } : { $0 + r.end })
    }

    private static func opacityStep(_ a: Action) -> Step<Double>? {
        guard case .opacity(let o) = a.spec else { return nil }
        return Step(a, initial: o.initial, target: { _ in o.end })
    }

    private static func sizeStep(_ a: Action) -> Step<Size2>? {
        guard case .resize(let r) = a.spec else { return nil }
        return Step(a, initial: r.initial, target: { _ in r.end })
    }

    private static func fillStep(_ a: Action) -> Step<Paint>? {
        guard case .color(let c) = a.spec else { return nil }
        return Step(a, initial: c.initial, target: { _ in c.end })
    }

    private static func strokeStep(_ a: Action) -> Step<StrokeLook>? {
        guard case .stroke(let st) = a.spec else { return nil }
        return Step(a, initial: st.initial, target: { _ in st.end })
    }

    private static func trimStep(_ a: Action) -> Step<TrimRange>? {
        guard case .trim(let tr) = a.spec else { return nil }
        return Step(a, initial: tr.initial, target: { _ in tr.end })
    }

    private static func cornerStep(_ a: Action) -> Step<CornerRadii>? {
        guard case .cornerRadius(let c) = a.spec else { return nil }
        return Step(a, initial: c.initial, target: { _ in c.end })
    }

    private static func shadowStep(_ a: Action) -> Step<DropShadow>? {
        guard case .shadow(let sh) = a.spec else { return nil }
        return Step(a, initial: sh.initial, target: { _ in sh.end })
    }

    private static func layerBlurStep(_ a: Action) -> Step<Double>? {
        guard case .layerBlur(let b) = a.spec else { return nil }
        return Step(a, initial: b.initial, target: { _ in b.end })
    }

    private static func backgroundBlurStep(_ a: Action) -> Step<BackgroundBlur>? {
        guard case .backgroundBlur(let b) = a.spec else { return nil }
        return Step(a, initial: b.initial, target: { _ in b.end })
    }

    private static func letterSpacingStep(_ a: Action) -> Step<Double>? {
        guard case .letterSpacing(let v) = a.spec else { return nil }
        return Step(a, initial: v.initial, target: { _ in v.end })
    }

    private static func lineHeightStep(_ a: Action) -> Step<Double>? {
        guard case .lineHeight(let v) = a.spec else { return nil }
        return Step(a, initial: v.initial, target: { _ in v.end })
    }

    private static func arcStep(_ a: Action) -> Step<EllipseArc>? {
        guard case .arc(let v) = a.spec else { return nil }
        return Step(a, initial: v.initial, target: { _ in v.end })
    }

    private static func starStep(_ a: Action) -> Step<StarShape>? {
        guard case .star(let v) = a.spec else { return nil }
        return Step(a, initial: v.initial, target: { _ in v.end })
    }

    private static func pathStep(_ a: Action) -> Step<BezierPath>? {
        guard case .path(let v) = a.spec else { return nil }
        return Step(a, initial: v.initial, target: { _ in v.end })
    }

    private static func volumeStep(_ a: Action) -> Step<Double>? {
        guard case .volume(let v) = a.spec else { return nil }
        return Step(a, initial: v.initial, target: { _ in v.end })
    }

    // MARK: Media

    /// Where in its file a media layer is at `time`. The latest Play to have
    /// started is the one showing; before the first, the layer waits on the
    /// frame it will start with, and after a Play ends it rests on the frame
    /// it stopped on.
    static func sourceTime(_ plays: [Action], at time: Double) -> Double {
        let runs = plays.compactMap { a -> (Action, PlayAction)? in
            if case .play(let p) = a.spec { return (a, p) }
            return nil
        }
        guard let first = runs.first else { return 0 }
        guard time >= first.0.start else { return first.1.trimStart }
        let (action, play) = runs.last { $0.0.start <= time } ?? first
        return play.trimStart + min(max(time - action.start, 0), action.duration)
    }

    // MARK: Text

    /// The text channel follows the same rules as the rest, with words in
    /// place of numbers: actions in start order, each taking over from the
    /// text showing when it starts, and a first Counter with its own From
    /// showing that number from the start of the scene.
    static func shownText(design: String, _ actions: [Action], at time: Double) -> ShownText {
        guard let first = actions.first else { return ShownText(text: design) }
        if time < first.start {
            if case .counter(let c) = first.spec, let from = c.from {
                return ShownText(text: Counting(c, base: design).text(for: from), isCounting: true)
            }
            return ShownText(text: design)
        }
        var current: (action: Action, base: String)?
        for action in actions where action.start <= time {
            let base = current.map { settledText($0.action, base: $0.base, at: action.start) } ?? design
            current = (action, base)
        }
        guard let current else { return ShownText(text: design) }
        return shown(current.action, base: current.base, at: time)
    }

    /// What an action is showing at `time` with any transition finished: the
    /// number a counter has reached, or whichever text a change is on.
    private static func settledText(_ action: Action, base: String, at time: Double) -> String {
        let s = shown(action, base: base, at: time)
        guard let swap = s.swap else { return s.text }
        if case .counter = action.spec { return swap.previous }
        return s.visible
    }

    private static func progress(_ action: Action, at time: Double) -> Double {
        guard action.duration > 0 else { return 1 }
        return min(max(action.easing.progress((time - action.start) / action.duration), 0), 1)
    }

    private static func shown(_ action: Action, base: String, at time: Double) -> ShownText {
        let p = time >= action.end ? 1 : progress(action, at: time)
        switch action.spec {
        case .counter(let c):
            let counting = Counting(c, base: base)
            let q = counting.steps * p
            guard p < 1, q < counting.steps else { return ShownText(text: counting.text(for: c.to), isCounting: true) }
            let k = q.rounded(.down), frac = q - k
            let now = counting.text(for: counting.value(atStep: k))
            guard c.transition != .none, frac > 0 else { return ShownText(text: now, isCounting: true) }
            return ShownText(text: counting.text(for: counting.value(atStep: k + 1)),
                             swap: TextSwap(previous: now, transitionOut: c.transition, transitionIn: c.transition,
                                            outProgress: frac, inProgress: frac),
                             isCounting: true)
        case .changeText(let change):
            guard p < 1 else { return ShownText(text: change.text) }
            let out = change.overlaps ? p : min(1, p * 2)
            let into = change.overlaps ? p : max(0, p * 2 - 1)
            return ShownText(text: change.text, swap: TextSwap(previous: base, transitionOut: change.transitionOut,
                                                               transitionIn: change.transitionIn,
                                                               outProgress: out, inProgress: into))
        default:
            return ShownText(text: base)
        }
    }

    /// Visibility walks as 1 (shown) and 0 (hidden), every step instant. The
    /// first visibility action on a layer starts from the opposite of what it
    /// sets, so a layer whose first one is a Show is hidden until it: the
    /// entrance rule, applied to Hide/Show.
    private static func visibilitySteps(_ actions: [Action]) -> [Step<Double>] {
        actions.enumerated().compactMap { index, a in
            guard case .visibility(let v) = a.spec else { return nil }
            let end: Double = v.isVisible ? 1 : 0
            return Step(a, initial: index == 0 ? 1 - end : nil, target: { _ in end })
        }
    }
}

// MARK: - The rules

/// One action on one channel, reduced to what the walk needs.
struct Step<V: Interpolatable> {
    var start: Double
    var duration: Double
    var isInstant: Bool
    var easing: Easing
    var initial: V?
    /// The end value, given the value the action starts from. A To action
    /// ignores it; a By action builds on it.
    var target: (V) -> V
    /// How the value travels from start to end at eased progress `p`.
    /// Straight unless a Move is curved.
    var travel: ((V, V, Double) -> V)?

    init(_ action: Action, initial: V?, target: @escaping (V) -> V, travel: ((V, V, Double) -> V)? = nil) {
        start = action.start
        duration = action.duration
        isInstant = action.isInstant
        easing = action.easing
        self.initial = initial
        self.target = target
        self.travel = travel
    }
}

/// The value of one channel at `time`, from its design value and its
/// actions, which must be sorted by start (ties in row order).
///
/// These are the rules actions follow, all of them here:
///
/// 1. Start from the design value.
/// 2. Take the channel's actions in order of start.
/// 3. An action's starting value is its explicit initial value if it has
///    one. Otherwise it inherits the channel's value at the moment it starts:
///    the design value plus everything earlier actions have done by then. So
///    a second Move continues from wherever the first one left off.
/// 4. Before an action starts it has no effect, with one exception: the first
///    action on a channel, if it has an explicit initial value, holds that
///    value from the start of the scene. That is what makes an entrance work:
///    a fade from 0% to 100% at 2 s keeps the layer invisible until 2 s.
/// 5. While an action runs, the value goes from its starting value to its end
///    value along its easing. After it ends, the end value holds until a later
///    action on the channel changes it.
/// 6. Overlaps: when an action starts while an earlier one on the same channel
///    is still running, the later one takes over from the value at its own
///    start, and the earlier one stops having any effect. Actions on
///    different channels never interfere.
/// 7. Instant actions (zero duration, and every Hide/Show) jump to their end
///    value at their start, with no easing.
func walk<V: Interpolatable>(_ design: V, _ steps: [Step<V>], at time: Double) -> V {
    guard let first = steps.first else { return design }
    if time < first.start { return first.initial ?? design }        // rules 1 and 4

    var current: (step: Step<V>, from: V, to: V)?
    for step in steps {
        guard step.start <= time else { break }                      // rule 4: not started yet
        let inherited = current.map { value(of: $0, at: step.start) } ?? design
        let from = step.initial ?? inherited                          // rule 3
        current = (step, from, step.target(from))                     // rule 6: it takes over
    }
    return current.map { value(of: $0, at: time) } ?? design
}

/// One action's value at `time`, which is at or after its start.
private func value<V: Interpolatable>(of run: (step: Step<V>, from: V, to: V), at time: Double) -> V {
    let s = run.step
    if s.isInstant || time >= s.start + s.duration { return run.to }  // rules 5 and 7
    let p = s.easing.progress((time - s.start) / s.duration)
    return s.travel?(run.from, run.to, p) ?? V.interpolate(run.from, run.to, p)
}

/// A point along a cubic bezier. `p` may leave 0...1 for easings that
/// overshoot, and the curve simply carries on past its ends.
private func cubic(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2, _ p: Double) -> Vec2 {
    let q = 1 - p
    let wa = q * q * q, wb = 3 * q * q * p, wc = 3 * q * p * p, wd = p * p * p
    return Vec2(wa * a.x + wb * b.x + wc * c.x + wd * d.x, wa * a.y + wb * b.y + wc * c.y + wd * d.y)
}

/// A Counter worked out against the text it starts from: where it counts
/// from, how many steps it takes, and how each number is written.
struct Counting {
    let from: Double
    let to: Double
    let step: Double
    let format: NumberFormat

    init(_ counter: CounterAction, base: String) {
        let read = NumberFormat.read(base)
        from = counter.from ?? read?.value ?? 0
        to = counter.to
        step = counter.step > 0 ? counter.step : 1
        var format = read?.format ?? NumberFormat()
        format.decimals = max(format.decimals, NumberFormat.decimals(of: step), NumberFormat.decimals(of: from),
                              NumberFormat.decimals(of: to))
        self.format = format
    }

    /// Steps from `from` to `to`, which need not be a whole number: the last
    /// step lands on `to` however far short of a full step it is.
    var steps: Double { abs(to - from) / step }

    func value(atStep k: Double) -> Double {
        k >= steps ? to : from + (to >= from ? 1 : -1) * k * step
    }

    func text(for value: Double) -> String { format.text(for: value) }
}
