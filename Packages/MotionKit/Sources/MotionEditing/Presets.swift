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
///
/// Every preset but the sound ones can move a text's letters, words or lines
/// one by one (`PresetAction.unit`, set in the inspector); the Text group's
/// presets are ones that go on that way, for text layers only.
public struct Preset: Sendable, Equatable, Identifiable {
    /// The kind a new bar takes: for a pair, the one that brings it on.
    public let kind: PresetKind
    public let name: String
    public let group: PresetGroup
    /// Only layers with sound take it.
    public let isSound: Bool
    /// A Text preset's letters, words or lines, order and delay, and any
    /// other setting it goes on with; nil for every other preset.
    public let text: PresetAction?
    /// A Text preset's bar length, longer than its recipe's own since the
    /// letters take turns in it.
    public let length: Double?

    public init(_ kind: PresetKind, _ name: String, _ group: PresetGroup, isSound: Bool = false,
                text: PresetAction? = nil, length: Double? = nil) {
        self.kind = kind
        self.name = name
        self.group = group
        self.isSound = isSound
        self.text = text
        self.length = length
    }

    public var isText: Bool { text != nil }

    public var id: String { isText ? "text-" + name.lowercased().replacingOccurrences(of: " ", with: "-") : kind.rawValue }
}

/// The headed groups the picker shows presets in, in order.
public enum PresetGroup: String, Sendable, CaseIterable {
    case fade, scale, mask, blur, emphasis, text, sound

    public var title: String {
        switch self {
        case .fade: "Fade"
        case .scale: "Scale"
        case .mask: "Mask"
        case .blur: "Blur"
        case .emphasis: "Emphasis"
        case .text: "Text"
        case .sound: "Sound"
        }
    }
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
        case .shrinkIn: .shrinkOut
        case .shrinkOut: .shrinkIn
        case .twistIn: .twistOut
        case .twistOut: .twistIn
        case .moveScaleIn: .moveScaleOut
        case .moveScaleOut: .moveScaleIn
        case .maskRevealIn: .maskRevealOut
        case .maskRevealOut: .maskRevealIn
        case .maskCenterIn: .maskCenterOut
        case .maskCenterOut: .maskCenterIn
        case .maskResizeIn: .maskResizeOut
        case .maskResizeOut: .maskResizeIn
        case .maskSlideIn: .maskSlideOut
        case .maskSlideOut: .maskSlideIn
        case .maskShrinkIn: .maskShrinkOut
        case .maskShrinkOut: .maskShrinkIn
        case .blurSlideIn: .blurSlideOut
        case .blurSlideOut: .blurSlideIn
        case .blurScaleIn: .blurScaleOut
        case .blurScaleOut: .blurScaleIn
        case .pulse, .bounce, .shake, .wiggle: nil
        }
    }
}

/// A setting a preset shows in the inspector.
public enum PresetControl: Sendable, Hashable {
    case direction, distance, scale, angle, blur, fades
}

public enum Presets {
    /// In the order the picker shows them, group by group. A pair is one
    /// preset.
    public static let library: [Preset] = [
        Preset(.fadeIn, "Fade", .fade),
        Preset(.slideIn, "Slide", .fade),
        Preset(.dropIn, "Drop", .fade),
        Preset(.scalePop, "Grow", .scale),
        Preset(.shrinkIn, "Shrink", .scale),
        Preset(.rotateIn, "Spin", .scale),
        Preset(.twistIn, "Twist", .scale),
        Preset(.moveScaleIn, "Move & Scale", .scale),
        Preset(.maskRevealIn, "Mask Reveal", .mask),
        Preset(.maskCenterIn, "Mask Center", .mask),
        Preset(.maskResizeIn, "Mask Resize", .mask),
        Preset(.maskSlideIn, "Mask & Slide", .mask),
        Preset(.maskShrinkIn, "Mask Shrink", .mask),
        Preset(.blurIn, "Blur", .blur),
        Preset(.blurSlideIn, "Blur & Slide", .blur),
        Preset(.blurScaleIn, "Blur & Scale", .blur),
        Preset(.pulse, "Pulse", .emphasis),
        Preset(.bounce, "Bounce", .emphasis),
        Preset(.shake, "Shake", .emphasis),
        Preset(.wiggle, "Wiggle", .emphasis),
        Preset(.fadeIn, "Typewriter", .text, text: PresetAction(preset: .fadeIn, unit: .letters, delay: 0.05), length: 1),
        Preset(.slideIn, "Letters Rise", .text,
               text: PresetAction(preset: .slideIn, direction: .bottom, unit: .letters, delay: 0.03), length: 0.8),
        Preset(.scalePop, "Letters Pop", .text, text: PresetAction(preset: .scalePop, unit: .letters, delay: 0.03), length: 0.8),
        Preset(.blurIn, "Words Blur", .text, text: PresetAction(preset: .blurIn, unit: .words, delay: 0.1), length: 0.9),
        Preset(.maskRevealIn, "Lines Reveal", .text, text: PresetAction(preset: .maskRevealIn, unit: .lines, delay: 0.12),
               length: 0.9),
        Preset(.fadeSoundIn, "Sound Fade", .sound, isSound: true),
    ]

