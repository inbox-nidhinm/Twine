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
    case skew, tilt
    /// A clip of the layer's own box, which only the Mask presets drive.
    case reveal
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
        case .skew: return .skew
        case .tilt: return .tilt
        // A preset reaches several; `ActionTracks` asks its recipe which.
        case .preset: return .position
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
    /// Skew and tilt, boxed when there are any (see `Warp`).
    public var warp: Warp
    /// Degrees each way (see `Transform.skew`).
    public var skew: Vec2 {
        get { warp.skew }
        set { warp = Warp(skew: newValue, tilt: warp.tilt) }
    }
    /// A turn in depth (see `Tilt`).
    public var tilt: Tilt {
        get { warp.tilt }
        set { warp = Warp(skew: warp.skew, tilt: newValue) }
    }
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
    /// A clip of the layer's own box, from a Mask preset; `.none` otherwise.
    public var reveal: Reveal = .none

    /// The layer as it is designed, with no actions.
    public init(design layer: Layer) {
        position = layer.transform.position
        scale = layer.transform.scale
        rotation = layer.transform.rotation
        warp = Warp(skew: layer.transform.skew, tilt: layer.transform.tilt)
        opacity = layer.opacity
        size = layer.size
        isShown = true
        if let shape = layer.look {
            fill = shape.fills.last?.paint
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
            // Inner shadows are drawn as designed; no action changes them.
            case .innerShadow: break
            case .layerBlur(let b): layerBlur = b.radius
            case .backgroundBlur(let b): backgroundBlur = b
            }
        }
    }
}

/// A layer's skew and tilt, kept out of line: most layers have neither, and
/// carrying five more numbers in every layer's state made each frame's
/// evaluation measurably slower.
public enum Warp: Sendable, Equatable {
    case none
    indirect case warped(skew: Vec2, tilt: Tilt)

    public init(skew: Vec2, tilt: Tilt) {
        self = skew == .zero && tilt == .none ? .none : .warped(skew: skew, tilt: tilt)
    }

    public var skew: Vec2 {
        if case .warped(let skew, _) = self { return skew }
        return .zero
    }

    public var tilt: Tilt {
        if case .warped(_, let tilt) = self { return tilt }
        return .none
    }
}

extension Action {
    /// Whether it moves its layer, or a text's letters, so motion blur has
    /// something to smear: a Move, Scale, Rotate, Skew or Tilt, or a preset
    /// that moves, scales, turns or tilts.
    public var canMotionBlur: Bool {
        if case .preset(let p) = spec { return !p.preset.isSound && !PresetRecipe.channels(p).isDisjoint(with: ActionTracks.moving) }
        return ActionTracks.moving.contains(spec.kind.channel)
    }
}

/// Every enabled action in a project, sorted into one track per layer and
/// channel, ready to be evaluated at any moment, including between frames.
public struct ActionTracks: Sendable {
    private var tracks: [UUID: [Channel: [Action]]] = [:]
    /// Each preset's parts, worked out once.
    private var presetParts: [UUID: [PresetPart]] = [:]
    /// The layers with a preset on them. Only they take the slower way.
    private var presetLayers: Set<UUID> = []
    /// The layers with a Move that turns them along its path (rule 9).
    private var turningLayers: Set<UUID> = []
    /// Presets that move a text's letters, words or lines one by one, by
    /// layer, in start order. They leave the layer's own channels alone.
    private var textPresets: [UUID: [TextPreset]] = [:]
    /// Actions with motion blur on, by layer, with the moving channels each
    /// drives. A text preset's letters blur through `TextAnimation` instead.
    private var blurs: [UUID: [BlurRun]] = [:]

    private struct BlurRun: Sendable {
        let start: Double
        let end: Double
        let shutter: Double
        let channels: Set<Channel>
    }

    /// The channels motion blur spreads: those that move a layer.
    static let moving: Set<Channel> = [.position, .scale, .rotation, .skew, .tilt]

