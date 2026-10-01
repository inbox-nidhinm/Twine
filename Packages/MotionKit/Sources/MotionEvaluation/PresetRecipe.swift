import Foundation
import MotionModel

/// What one part of a preset does to the layer. Values are measured from
/// the layer as it is when the preset starts on that property (its "own"),
/// so a preset suits a layer wherever it is and however big.
public enum PresetEffect: Sendable, Equatable {
    /// Opacity from `from` (nil carries on from wherever it is) to `to`
    /// (nil is the layer's own).
    case opacity(from: Double?, to: Double?)
    /// Moves by `by`, in pixels. Entering, it comes from `by` away and lands
    /// where the layer was; otherwise it goes on by that much.
    case move(by: Vec2, entering: Bool)
    /// Scale as a factor of the layer's own: from `from` (nil carries on) to
    /// `to` (nil is its own).
    case scale(from: Double?, to: Double?)
    /// Turns by `by` degrees, clockwise. Entering, it turns into its own
    /// angle from `by` short of it; otherwise it turns on by that much.
    case rotate(by: Double, entering: Bool)
    /// Layer blur, in Figma's pixels, from `from` (nil carries on) to `to`.
    case blur(from: Double?, to: Double)
    /// Volume from `from` (nil carries on) to `to` (nil is the layer's own
    /// level, at most 100%).
    case volume(from: Double?, to: Double?)
    /// Turns in depth around an upright line by `by` degrees (a tilt's y).
    /// Entering, it turns into its own tilt from `by` short of it;
    /// otherwise it turns on by that much.
    case tilt(by: Double, entering: Bool)
    /// Turns in depth on the `hinge` edge, like a page on its spine, by
    /// `by` degrees. Going, the free edge lifts towards the viewer until it
    /// has turned by that much; entering, it comes down into its own tilt
    /// from as far round the other side, so an Out on one layer and an In
    /// on the next turn the same way, as the onboarding's pages do.
    case turnPage(hinge: PresetDirection, by: Double, entering: Bool)
    /// A clip of the layer's own box, from `from` (nil carries on) to `to`
    /// (nil is the whole box, nothing clipped).
    case reveal(from: RevealBox?, to: RevealBox?)
    /// A page curl from `corner`, from `from` to `to` (0 flat, 1 curled off).
    case curl(corner: PresetCorner, from: Double, to: Double)

    public var channel: Channel {
        switch self {
        case .opacity: .opacity
        case .move: .position
        case .scale: .scale
        case .rotate: .rotation
        case .blur: .layerBlur
        case .volume: .volume
        case .tilt, .turnPage: .tilt
        case .reveal: .reveal
        case .curl: .curl
        }
    }

    /// Whether it sets where the property starts, so that, as the first
    /// thing on its property, it holds that from the start of the scene: an
    /// entrance keeps the layer away until it comes on.
    var setsStart: Bool {
        switch self {
        case .opacity(let from, _), .scale(let from, _), .volume(let from, _): from != nil
        case .blur(let from, _): from != nil
        case .reveal(let from, _): from != nil
        case .curl(_, let from, _): from > 0
        case .move(_, let entering), .rotate(_, let entering), .tilt(_, let entering), .turnPage(_, _, let entering): entering
        }
    }
}

/// One part of a preset, timed as fractions of its bar, so stretching the
/// bar stretches every part together.
public struct PresetPart: Sendable, Equatable {
    public var effect: PresetEffect
    public var start: Double
    public var duration: Double
    /// Nil follows the bar's own easing; a part that keeps its own (a fade
    /// alongside a slide) says which.
    public var easing: Easing?
}

/// Every preset's recipe: its parts, with its settings applied, and the
/// defaults its settings start at.
public enum PresetRecipe {
    /// How far slides travel unless set otherwise.
    public static let travel = 160.0

