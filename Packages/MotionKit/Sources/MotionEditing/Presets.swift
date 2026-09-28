import Foundation
import MotionModel
import MotionEvaluation

/// One-click animations, as Jitter has them: a preset goes on as one bar,
/// whose settings the inspector shows when it is selected (`PresetAction`).
/// What it does is its recipe (`PresetRecipe`, in MotionEvaluation), worked
/// out as it plays. It can be split into the ordinary actions it is made of
/// for finer control. Presets added before this were added as their
/// actions, and stay so.
///
/// A preset that brings a layer on has a twin that takes it off (Fade In and
/// Fade Out); the library lists the pair once, by its short name, and the
/// inspector turns a bar from one to the other.
public struct Preset: Sendable, Equatable, Identifiable {
    /// The kind a new bar takes: for a pair, the one that brings it on.
    public let kind: PresetKind
    public let name: String
    /// Only layers with sound take it.
    public let isSound: Bool

    public init(_ kind: PresetKind, _ name: String, isSound: Bool = false) {
        self.kind = kind
        self.name = name
        self.isSound = isSound
    }

    public var id: String { kind.rawValue }
}

extension PresetKind {
    /// The same preset the other way round, for those that bring a layer on
    /// or take it off; nil for the rest.
    public var reversed: PresetKind? {
        switch self {
        case .fadeIn: .fadeOut
        case .fadeOut: .fadeIn
        case .slideIn: .slideOut
        case .slideOut: .slideIn
        case .scalePop: .scaleOut
        case .scaleOut: .scalePop
        case .rotateIn: .rotateOut
        case .rotateOut: .rotateIn
        case .blurIn: .blurOut
        case .blurOut: .blurIn
        case .dropIn: .dropOut
        case .dropOut: .dropIn
        case .fadeSoundIn: .fadeSoundOut
        case .fadeSoundOut: .fadeSoundIn
        case .pulse, .bounce, .shake, .wiggle: nil
        }
    }

    /// True for one that brings a layer (or a sound) on, false for one that
    /// takes it off, nil for one that leaves it where it was.
    public var entering: Bool? {
        switch self {
        case .fadeIn, .slideIn, .scalePop, .rotateIn, .blurIn, .dropIn, .fadeSoundIn: true
        case .fadeOut, .slideOut, .scaleOut, .rotateOut, .blurOut, .dropOut, .fadeSoundOut: false
        case .pulse, .bounce, .shake, .wiggle: nil
        }
    }

    public var isSound: Bool { self == .fadeSoundIn || self == .fadeSoundOut }
}

/// A setting a preset shows in the inspector.
public enum PresetControl: Sendable, Hashable {
    case direction, distance, scale, angle, blur, fades
}

public enum Presets {
    /// In the order the picker shows them. No groups: a pair is one preset.
    public static let library: [Preset] = [
        Preset(.fadeIn, "Fade"),
        Preset(.slideIn, "Slide"),
        Preset(.scalePop, "Scale"),
        Preset(.rotateIn, "Rotate"),
        Preset(.blurIn, "Blur"),
        Preset(.dropIn, "Drop"),
        Preset(.pulse, "Pulse"),
        Preset(.bounce, "Bounce"),
        Preset(.shake, "Shake"),
        Preset(.wiggle, "Wiggle"),
        Preset(.fadeSoundIn, "Sound Fade", isSound: true),
    ]

    /// A preset of exactly `kind`, named for which way it goes.
    public static func preset(_ kind: PresetKind) -> Preset {
        Preset(kind, name(of: kind), isSound: kind.isSound)
    }

    /// What a bar of `kind` is called: the pair's name and which way, as
    /// Fade In or Fade Out, or the preset's own name.
    public static func name(of kind: PresetKind) -> String {
        let base = library.first { $0.kind == kind || $0.kind == kind.reversed }?.name ?? kind.rawValue
        switch kind.entering {
        case true?: return base + " In"
        case false?: return base + " Out"
        case nil: return base
        }
    }