    public init(_ actions: [Action]) {
        // In presets, which show their layer as a Show does (rule 10).
        var entrances: [UUID: [Action]] = [:]
        for action in actions where action.isEnabled {
            if case .preset(let p) = action.spec, p.preset.entering == true, !p.preset.isSound {
                entrances[action.targetLayerID, default: []].append(action)
            }
            if case .preset(let p) = action.spec, p.unit != nil {
                textPresets[action.targetLayerID, default: []].append(TextPreset(action, p))
            } else if case .preset(let p) = action.spec {
                // On every property it reaches, as one action there.
                let parts = PresetRecipe.parts(p)
                presetParts[action.id] = parts
                presetLayers.insert(action.targetLayerID)
                for channel in Set(parts.map(\.effect.channel)) {
                    tracks[action.targetLayerID, default: [:]][channel, default: []].append(action)
                }
            } else {
                tracks[action.targetLayerID, default: [:]][action.spec.kind.channel, default: []].append(action)
                if case .move(let m) = action.spec, m.turns { turningLayers.insert(action.targetLayerID) }
            }
            if let shutter = action.motionBlur, shutter > 0, !action.isInstant {
                var channels: Set<Channel>
                if case .preset(let p) = action.spec {
                    channels = p.unit == nil ? PresetRecipe.channels(p).intersection(Self.moving) : []
                } else {
                    channels = Self.moving.contains(action.spec.kind.channel) ? [action.spec.kind.channel] : []
                }
                // A Move that turns the layer along its path turns it too.
                if case .move(let m) = action.spec, m.turns { channels.insert(.rotation) }
                if !channels.isEmpty {
                    blurs[action.targetLayerID, default: []].append(
                        BlurRun(start: action.start, end: action.end, shutter: shutter, channels: channels))
                }
            }
        }
        // Only where there is a Show or Hide for them to answer to.
        for (layer, list) in entrances where tracks[layer]?[.visibility] != nil {
            tracks[layer]?[.visibility]?.append(contentsOf: list)
        }
        for (layer, channels) in tracks {
            for (channel, list) in channels {
                tracks[layer]?[channel] = list.sorted(by: Self.order)
            }
        }
        for (layer, list) in textPresets {
            textPresets[layer] = list.sorted { Self.order($0.action, $1.action) }
        }
    }

    /// How a text layer's letters, words or lines move at `time`: the text
    /// preset in force then (the latest to have started, or before any has,
    /// the first), or nil when the layer has none. Only one is in force at a
    /// time; each ends with every letter where it belongs and starts from
    /// there, so handing over shows nothing.
    public func textAnimation(of layer: UUID, at time: Double) -> TextAnimation? {
        guard !textPresets.isEmpty, let list = textPresets[layer], let first = list.first else { return nil }
        let visibility = tracks[layer]?[.visibility]
        guard let current = list.last(where: { $0.action.start <= time }) else {
            // Before the first, as it will start, unless a Show or Hide comes
            // first (rule 10).
            return Self.firstShowOrHide(visibility) <= first.action.start ? nil : TextAnimation(first)
        }
        // A Show after it has ended brings back letters it faded right out.
        let revives = visibility?.contains {
            if case .visibility(let v) = $0.spec { return v.isVisible && $0.start >= current.action.end && $0.start <= time }
            return false
        } ?? false
        return TextAnimation(current, revives: revives)
    }

    /// When a layer's first Show or Hide starts, or never.
    private static func firstShowOrHide(_ visibility: [Action]?) -> Double {
        visibility?.first { $0.spec.kind == .visibility }?.start ?? .infinity
    }