    /// The settings a new bar starts with, every one the preset uses filled.
    public static func defaults(_ kind: PresetKind) -> PresetAction {
        switch kind {
        case .slideIn: PresetAction(preset: kind, direction: .left, distance: travel, fades: true)
        case .slideOut: PresetAction(preset: kind, direction: .right, distance: travel, fades: true)
        case .scalePop: PresetAction(preset: kind, scale: 0, fades: true)
        case .scaleOut: PresetAction(preset: kind, scale: 0, fades: true)
        case .rotateIn, .rotateOut: PresetAction(preset: kind, scale: 0.6, angle: 180, fades: true)
        case .shrinkIn, .shrinkOut: PresetAction(preset: kind, scale: 1.5, fades: true)
        case .twistIn, .twistOut: PresetAction(preset: kind, angle: 90, fades: true)
        case .moveScaleIn: PresetAction(preset: kind, direction: .bottom, distance: travel / 2, scale: 0.5, fades: true)
        case .moveScaleOut: PresetAction(preset: kind, direction: .top, distance: travel / 2, scale: 0.5, fades: true)
        case .maskRevealIn: PresetAction(preset: kind, direction: .bottom)
        case .maskRevealOut: PresetAction(preset: kind, direction: .top)
        case .maskResizeIn: PresetAction(preset: kind, direction: .left)
        case .maskResizeOut: PresetAction(preset: kind, direction: .right)
        case .maskSlideIn: PresetAction(preset: kind, direction: .left, distance: travel / 2)
        case .maskSlideOut: PresetAction(preset: kind, direction: .right, distance: travel / 2)
        case .maskShrinkIn, .maskShrinkOut: PresetAction(preset: kind, scale: 1.4)
        case .maskCenterIn, .maskCenterOut: PresetAction(preset: kind)
        case .pageTurnIn, .pageTurnOut: PresetAction(preset: kind, direction: .left)
        case .pageCurlIn, .pageCurlOut: PresetAction(preset: kind, corner: .topRight)
        case .blurSlideIn: PresetAction(preset: kind, direction: .bottom, distance: travel / 3, blur: 16, fades: true)
        case .blurSlideOut: PresetAction(preset: kind, direction: .top, distance: travel / 3, blur: 16, fades: true)
        case .blurScaleIn, .blurScaleOut: PresetAction(preset: kind, scale: 0.6, blur: 16, fades: true)
        case .blurIn, .blurOut: PresetAction(preset: kind, blur: 24, fades: true)
        case .dropIn, .dropOut: PresetAction(preset: kind, distance: travel * 1.5, fades: true)
        case .pulse: PresetAction(preset: kind, scale: 1.12)
        case .bounce: PresetAction(preset: kind, distance: 40)
        case .shake: PresetAction(preset: kind, distance: 12)
        case .wiggle: PresetAction(preset: kind, angle: 8)
        case .fadeIn, .fadeOut, .fadeSoundIn, .fadeSoundOut, .typewriterIn, .typewriterOut: PresetAction(preset: kind)
        }
    }

    /// Its own length, in seconds, which a new bar takes.
    public static func length(_ kind: PresetKind) -> Double {
        seconds(kind).length
    }

    /// The easing a new bar takes: that of its main motion.
    public static func easing(_ kind: PresetKind) -> Easing {
        switch kind {
        case .slideIn, .rotateIn, .blurIn, .shrinkIn, .twistIn, .moveScaleIn, .blurSlideIn, .blurScaleIn,
             .maskRevealIn, .maskCenterIn, .maskResizeIn, .maskSlideIn, .maskShrinkIn, .pageTurnIn: slowDown
        case .slideOut, .blurOut, .rotateOut, .dropOut, .shrinkOut, .twistOut, .moveScaleOut, .blurSlideOut, .blurScaleOut,
             .maskRevealOut, .maskCenterOut, .maskResizeOut, .maskSlideOut, .maskShrinkOut, .pageTurnOut: accelerate
        case .scalePop: .preset(.overshoot, intensity: 0.6)
        case .scaleOut: .preset(.accelerate, intensity: 0.5)
        case .dropIn: .preset(.spring, intensity: 0.5)
        // Flip's own ease in and out (SwiftUI's), gentler than Natural, so
        // the corner is seen lifting.
        case .pageCurlIn, .pageCurlOut: .custom(CubicBezier(0.42, 0, 0.58, 1))
        default: .default
        }
    }