    /// A preset of exactly `kind`, named for which way it goes.
    public static func preset(_ kind: PresetKind) -> Preset {
        let group = library.first { !$0.isText && ($0.kind == kind || $0.kind == kind.reversed) }?.group ?? .emphasis
        return Preset(kind, name(of: kind), group, isSound: kind.isSound)
    }

    /// What a bar of `kind` is called: the pair's name and which way, as
    /// Fade In or Fade Out, or the preset's own name.
    public static func name(of kind: PresetKind) -> String {
        let base = library.first { !$0.isText && ($0.kind == kind || $0.kind == kind.reversed) }?.name ?? kind.rawValue
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
        case .shrinkIn, .shrinkOut: [.scale, .fades]
        case .twistIn, .twistOut: [.angle, .fades]
        case .moveScaleIn, .moveScaleOut: [.direction, .distance, .scale, .fades]
        case .maskRevealIn, .maskRevealOut, .maskResizeIn, .maskResizeOut: [.direction]
        case .maskSlideIn, .maskSlideOut: [.direction, .distance]
        case .maskShrinkIn, .maskShrinkOut: [.scale]
        case .maskCenterIn, .maskCenterOut: []
        case .blurSlideIn, .blurSlideOut: [.direction, .distance, .blur, .fades]
        case .blurScaleIn, .blurScaleOut: [.scale, .blur, .fades]
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
    /// Text presets only suit text.
    public static func available(for layers: [Layer], in project: Project) -> [Preset] {
        let kinds = Set(ActionFactory.kinds(for: layers, in: project))
        guard !kinds.isEmpty else { return [] }
        let allText = layers.allSatisfy(\.isText)
        return library.filter { preset in (!preset.isText || allText) && needs(preset.kind).isSubset(of: kinds) }
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
            case .tilt: .tilt
            // A reveal clips whatever draws, as opacity fades it.
            default: .opacity
            }
        })
    }

    /// The preset as one bar on `layer`, starting at `time`, at its own
    /// length and easing, named after it. `rowOrder` is left for the caller.
    /// A Text preset takes its letters, words or lines and the rest of its
    /// settings, and travels one type size, as the letters are that big.
    public static func action(_ preset: Preset, for layer: Layer, at time: Double, frameRate: FrameRate) -> Action {
        var settings = PresetRecipe.defaults(preset.kind)
        if let text = preset.text {
            settings.unit = text.unit
            settings.order = text.order
            settings.delay = text.delay
            if let direction = text.direction { settings.direction = direction }
            settings.distance = unitDistance(settings, of: layer)
        }
        return Action(target: layer.id, start: frameRate.snapped(max(time, 0)),
                      duration: max(frameRate.snapped(preset.length ?? PresetRecipe.length(preset.kind)), frameRate.frameDuration),
                      easing: PresetRecipe.easing(preset.kind), name: preset.isText ? preset.name : name(of: preset.kind),
                      spec: .preset(settings))
    }

    /// How far a preset set to move `layer`'s letters, words or lines one by
    /// one travels: its type size, when the preset travels at all.
    public static func unitDistance(_ settings: PresetAction, of layer: Layer) -> Double? {
        guard settings.distance != nil, case .text(let text) = layer.content else { return settings.distance }
        return settings.unit == nil ? PresetRecipe.defaults(settings.preset).distance : text.fontSize.rounded()
    }

    /// Whether a bar can be split into ordinary actions: not when it moves a
    /// text's letters one by one, or clips the layer, which no action does.
    public static func splits(_ settings: PresetAction) -> Bool {
        settings.unit == nil && !PresetRecipe.channels(settings).contains(.reveal)
    }

    /// A preset bar as the ordinary actions it is made of, for editing one
    /// by one: the same motion, with its values fixed from `state`, the
    /// layer as the bar found it (`ActionTracks.inheritedState`), and its
    /// design for what a layer faded right out comes back to. They take the
    /// bar's row, and nil for anything that is not a preset.
    public static func split(_ action: Action, of layer: Layer, from state: LayerState, frameRate: FrameRate) -> [Action]? {
        guard case .preset(let settings) = action.spec, splits(settings) else { return nil }
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
            case .tilt(let by, let entering):
                let own = state.tilt
                spec = entering
                    ? .tilt(TiltAction(mode: .to, initial: Tilt(x: own.x, y: own.y - by, depth: own.depth), end: own))
                    : .tilt(TiltAction(mode: .by, end: Tilt(x: 0, y: by, depth: own.depth)))
            case .reveal:
                // Never reached: `splits` turns away any preset that clips.
                spec = .opacity(OpacityAction(end: ownOpacity))
            }
            let start = frameRate.snapped(action.start + part.start * action.duration)
            let end = frameRate.snapped(action.start + (part.start + part.duration) * action.duration)
            return Action(target: action.targetLayerID, start: start, duration: max(end - start, 0),
                          easing: part.easing ?? action.easing, isEnabled: action.isEnabled,
                          rowOrder: action.rowOrder, spec: spec)
        }
    }
}