    /// The same, for a text layer only: anything else draws whole.
    func textAnimation(of layer: Layer, at time: Double) -> TextAnimation? {
        guard !textPresets.isEmpty, case .text = layer.content else { return nil }
        return textAnimation(of: layer.id, at: time)
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

    /// Whether no action reaches the layer, so it is as designed at every
    /// moment.
    func isStill(_ layer: UUID) -> Bool { tracks[layer] == nil && textPresets[layer] == nil }

    /// Whether any action has motion blur on, text presets included.
    public var hasMotionBlur: Bool {
        !blurs.isEmpty || textPresets.values.contains { $0.contains { ($0.action.motionBlur ?? 0) > 0 } }
    }

    /// The moving channels motion blur spreads on `layer` at `time`, and
    /// how long the shutter is open, in seconds, when a frame lasts `frame`:
    /// those of each action with motion blur whose run meets the shutter,
    /// open for half its time either side of `time`. Nil when none does.
    public func motionBlur(of layer: UUID, at time: Double, frame: Double) -> (channels: Set<Channel>, shutter: Double)? {
        guard let runs = blurs[layer] else { return nil }
        var channels: Set<Channel> = []
        var shutter = 0.0
        for run in runs {
            let open = run.shutter * frame
            guard run.start < time + open / 2, run.end > time - open / 2 else { continue }
            channels.formUnion(run.channels)
            shutter = max(shutter, open)
        }
        return channels.isEmpty || shutter <= 0 ? nil : (channels, shutter)
    }

    /// `layer` at `time`, with every action on it applied.
    public func state(of layer: Layer, at time: Double) -> LayerState {
        state(of: layer, at: time, including: nil)
    }

    /// What an action picks up from when it has no initial value of its own:
    /// the layer at the action's start, with only the actions before it on
    /// its channel applied. The inspector shows this as the placeholder for
    /// an empty starting value.
    public func inheritedState(for action: Action, of layer: Layer) -> LayerState {
        // A preset picks up the layer as it is when it starts, on every
        // property it reaches.
        if case .preset = action.spec { return state(of: layer, at: action.start) { $0.id != action.id } }
        let channel = action.spec.kind.channel
        let earlier = Set((tracks[layer.id]?[channel] ?? []).prefix { $0.id != action.id }.map(\.id))
        return state(of: layer, at: action.start) { $0.spec.kind.channel != channel || earlier.contains($0.id) }
    }

    /// `including` picks which actions count; nil is all of them, the way
    /// playback asks, which then copies no lists.
    private func state(of layer: Layer, at time: Double, including: ((Action) -> Bool)?) -> LayerState {
        var state = LayerState(design: layer)
        guard let channels = tracks[layer.id] else { return state }
        let presets = !presetParts.isEmpty && presetLayers.contains(layer.id)
        func steps<V>(_ actions: [Action], _ plain: (Action) -> Step<V>?, _ part: (PresetEffect) -> PartRun<V>?) -> [Step<V>] {
            presets ? self.steps(actions, plain, part) : actions.compactMap(plain)
        }
        // Show and Hide reach other channels (rule 10), when there are any.
        let visibility = channels[.visibility].map { all in including.map { all.filter($0) } ?? all }
        let holdsBefore = Self.firstShowOrHide(visibility)
        func walk<V>(_ design: V, _ steps: [Step<V>], at time: Double) -> V {
            MotionEvaluation.walk(design, steps, at: time, holdsBefore: holdsBefore)
        }
        // Only the channels the layer has actions on: every other one stays
        // as designed, which is what walking no actions gives. Most layers
        // have one or two of the two dozen.
        for (channel, all) in channels {
            let list = including.map { all.filter($0) } ?? all
            guard !list.isEmpty else { continue }
            switch channel {
            case .position: state.position = walk(state.position, steps(list, Self.positionStep, Self.positionPart), at: time)
            case .scale: state.scale = walk(state.scale, steps(list, Self.scaleStep, Self.scalePart), at: time)
            case .rotation: state.rotation = walk(state.rotation, steps(list, Self.rotationStep, Self.rotationPart), at: time)
            case .opacity:
                var run = steps(list, Self.opacityStep, Self.opacityPart)
                if let visibility { run = Self.withShows(run, visibility, design: layer.opacity) }
                state.opacity = walk(state.opacity, run, at: time)
            case .skew: state.skew = walk(state.skew, list.compactMap(Self.skewStep), at: time)
            case .tilt: state.tilt = walk(state.tilt, steps(list, Self.tiltStep, Self.tiltPart), at: time)
            case .reveal:
                state.reveal = Reveal(walk(state.reveal.box, steps(list, { _ in nil }, Self.revealPart), at: time))
            case .size: state.size = walk(state.size, list.compactMap(Self.sizeStep), at: time)
            case .visibility: state.isShown = MotionEvaluation.walk(1, Self.visibilitySteps(list), at: time) > 0.5
            // Only what the layer has: a Colour on a layer with no fill does nothing.
            case .fill: if let fill = state.fill { state.fill = walk(fill, list.compactMap(Self.fillStep), at: time) }
            case .stroke: if let stroke = state.stroke { state.stroke = walk(stroke, list.compactMap(Self.strokeStep), at: time) }
            case .trim: if let trim = state.trim { state.trim = walk(trim, list.compactMap(Self.trimStep), at: time) }
            case .cornerRadius:
                if let radii = state.cornerRadii { state.cornerRadii = walk(radii, list.compactMap(Self.cornerStep), at: time) }
            case .shadow: state.shadow = walk(state.shadow, list.compactMap(Self.shadowStep), at: time)
            case .layerBlur: state.layerBlur = walk(state.layerBlur, steps(list, Self.layerBlurStep, Self.layerBlurPart), at: time)
            case .backgroundBlur:
                state.backgroundBlur = walk(state.backgroundBlur, list.compactMap(Self.backgroundBlurStep), at: time)
            case .letterSpacing:
                if let spacing = state.letterSpacing { state.letterSpacing = walk(spacing, list.compactMap(Self.letterSpacingStep), at: time) }
            case .lineHeight:
                if let height = state.lineHeight { state.lineHeight = walk(height, list.compactMap(Self.lineHeightStep), at: time) }
            case .text:
                if let shown = state.text { state.text = Self.shownText(design: shown.text, list, at: time, holdsBefore: holdsBefore) }
            case .arc: if let arc = state.arc { state.arc = walk(arc, list.compactMap(Self.arcStep), at: time) }
            case .star: if let star = state.star { state.star = walk(star, list.compactMap(Self.starStep), at: time) }
            case .path: if let path = state.path { state.path = walk(path, list.compactMap(Self.pathStep), at: time) }
            case .volume:
                if let volume = state.volume { state.volume = walk(volume, steps(list, Self.volumeStep, Self.volumePart), at: time) }
            case .media: if state.sourceTime != nil { state.sourceTime = Self.sourceTime(list, at: time) }
            }
        }
        // Rule 9: a Move that turns along its path turns the layer on top of
        // whatever its rotation is doing.
        if !turningLayers.isEmpty, turningLayers.contains(layer.id), let all = channels[.position] {
            let list = including.map { all.filter($0) } ?? all
            state.rotation += pathTurn(of: layer, list, steps(list, Self.positionStep, Self.positionPart), at: time)
        }
        return state
    }

    /// How far the layer has turned by `time` following its turning Moves:
    /// for each, how much its path's direction has turned from its start to
    /// where the Move has got to, stopping where a later Move takes over.
    private func pathTurn(of layer: Layer, _ moves: [Action], _ steps: [Step<Vec2>], at time: Double) -> Double {
        let design = layer.transform.position
        var turn = 0.0
        for (i, action) in moves.enumerated() {
            guard case .move(let m) = action.spec, m.turns, let curve = m.curve, action.start <= time else { continue }
            // Where it starts and ends, as the channel has them.
            let from = walk(design, steps, at: action.start)
            let to = m.mode == .to ? m.end : from + m.end
            // It stops when the next Move on the channel starts (rule 6).
            let next = moves[(i + 1)...].first { $0.start >= action.start && $0.id != action.id }?.start ?? .infinity
            let until = min(time, next)
            let p = until >= action.end ? 1 : Self.progress(action, at: until)
            turn += Self.turning(from: from, to: to, curve: curve, upTo: p)
        }
        return turn
    }

    /// Degrees the direction along a curved path turns from its start to
    /// `p`, followed in small steps so a path that bends further than half a
    /// turn is counted whole.
    static func turning(from: Vec2, to: Vec2, curve: MotionCurve, upTo p: Double) -> Double {
        let a = from, b = from + curve.startHandle, c = to + curve.endHandle, d = to
        func direction(_ t: Double) -> Vec2? {
            // Kept off the very ends, where a handle of zero length leaves no direction.
            let t = min(max(t, 1e-4), max(p, 1) - 1e-4)
            let q = 1 - t
            let v = Vec2(3 * q * q * (b.x - a.x) + 6 * q * t * (c.x - b.x) + 3 * t * t * (d.x - c.x),
                         3 * q * q * (b.y - a.y) + 6 * q * t * (c.y - b.y) + 3 * t * t * (d.y - c.y))
            return abs(v.x) + abs(v.y) > 1e-9 ? v : nil
        }
        let samples = 24
        var total = 0.0
        var last = direction(0)
        for k in 1...samples {
            guard let now = direction(p * Double(k) / Double(samples)) else { continue }
            if let before = last {
                total += atan2(before.x * now.y - before.y * now.x, before.x * now.x + before.y * now.y)
            }
            last = now
        }
        return total * 180 / .pi
    }

    // MARK: Actions as steps

    /// A channel's steps: each action's, and each part a preset has there,
    /// in order of start (ties keep the actions' order).
    private func steps<V>(_ actions: [Action], _ plain: (Action) -> Step<V>?,
                          _ part: (PresetEffect) -> PartRun<V>?) -> [Step<V>] {
        var out: [Step<V>] = []
        var parted = false
        for action in actions {
            // Only presets are looked up: hashing every action's id on every
            // frame cost a tenth of evaluation.
            if case .preset = action.spec, let parts = presetParts[action.id] {
                for p in parts { if let run = part(p.effect) { out.append(Step(action, part: p, run: run)); parted = true } }
            } else if let step = plain(action) {
                out.append(step)
            }
        }
        guard parted else { return out }
        return out.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
    }

    // What each preset effect does on its channel, from the value when it
    // starts (`inherited`), the value when the preset first reached the
    // channel (`own`) and the design value.

    private static func positionPart(_ e: PresetEffect) -> PartRun<Vec2>? {
        guard case .move(let by, let entering) = e else { return nil }
        return PartRun(holds: entering) { inherited, own, _ in entering ? (own + by, own) : (inherited, inherited + by) }
    }

    private static func scalePart(_ e: PresetEffect) -> PartRun<Vec2>? {
        guard case .scale(let from, let to) = e else { return nil }
        return PartRun(holds: from != nil) { inherited, own, _ in
            (from.map { Vec2(own.x * $0, own.y * $0) } ?? inherited, Vec2(own.x * (to ?? 1), own.y * (to ?? 1)))
        }
    }

    private static func rotationPart(_ e: PresetEffect) -> PartRun<Double>? {
        guard case .rotate(let by, let entering) = e else { return nil }
        return PartRun(holds: entering) { inherited, own, _ in entering ? (own - by, own) : (inherited, inherited + by) }
    }

    private static func opacityPart(_ e: PresetEffect) -> PartRun<Double>? {
        guard case .opacity(let from, let to) = e else { return nil }
        // A layer faded right out has nothing of its own to come back to, so
        // it comes back to its design, or all the way.
        return PartRun(holds: from != nil) { inherited, own, design in
            (from ?? inherited, to ?? (own > 0.01 ? own : design > 0.01 ? design : 1))
        }
    }

    private static func layerBlurPart(_ e: PresetEffect) -> PartRun<Double>? {
        guard case .blur(let from, let to) = e else { return nil }
        return PartRun(holds: from != nil) { inherited, _, _ in (from ?? inherited, to) }
    }

    private static func tiltPart(_ e: PresetEffect) -> PartRun<Tilt>? {
        guard case .tilt(let by, let entering) = e else { return nil }
        func turned(_ t: Tilt, _ d: Double) -> Tilt { Tilt(x: t.x, y: t.y + d, depth: t.depth) }
        return PartRun(holds: entering) { inherited, own, _ in
            entering ? (turned(own, -by), own) : (inherited, turned(inherited, by))
        }
    }

    private static func revealPart(_ e: PresetEffect) -> PartRun<RevealBox>? {
        guard case .reveal(let from, let to) = e else { return nil }
        return PartRun(holds: from != nil) { inherited, _, _ in (from ?? inherited, to ?? .full) }
    }

    private static func volumePart(_ e: PresetEffect) -> PartRun<Double>? {
        guard case .volume(let from, let to) = e else { return nil }
        return PartRun(holds: from != nil) { inherited, own, design in
            (from ?? inherited, to ?? min(own > 0.01 ? own : design > 0.01 ? design : 1, 1))
        }
    }

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

    private static func skewStep(_ a: Action) -> Step<Vec2>? {
        guard case .skew(let k) = a.spec else { return nil }
        return Step(a, initial: k.initial, target: k.mode == .to ? { _ in k.end } : { $0 + k.end })
    }

    private static func tiltStep(_ a: Action) -> Step<Tilt>? {
        guard case .tilt(let t) = a.spec else { return nil }
        return Step(a, initial: t.initial,
                    target: t.mode == .to ? { _ in t.end } : { Tilt(x: $0.x + t.end.x, y: $0.y + t.end.y, depth: t.end.depth) })
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
    static func shownText(design: String, _ actions: [Action], at time: Double,
                          holdsBefore: Double = .infinity) -> ShownText {
        guard let first = actions.first else { return ShownText(text: design) }
        if time < first.start {
            if first.start < holdsBefore, case .counter(let c) = first.spec, let from = c.from {
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

    /// Visibility walks as 1 (shown) and 0 (hidden), every step instant. A
    /// layer is shown until something hides it: a Show never reaches back
    /// before its start (the user's choice on 28 September 2026), so to
    /// appear later a layer takes a Hide first or an In preset. An In preset
    /// shows the layer at its start, as a Show does.
    private static func visibilitySteps(_ actions: [Action]) -> [Step<Double>] {
        actions.compactMap { a in
            switch a.spec {
            case .visibility(let v):
                let end: Double = v.isVisible ? 1 : 0
                return Step(a, initial: nil, target: { _ in end })
            case .preset:
                var step = Step<Double>(a, initial: nil, target: { _ in 1 })
                step.isInstant = true
                return step
            default:
                return nil
            }
        }
    }

    /// The opacity channel's steps with a step for each Show among
    /// `visibility`, which brings back a layer faded right out (rule 10).
    /// A Show goes before anything starting with it.
    private static func withShows(_ steps: [Step<Double>], _ visibility: [Action], design: Double) -> [Step<Double>] {
        let back = design > 0.01 ? design : 1
        let shows = visibility.compactMap { a -> Step<Double>? in
            guard case .visibility(let v) = a.spec, v.isVisible else { return nil }
            return Step(a, revive: { $0 <= 0.01 ? back : nil })
        }
        guard !shows.isEmpty else { return steps }
        var out: [Step<Double>] = []
        out.reserveCapacity(steps.count + shows.count)
        var i = 0
        for show in shows {
            while i < steps.count, steps[i].start < show.start { out.append(steps[i]); i += 1 }
            out.append(show)
        }
        out.append(contentsOf: steps[i...])
        return out
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

    /// For a preset's part, how it works out its values; nil for any other
    /// step. Boxed, so ordinary steps stay small: a larger step made every
    /// frame's evaluation a third slower.
    var part: PartBox<V>?

    init(_ action: Action, initial: V?, target: @escaping (V) -> V, travel: ((V, V, Double) -> V)? = nil) {
        start = action.start
        duration = action.duration
        isInstant = action.isInstant
        easing = action.easing
        self.initial = initial
        self.target = target
        self.travel = travel
    }

    init(_ action: Action, part: PresetPart, run: PartRun<V>) {
        start = action.start + part.start * action.duration
        duration = part.duration * action.duration
        isInstant = duration <= 0
        easing = part.easing ?? action.easing
        initial = nil
        target = { $0 }
        self.part = PartBox(run: run, group: action.id)
    }

    /// A Show on the opacity channel (rule 10): `revive` gives the value it
    /// brings back, or nil to leave the channel as it is.
    init(_ show: Action, revive: @escaping (V) -> V?) {
        start = show.start
        duration = 0
        isInstant = true
        easing = show.easing
        initial = nil
        target = { $0 }
        part = PartBox(revive: revive)
    }

    /// What it shows before it starts, as the first step on its channel:
    /// an explicit starting value holds from the start of the scene.
    func before(_ design: V) -> V {
        if let run = part?.run { return run.holds ? run.resolve(design, design, design).from : design }
        return initial ?? design
    }
}

/// A preset part's run and the preset it belongs to, whose parts on one
/// channel share what the preset found there. A Show on the opacity
/// channel is boxed here too, as `revive`, to keep steps small.
final class PartBox<V> {
    let run: PartRun<V>
    let group: UUID
    let revive: ((V) -> V?)?

    init(run: PartRun<V>, group: UUID) {
        self.run = run
        self.group = group
        revive = nil
    }

    init(revive: @escaping (V) -> V?) {
        run = PartRun(holds: false) { inherited, _, _ in (inherited, inherited) }
        group = UUID()
        self.revive = revive
    }
}

/// A preset part's start and end on its channel, from the value it
/// inherits, the value its preset found there and the design value.
/// `holds` when it sets where it starts, as an explicit initial value does.
struct PartRun<V> {
    var holds: Bool
    var resolve: (_ inherited: V, _ own: V, _ design: V) -> (from: V, to: V)

    init(holds: Bool, _ resolve: @escaping (_ inherited: V, _ own: V, _ design: V) -> (from: V, to: V)) {
        self.holds = holds
        self.resolve = resolve
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
/// 8. A preset is one action whose parts are steps on the channels they
///    reach, each following these rules. Its values are measured from what
///    it finds on each channel when its first part there starts.
/// 9. The one exception to rule 6's last sentence: a curved Move set to turn
///    along its path adds to the layer's rotation how far its path's
///    direction has turned since the Move began, and keeps that turn after
///    it ends (`pathTurn`, applied after the walks).
/// 10. Show and Hide are kept whatever else the layer does, and never reach
///    back before their start: a layer is shown until something hides it.
///    A Show or Hide
///    at or before a channel's first action ends rule 4's exception there
///    (`holdsBefore` is when the first one starts): the channel stays as
///    designed until the action starts, so a layer shown at 1 s with a Fade
///    In at 3 s shows until 3 s, then fades in. A Show brings back a layer
///    faded right out, at its design opacity (or 100%, if that is 0%),
///    leaving where it is and how big alone; at any other opacity it leaves
///    the channel alone, so a fade running through it carries on. An In
///    preset shows its layer when it starts, as a Show does, so one after a
///    Hide plays.
func walk<V: Interpolatable>(_ design: V, _ steps: [Step<V>], at time: Double,
                             holdsBefore: Double = .infinity) -> V {
    guard let first = steps.first else { return design }
    if time < first.start {                                           // rules 1, 4 and 10
        return first.start < holdsBefore ? first.before(design) : design
    }

    var current: (step: Step<V>, from: V, to: V)?
    var found: [UUID: V] = [:]
    for step in steps {
        guard step.start <= time else { break }                      // rule 4: not started yet
        let inherited = current.map { value(of: $0, at: step.start) } ?? design
        if let revive = step.part?.revive {                           // rule 10
            if let back = revive(inherited) { current = (step, back, back) }
            continue
        }
        if let part = step.part {                                     // rule 8
            let own: V
            if let seen = found[part.group] { own = seen } else { own = inherited; found[part.group] = inherited }
            let (from, to) = part.run.resolve(inherited, own, design)
            current = (step, from, to)
            continue
        }
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
