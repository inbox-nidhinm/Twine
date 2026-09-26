import Foundation
import MotionModel

/// A property of a layer that actions can drive. Each action drives exactly
/// one. Actions on different channels always run together; only actions on
/// the same channel of the same layer interact (see `walk`).
public enum Channel: String, Hashable, Sendable, CaseIterable {
    case position, scale, rotation, opacity, size, visibility
    case fill, stroke, trim, cornerRadius, shadow, layerBlur, backgroundBlur
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
        }
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
            if case .rectangle(let radii) = shape.geometry { cornerRadii = radii }
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
        return a.id.uuidString < b.id.uuidString
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
