import Foundation
import MotionModel
import MotionEvaluation

/// One-click animations. A preset is only a recipe: applying it adds
/// ordinary actions, each editable like any other, and leaves nothing of the
/// preset behind. Adding a preset is adding a value to `Presets.library`,
/// built from the effects below; no new code is needed unless it needs a
/// new kind of effect.
public struct Preset: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let category: PresetCategory
    public let steps: [PresetStep]

    public init(_ id: String, _ name: String, _ category: PresetCategory, _ steps: [PresetStep]) {
        self.id = id
        self.name = name
        self.category = category
        self.steps = steps
    }

    /// From the preset's start to the end of its last step.
    public var duration: Double { steps.map { $0.start + $0.duration }.max() ?? 0 }
}

public enum PresetCategory: String, Codable, Sendable, CaseIterable {
    /// Bring a layer on.
    case entrance
    /// Take it off.
    case exit
    /// Draw the eye to it and leave it where it was.
    case emphasis

    public var title: String {
        switch self {
        case .entrance: "Entrances"
        case .exit: "Exits"
        case .emphasis: "Emphasis"
        }
    }
}

/// One action of a preset: when it starts after the preset does, for how
/// long, with what easing, doing what.
public struct PresetStep: Codable, Sendable, Equatable {
    public var start: Double
    public var duration: Double
    public var easing: Easing
    public var effect: PresetEffect

    public init(_ effect: PresetEffect, at start: Double = 0, for duration: Double, easing: Easing = .default) {
        self.start = start
        self.duration = duration
        self.easing = easing
        self.effect = effect
    }
}

/// What a step does, measured from the layer as it is when the preset is
/// applied ("own"), so a preset suits a layer wherever and however big it is.
public enum PresetEffect: Codable, Sendable, Equatable {
    /// Opacity from `from` (nil carries on from wherever it is) to `to`
    /// (nil is the layer's own).
    case opacity(from: Double?, to: Double?)
    /// Moves by `by`, in pixels. Entering, it comes from `by` away and lands
    /// where the layer is; otherwise it leaves by that much.
    case move(by: Vec2, entering: Bool)
    /// Scale as a factor of the layer's own: from `from` (nil carries on) to
    /// `to` (nil is its own).
    case scale(from: Double?, to: Double?)
    /// Turns by `by` degrees, clockwise. Entering, it turns into its own
    /// angle from `by` short of it; otherwise it turns on by that much.
    case rotate(by: Double, entering: Bool)
    /// Layer blur, in Figma's pixels, from `from` (nil carries on) to `to`.
    case blur(from: Double?, to: Double)

    public var kind: ActionKind {
        switch self {
        case .opacity: .opacity
        case .move: .move
        case .scale: .scale
        case .rotate: .rotate
        case .blur: .layerBlur
        }
    }
}

public enum Presets {
    /// The presets that suit every one of `layers`: those whose every step
    /// is an action they can all take.
    public static func available(for layers: [Layer]) -> [Preset] {
        let kinds = Set(ActionFactory.kinds(for: layers))
        guard !kinds.isEmpty else { return [] }
        return library.filter { preset in preset.steps.allSatisfy { kinds.contains($0.effect.kind) } }
    }

    /// The actions `preset` makes on `layer`, starting at `time`. `state` is
    /// the layer at that moment. Times land on frames; `rowOrder` is left
    /// for the caller to set.
    public static func actions(_ preset: Preset, for layer: Layer, at time: Double, state: LayerState,
                               frameRate: FrameRate) -> [Action] {
        let begin = frameRate.snapped(max(time, 0))
        // A layer faded right out has nothing of its own to fade back to, so
        // it comes back to its design opacity, or all the way.
        let ownOpacity = state.opacity > 0.01 ? state.opacity : (layer.opacity > 0.01 ? layer.opacity : 1)
        return preset.steps.map { step in
            let spec: ActionSpec
            switch step.effect {
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
            }
            return Action(target: layer.id, start: frameRate.snapped(begin + step.start),
                          duration: max(frameRate.snapped(step.duration), frameRate.frameDuration),
                          easing: step.easing, spec: spec)
        }
    }

    // MARK: The library

    private static let travel = 160.0
    private static func fadeIn(_ length: Double) -> PresetStep { PresetStep(.opacity(from: 0, to: nil), for: length) }
    private static func fadeOut(_ length: Double) -> PresetStep { PresetStep(.opacity(from: nil, to: 0), for: length) }
    private static let slowDown = Easing.preset(.slowDown, intensity: 0.6)
    private static let accelerate = Easing.preset(.accelerate, intensity: 0.6)