    /// The settings the inspector shows for a preset, in order.
    public static func controls(for kind: PresetKind) -> [PresetControl] {
        switch kind {
        case .slideIn, .slideOut: [.direction, .distance, .fades]
        case .scalePop, .scaleOut: [.scale, .fades]
        case .rotateIn, .rotateOut: [.angle, .scale, .fades]
        case .blurIn, .blurOut: [.blur, .fades]
        case .dropIn, .dropOut: [.distance, .fades]
        case .pulse: [.scale]
        case .bounce, .shake: [.distance]
        case .wiggle: [.angle]
        case .fadeIn, .fadeOut, .fadeSoundIn, .fadeSoundOut: []
        }
    }

    /// The presets that suit every one of `layers`: those whose every part
    /// is something they can all take. Sound presets only suit layers with
    /// sound, which only `project` knows for a video.
    public static func available(for layers: [Layer], in project: Project) -> [Preset] {
        let kinds = Set(ActionFactory.kinds(for: layers, in: project))
        guard !kinds.isEmpty else { return [] }
        return library.filter { preset in needs(preset.kind).isSubset(of: kinds) }
    }

    /// The actions a layer must be able to take for the preset to suit it.
    static func needs(_ kind: PresetKind) -> Set<ActionKind> {
        Set(PresetRecipe.channels(PresetRecipe.defaults(kind)).map { channel -> ActionKind in
            switch channel {
            case .position: .move
            case .scale: .scale
            case .rotation: .rotate
            case .layerBlur: .layerBlur
            case .volume: .volume
            default: .opacity
            }
        })
    }

    /// The preset as one bar on `layer`, starting at `time`, at its own
    /// length and easing, named after it. `rowOrder` is left for the caller.
    public static func action(_ preset: Preset, for layer: Layer, at time: Double, frameRate: FrameRate) -> Action {
        Action(target: layer.id, start: frameRate.snapped(max(time, 0)),
               duration: max(frameRate.snapped(PresetRecipe.length(preset.kind)), frameRate.frameDuration),
               easing: PresetRecipe.easing(preset.kind), name: name(of: preset.kind),
               spec: .preset(PresetRecipe.defaults(preset.kind)))
    }

    /// A preset bar as the ordinary actions it is made of, for editing one
    /// by one: the same motion, with its values fixed from `state`, the
    /// layer as the bar found it (`ActionTracks.inheritedState`), and its
    /// design for what a layer faded right out comes back to. They take the
    /// bar's row, and nil for anything that is not a preset.
    public static func split(_ action: Action, of layer: Layer, from state: LayerState, frameRate: FrameRate) -> [Action]? {
        guard case .preset(let settings) = action.spec else { return nil }
        let design = LayerState(design: layer)
        func own(_ value: Double, _ designed: Double) -> Double { value > 0.01 ? value : designed > 0.01 ? designed : 1 }
        let ownOpacity = own(state.opacity, design.opacity)
        let ownVolume = min(own(state.volume ?? 1, design.volume ?? 1), 1)
        return PresetRecipe.parts(settings).map { part in
            let spec: ActionSpec
            switch part.effect {
            case .opacity(let from, let to):
                spec = .opacity(OpacityAction(initial: from, end: to ?? ownOpacity))
            case .move(let by, let entering):
                spec = entering
                    ? .move(MoveAction(mode: .by, initial: state.position + by, end: Vec2(-by.x, -by.y)))
                    : .move(MoveAction(mode: .by, end: by))
            case .scale(let from, let to):
                let own = state.scale
                func times(_ f: Double) -> Vec2 { Vec2(own.x * f, own.y * f) }
                spec = .scale(ScaleAction(mode: .to, initial: from.map(times), end: times(to ?? 1)))
            case .rotate(let by, let entering):
                spec = entering
                    ? .rotate(RotateAction(mode: .to, initial: state.rotation - by, end: state.rotation))
                    : .rotate(RotateAction(mode: .by, end: by))
            case .blur(let from, let to):
                spec = .layerBlur(LayerBlurAction(initial: from, end: to))
            case .volume(let from, let to):
                spec = .volume(VolumeAction(initial: from, end: to ?? ownVolume))
            }
            let start = frameRate.snapped(action.start + part.start * action.duration)
            let end = frameRate.snapped(action.start + (part.start + part.duration) * action.duration)
            return Action(target: action.targetLayerID, start: start, duration: max(end - start, 0),
                          easing: part.easing ?? action.easing, isEnabled: action.isEnabled,
                          rowOrder: action.rowOrder, spec: spec)
        }
    }
}
