import Foundation
import MotionModel
import MotionEvaluation

/// One-click animations, as Jitter has them: a preset goes on as one bar,
/// whose settings the inspector shows when it is selected (`PresetAction`).
/// What it does is its recipe (`PresetRecipe`, in MotionEvaluation), worked
/// out as it plays. It can be split into the ordinary actions it is made of
/// for finer control. Presets added before this were added as their
/// actions, and stay so.
public struct Preset: Sendable, Equatable, Identifiable {
    public let kind: PresetKind
    public let name: String
    public let category: PresetCategory

    public init(_ kind: PresetKind, _ name: String, _ category: PresetCategory) {
        self.kind = kind
        self.name = name
        self.category = category
    }

    public var id: String { kind.rawValue }
}

public enum PresetCategory: String, Codable, Sendable, CaseIterable {
    /// Bring a layer on.
    case entrance
    /// Take it off.
    case exit
    /// Draw the eye to it and leave it where it was.
    case emphasis
    /// Bring a sound in or take it out.
    case sound

    public var title: String {
        switch self {
        case .entrance: "Entrances"
        case .exit: "Exits"
        case .emphasis: "Emphasis"
        case .sound: "Sound"
        }
    }
}

/// A setting a preset shows in the inspector.
public enum PresetControl: Sendable, Hashable {
    case direction, distance, scale, angle, blur, fades
}

public enum Presets {
    public static let library: [Preset] = [
        Preset(.fadeIn, "Fade In", .entrance),
        Preset(.slideIn, "Slide In", .entrance),
        Preset(.scalePop, "Scale Pop", .entrance),
        Preset(.rotateIn, "Rotate In", .entrance),
        Preset(.blurIn, "Blur In", .entrance),
        Preset(.dropIn, "Drop In", .entrance),
        Preset(.fadeOut, "Fade Out", .exit),
        Preset(.slideOut, "Slide Out", .exit),
        Preset(.scaleOut, "Scale Out", .exit),
        Preset(.blurOut, "Blur Out", .exit),
        Preset(.fadeSoundIn, "Fade Sound In", .sound),
        Preset(.fadeSoundOut, "Fade Sound Out", .sound),
        Preset(.pulse, "Pulse", .emphasis),
        Preset(.bounce, "Bounce", .emphasis),
        Preset(.shake, "Shake", .emphasis),
        Preset(.wiggle, "Wiggle", .emphasis),
    ]

    public static func preset(_ kind: PresetKind) -> Preset {
        library.first { $0.kind == kind } ?? Preset(kind, kind.rawValue, .emphasis)
    }

    /// The settings the inspector shows for a preset, in order.
    public static func controls(for kind: PresetKind) -> [PresetControl] {
        switch kind {
        case .slideIn, .slideOut: [.direction, .distance, .fades]
        case .scalePop, .scaleOut: [.scale, .fades]
        case .rotateIn: [.angle, .scale, .fades]
        case .blurIn, .blurOut: [.blur, .fades]
        case .dropIn: [.distance, .fades]
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
               easing: PresetRecipe.easing(preset.kind), name: preset.name,
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