    private static func slideIn(_ id: String, _ name: String, _ by: Vec2) -> Preset {
        Preset(id, name, .entrance, [PresetStep(.move(by: by, entering: true), for: 0.5, easing: slowDown), fadeIn(0.3)])
    }

    private static func slideOut(_ id: String, _ name: String, _ by: Vec2) -> Preset {
        Preset(id, name, .exit, [PresetStep(.move(by: by, entering: false), for: 0.5, easing: accelerate),
                                 PresetStep(.opacity(from: nil, to: 0), at: 0.2, for: 0.3)])
    }

    public static let library: [Preset] = [
        // Entrances
        Preset("fade-in", "Fade In", .entrance, [fadeIn(0.4)]),
        slideIn("slide-in-left", "Slide In from Left", Vec2(-travel, 0)),
        slideIn("slide-in-right", "Slide In from Right", Vec2(travel, 0)),
        slideIn("slide-in-top", "Slide In from Top", Vec2(0, -travel)),
        slideIn("slide-in-bottom", "Slide In from Bottom", Vec2(0, travel)),
        Preset("scale-pop", "Scale Pop", .entrance, [
            PresetStep(.scale(from: 0, to: nil), for: 0.5, easing: .preset(.overshoot, intensity: 0.6)), fadeIn(0.2),
        ]),
        Preset("rotate-in", "Rotate In", .entrance, [
            PresetStep(.rotate(by: 90, entering: true), for: 0.5, easing: slowDown),
            PresetStep(.scale(from: 0.6, to: nil), for: 0.5, easing: slowDown), fadeIn(0.3),
        ]),
        Preset("blur-in", "Blur In", .entrance, [PresetStep(.blur(from: 24, to: 0), for: 0.5, easing: slowDown), fadeIn(0.4)]),
        Preset("drop-in", "Drop In", .entrance, [
            PresetStep(.move(by: Vec2(0, -travel * 1.5), entering: true), for: 0.8, easing: .preset(.spring, intensity: 0.5)),
            fadeIn(0.2),
        ]),

        // Exits
        Preset("fade-out", "Fade Out", .exit, [fadeOut(0.4)]),
        slideOut("slide-out-left", "Slide Out to Left", Vec2(-travel, 0)),
        slideOut("slide-out-right", "Slide Out to Right", Vec2(travel, 0)),
        slideOut("slide-out-top", "Slide Out to Top", Vec2(0, -travel)),
        slideOut("slide-out-bottom", "Slide Out to Bottom", Vec2(0, travel)),
        Preset("scale-out", "Scale Out", .exit, [
            PresetStep(.scale(from: nil, to: 0), for: 0.4, easing: .preset(.accelerate, intensity: 0.5)),
            PresetStep(.opacity(from: nil, to: 0), at: 0.2, for: 0.2),
        ]),
        Preset("blur-out", "Blur Out", .exit, [PresetStep(.blur(from: nil, to: 24), for: 0.5, easing: accelerate), fadeOut(0.5)]),

        // Emphasis
        Preset("pulse", "Pulse", .emphasis, [
            PresetStep(.scale(from: nil, to: 1.12), for: 0.18),
            PresetStep(.scale(from: nil, to: 1), at: 0.18, for: 0.25),
        ]),
        Preset("bounce", "Bounce", .emphasis, [
            PresetStep(.move(by: Vec2(0, -40), entering: false), for: 0.2, easing: slowDown),
            PresetStep(.move(by: Vec2(0, 40), entering: false), at: 0.2, for: 0.5, easing: .preset(.spring, intensity: 0.5)),
        ]),
        Preset("shake", "Shake", .emphasis, [
            PresetStep(.move(by: Vec2(12, 0), entering: false), for: 0.06),
            PresetStep(.move(by: Vec2(-24, 0), entering: false), at: 0.06, for: 0.1),
            PresetStep(.move(by: Vec2(24, 0), entering: false), at: 0.16, for: 0.1),
            PresetStep(.move(by: Vec2(-12, 0), entering: false), at: 0.26, for: 0.08),
        ]),
        Preset("wiggle", "Wiggle", .emphasis, [
            PresetStep(.rotate(by: 8, entering: false), for: 0.08),
            PresetStep(.rotate(by: -16, entering: false), at: 0.08, for: 0.14),
            PresetStep(.rotate(by: 16, entering: false), at: 0.22, for: 0.14),
            PresetStep(.rotate(by: -8, entering: false), at: 0.36, for: 0.1),
        ]),
    ]
}