    /// Whether the bar's easing shapes it. A shake or a wiggle keeps the
    /// easing of each of its jolts, so the inspector offers none.
    public static func usesEasing(_ kind: PresetKind) -> Bool {
        seconds(kind).parts.contains { $0.easing == nil }
    }

    /// Whether every part happens at once: each letter of a text then
    /// appears in its turn rather than playing across a share of the bar,
    /// so the turns are spread over the whole bar (`TextAnimation`).
    public static func isInstant(_ kind: PresetKind) -> Bool {
        seconds(kind).parts.allSatisfy { $0.duration <= 0 }
    }

    /// The parts, as fractions of the bar.
    public static func parts(_ action: PresetAction) -> [PresetPart] {
        let (length, parts) = seconds(action.preset, action)
        guard length > 0 else { return parts }
        return parts.map { PresetPart(effect: $0.effect, start: $0.start / length, duration: $0.duration / length,
                                      easing: $0.easing) }
    }

    /// The properties it changes.
    public static func channels(_ action: PresetAction) -> Set<Channel> {
        Set(parts(action).map(\.effect.channel))
    }

    // MARK: The recipes, in seconds at their own length

    private static let slowDown = Easing.preset(.slowDown, intensity: 0.6)

    private static func opposite(_ d: PresetDirection) -> PresetDirection {
        switch d {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }
    private static let accelerate = Easing.preset(.accelerate, intensity: 0.6)

    private static func seconds(_ kind: PresetKind, _ settings: PresetAction? = nil) -> (length: Double, parts: [PresetPart]) {
        let own = defaults(kind)
        let s = settings ?? own
        let distance = s.distance ?? own.distance ?? travel
        let fades = s.fades ?? own.fades ?? true
        func part(_ effect: PresetEffect, at start: Double = 0, for duration: Double, easing: Easing? = nil) -> PresetPart {
            PresetPart(effect: effect, start: start, duration: duration, easing: easing)
        }
        func fadeIn(_ length: Double) -> [PresetPart] {
            fades ? [part(.opacity(from: 0, to: nil), for: length, easing: .default)] : []
        }
        func fadeOut(at start: Double = 0, _ length: Double) -> [PresetPart] {
            fades ? [part(.opacity(from: nil, to: 0), at: start, for: length, easing: .default)] : []
        }
        let direction = s.direction ?? own.direction ?? .left
        let scale = s.scale ?? own.scale ?? 1
        let angle = s.angle ?? own.angle ?? 90
        let blur = s.blur ?? own.blur ?? 24
        func toward(_ direction: PresetDirection?) -> Vec2 {
            switch direction ?? own.direction ?? .left {
            case .left: Vec2(-distance, 0)
            case .right: Vec2(distance, 0)
            case .top: Vec2(0, -distance)
            case .bottom: Vec2(0, distance)
            }
        }
        switch kind {
        case .fadeIn:
            return (0.4, [part(.opacity(from: 0, to: nil), for: 0.4)])
        // Straight on or off, no fade: the timing is all in the letters'
        // turns. An easing of its own, as there is nothing for the bar's to
        // shape.
        case .typewriterIn:
            return (1, [part(.opacity(from: 0, to: nil), for: 0, easing: .default)])
        case .typewriterOut:
            return (1, [part(.opacity(from: nil, to: 0), for: 0, easing: .default)])
        case .fadeOut:
            return (0.4, [part(.opacity(from: nil, to: 0), for: 0.4)])
        case .slideIn:
            return (0.5, [part(.move(by: toward(s.direction), entering: true), for: 0.5)] + fadeIn(0.3))
        case .slideOut:
            return (0.5, [part(.move(by: toward(s.direction), entering: false), for: 0.5)] + fadeOut(at: 0.2, 0.3))
        case .scalePop:
            return (0.5, [part(.scale(from: s.scale ?? own.scale, to: nil), for: 0.5)] + fadeIn(0.2))
        case .scaleOut:
            return (0.4, [part(.scale(from: nil, to: s.scale ?? own.scale), for: 0.4)] + fadeOut(at: 0.2, 0.2))
        case .rotateIn:
            return (0.5, [part(.rotate(by: s.angle ?? own.angle ?? 90, entering: true), for: 0.5),
                          part(.scale(from: s.scale ?? own.scale, to: nil), for: 0.5)] + fadeIn(0.3))
        case .rotateOut:
            return (0.5, [part(.rotate(by: s.angle ?? own.angle ?? 90, entering: false), for: 0.5),
                          part(.scale(from: nil, to: s.scale ?? own.scale), for: 0.5)] + fadeOut(at: 0.2, 0.3))
        case .blurIn:
            return (0.5, [part(.blur(from: s.blur ?? own.blur, to: 0), for: 0.5)] + fadeIn(0.4))
        case .blurOut:
            return (0.5, [part(.blur(from: nil, to: s.blur ?? own.blur ?? 24), for: 0.5)] + fadeOut(0.5))
        case .dropIn:
            return (0.8, [part(.move(by: Vec2(0, -distance), entering: true), for: 0.8)] + fadeIn(0.2))
        case .dropOut:
            return (0.5, [part(.move(by: Vec2(0, distance), entering: false), for: 0.5)] + fadeOut(at: 0.3, 0.2))
        case .shrinkIn:
            return (0.5, [part(.scale(from: scale, to: nil), for: 0.5)] + fadeIn(0.3))
        case .shrinkOut:
            return (0.4, [part(.scale(from: nil, to: scale), for: 0.4)] + fadeOut(at: 0.1, 0.3))
        case .twistIn:
            return (0.6, [part(.tilt(by: angle, entering: true), for: 0.6)] + fadeIn(0.3))
        case .twistOut:
            return (0.5, [part(.tilt(by: angle, entering: false), for: 0.5)] + fadeOut(at: 0.2, 0.3))
        // Edge-on at the far end, so nothing shows there and nothing fades.
        case .pageTurnIn:
            return (0.5, [part(.turnPage(hinge: direction, by: 90, entering: true), for: 0.5)])
        case .pageTurnOut:
            return (0.5, [part(.turnPage(hinge: direction, by: 90, entering: false), for: 0.5)])
        // Flip's own: the leaf lifts from a corner, curls over and is gone.
        case .pageCurlIn:
            return (0.5, [part(.curl(corner: s.corner ?? own.corner ?? .topRight, from: 1, to: 0), for: 0.5)])
        case .pageCurlOut:
            return (0.5, [part(.curl(corner: s.corner ?? own.corner ?? .topRight, from: 0, to: 1), for: 0.5)])
        case .moveScaleIn:
            return (0.6, [part(.move(by: toward(s.direction), entering: true), for: 0.6),
                          part(.scale(from: scale, to: nil), for: 0.6)] + fadeIn(0.3))
        case .moveScaleOut:
            return (0.5, [part(.move(by: toward(s.direction), entering: false), for: 0.5),
                          part(.scale(from: nil, to: scale), for: 0.5)] + fadeOut(at: 0.2, 0.3))
        // The Mask presets clip the layer to its own box. Reveal slides the
        // content in behind it; Center opens it from the middle; Resize opens
        // it from one side; Slide opens it from the side the layer is
        // heading for while the layer slides that way, as through a slot;
        // Shrink opens it from the centre as the content shrinks into place.
        case .maskRevealIn:
            return (0.6, [part(.reveal(from: .away(direction), to: nil), for: 0.6)])
        case .maskRevealOut:
            return (0.5, [part(.reveal(from: nil, to: .away(direction)), for: 0.5)])
        case .maskCenterIn:
            return (0.6, [part(.reveal(from: .middle, to: nil), for: 0.6)])
        case .maskCenterOut:
            return (0.5, [part(.reveal(from: nil, to: .middle), for: 0.5)])
        case .maskResizeIn:
            return (0.6, [part(.reveal(from: .edge(direction), to: nil), for: 0.6)])
        case .maskResizeOut:
            return (0.5, [part(.reveal(from: nil, to: .edge(direction)), for: 0.5)])
        case .maskSlideIn:
            return (0.6, [part(.move(by: toward(s.direction), entering: true), for: 0.6),
                          part(.reveal(from: .edge(Self.opposite(direction)), to: nil), for: 0.6)])
        case .maskSlideOut:
            return (0.5, [part(.move(by: toward(s.direction), entering: false), for: 0.5),
                          part(.reveal(from: nil, to: .edge(Self.opposite(direction))), for: 0.5)])
        case .maskShrinkIn:
            return (0.7, [part(.reveal(from: .centre(zoom: scale), to: nil), for: 0.7)])
        case .maskShrinkOut:
            return (0.5, [part(.reveal(from: nil, to: .centre(zoom: scale)), for: 0.5)])
        case .blurSlideIn:
            return (0.6, [part(.blur(from: blur, to: 0), for: 0.6),
                          part(.move(by: toward(s.direction), entering: true), for: 0.6)] + fadeIn(0.4))
        case .blurSlideOut:
            return (0.5, [part(.blur(from: nil, to: blur), for: 0.5),
                          part(.move(by: toward(s.direction), entering: false), for: 0.5)] + fadeOut(0.5))
        case .blurScaleIn:
            return (0.6, [part(.blur(from: blur, to: 0), for: 0.6), part(.scale(from: scale, to: nil), for: 0.6)] + fadeIn(0.4))
        case .blurScaleOut:
            return (0.5, [part(.blur(from: nil, to: blur), for: 0.5), part(.scale(from: nil, to: scale), for: 0.5)] + fadeOut(0.5))
        case .fadeSoundIn:
            return (1, [part(.volume(from: 0, to: nil), for: 1)])
        case .fadeSoundOut:
            return (1, [part(.volume(from: nil, to: 0), for: 1)])
        case .pulse:
            let peak = s.scale ?? own.scale ?? 1.12
            return (0.43, [part(.scale(from: nil, to: peak), for: 0.18), part(.scale(from: nil, to: 1), at: 0.18, for: 0.25)])
        case .bounce:
            return (0.7, [part(.move(by: Vec2(0, -distance), entering: false), for: 0.2, easing: slowDown),
                          part(.move(by: Vec2(0, distance), entering: false), at: 0.2, for: 0.5,
                               easing: .preset(.spring, intensity: 0.5))])
        case .shake:
            let d = distance
            return (0.34, [part(.move(by: Vec2(d, 0), entering: false), for: 0.06, easing: .default),
                           part(.move(by: Vec2(-2 * d, 0), entering: false), at: 0.06, for: 0.1, easing: .default),
                           part(.move(by: Vec2(2 * d, 0), entering: false), at: 0.16, for: 0.1, easing: .default),
                           part(.move(by: Vec2(-d, 0), entering: false), at: 0.26, for: 0.08, easing: .default)])
        case .wiggle:
            let a = s.angle ?? own.angle ?? 8
            return (0.46, [part(.rotate(by: a, entering: false), for: 0.08, easing: .default),
                           part(.rotate(by: -2 * a, entering: false), at: 0.08, for: 0.14, easing: .default),
                           part(.rotate(by: 2 * a, entering: false), at: 0.22, for: 0.14, easing: .default),
                           part(.rotate(by: -a, entering: false), at: 0.36, for: 0.1, easing: .default)])
        }
    }
}

extension Action {
    /// Whether it changes `channel`: its own kind's, or any a preset's parts
    /// reach.
    public func drives(_ channel: Channel) -> Bool {
        if case .preset(let p) = spec { return PresetRecipe.channels(p).contains(channel) }
        return spec.kind.channel == channel
    }
}
