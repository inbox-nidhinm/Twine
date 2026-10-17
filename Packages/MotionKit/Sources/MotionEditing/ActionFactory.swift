import Foundation
import MotionModel
import MotionEvaluation

/// New actions, set up the way the action menu adds them: at the playhead,
/// half a second long, with an end value that visibly does something.
public enum ActionFactory {
    /// How long a new action runs, before landing on a frame.
    public static let defaultDuration = 0.5
    /// How long a new Counter runs.
    public static let counterDuration = 2.0
    /// How long a new Volume fade runs: a sound cut in half a second sounds
    /// clipped.
    public static let fadeDuration = 1.0

    private static func fontSize(of layer: Layer) -> Double {
        if case .text(let t) = layer.content { return t.fontSize }
        return 48
    }

    /// The actions that make sense on `layer`, in menu order. Audio has
    /// nothing to move or fade; a group's size is its children's, so it
    /// scales rather than resizes. Style acts on what a shape has: Colour
    /// on its first fill, Stroke and Trim on its first stroke, Corner Radius
    /// on a rectangle. Background blur and inner shadows follow a shape's
    /// outline, and a text with a stroke takes Stroke too. Volume is
    /// for layers with sound: always a sound, and a video when `hasSound`
    /// says its file has a sound track (see `kinds(for:in:)`).
    public static func kinds(for layer: Layer, hasSound: Bool = false) -> [ActionKind] {
        let transform: [ActionKind] = [.move, .scale, .rotate, .skew, .tilt, .depth, .bend, .opacity, .resize, .visibility]
        switch layer.content {
        case .audio:
            // Sound has nothing to move or fade; it plays, louder or softer.
            return [.play, .volume]
        case .group(let group):
            guard let frame = group.frame else { return transform.filter { $0 != .resize } + [.shadow, .layerBlur] }
            // A frame resizes, and has a look to change, as a rectangle does.
            var kinds = transform
            if let top = frame.fills.last, !top.paint.isImage { kinds.append(.color) }
            if !frame.strokes.isEmpty { kinds.append(.stroke) }
            kinds += [.cornerRadius, .shadow, .innerShadow, .layerBlur, .backgroundBlur]
            // A frame in 3D has a camera to move.
            if frame.space != nil { kinds.append(.camera) }
            return kinds
        case .shape(let shape):
            var kinds = transform
            // A picture has no colour to change.
            if let top = shape.fills.last, !top.paint.isImage { kinds.append(.color) }
            if let first = shape.strokes.first {
                kinds += [.stroke, .trim]
                // Only dashes or dots have anything to move.
                if first.dotted || first.dashPattern.contains(where: { $0 > 0 }) { kinds.append(.dash) }
            }
            switch shape.geometry {
            case .rectangle, .polygon: kinds.append(.cornerRadius)
            default: break
            }
            kinds += [.shadow, .innerShadow, .layerBlur, .backgroundBlur]
            if case .ellipse = shape.geometry { kinds.append(.arc) }
            if case .star = shape.geometry { kinds.append(.star) }
            if case .path = shape.geometry { kinds.append(.path) }
            return kinds
        case .text(let text):
            // A text box is always the size of its words, so it has nothing
            // to resize.
            return transform.filter { $0 != .resize } + [.color] + (text.stroke == nil ? [] : [.stroke])
                + [.shadow, .layerBlur, .letterSpacing, .lineHeight, .counter, .changeText]
        case .video:
            return transform + [.shadow, .layerBlur, .play] + (hasSound ? [.volume] : [])
        }
    }

    /// The kinds for a layer in `project`, which knows whether a video's file
    /// has sound.
    public static func kinds(for layer: Layer, in project: Project) -> [ActionKind] {
        kinds(for: layer, hasSound: project.hasSound(layer))
    }

    /// Kinds offered for several layers at once: those every one of them takes.
    /// A sound among layers that draw is left out, as it shares nothing
    /// with them (it only plays, louder or softer): the others' actions are
    /// offered, and adding one skips the sound.
    public static func kinds(for layers: [Layer], in project: Project) -> [ActionKind] {
        let drawn = layers.filter { if case .audio = $0.content { return false } else { return true } }
        let layers = drawn.isEmpty ? layers : drawn
        guard let first = layers.first else { return [] }
        return layers.dropFirst().reduce(kinds(for: first, in: project)) { shared, layer in
            let allowed = Set(kinds(for: layer, in: project))
            return shared.filter(allowed.contains)
        }
    }

    /// A new action of `kind` on `layer`, starting at `time`. `state` is the
    /// layer at that moment, which sets defaults that depend on it: a Resize
    /// grows from the current size, and Hide/Show does whichever is not
    /// already the case. `rowOrder` should put it after the layer's others.
    /// `duration` and `easing` are what an ordinary action takes; a Show or
    /// Hide is instant, and a counter, a sound fade and a Play keep lengths
    /// of their own.
    public static func make(_ kind: ActionKind, for layer: Layer, at time: Double, state: LayerState,
                            frameRate: FrameRate, rowOrder: Int, mediaLength: Double? = nil,
                            duration ordinary: Double = defaultDuration, easing: Easing = .default) -> Action {
        let start = frameRate.snapped(max(time, 0))
        let duration = max(frameRate.snapped(ordinary), frameRate.frameDuration)
        let spec: ActionSpec
        var name: String?
        var counting = false
        var playing = false
        switch kind {
        case .move:
            spec = .move(MoveAction(mode: .by, end: Vec2(100, 0)))
        case .scale:
            spec = .scale(ScaleAction(mode: .to, end: Vec2(1.2, 1.2)))
        case .rotate:
            spec = .rotate(RotateAction(mode: .by, end: 90))
        case .skew:
            spec = .skew(SkewAction(mode: .by, end: Vec2(15, 0)))
        case .tilt:
            // Turns it a third of the way round, side to side, at its own depth.
            spec = .tilt(TiltAction(mode: .by, end: Tilt(x: 0, y: 30, depth: state.tilt.depth)))
        case .bend:
            // A sixth of a turn across: a gentle curve, its middle forward.
            spec = .bend(BendAction(mode: .by, end: Vec2(60, 0)))
        case .depth:
            // Towards the viewer, enough to see it come forward.
            spec = .depth(DepthAction(mode: .by, end: 200))
        case .camera:
            // The camera in to half its distance, so the perspective deepens.
            let space = state.camera.space ?? Space3D()
            var end = space
            end.distance = max((space.distance / 2).rounded(), 1)
            spec = .camera(CameraAction(end: end))
        case .opacity:
            spec = .opacity(OpacityAction(end: 0))
        case .resize:
            let s = state.size
            spec = .resize(ResizeAction(end: Size2((s.width * 1.2).rounded(), (s.height * 1.2).rounded()), isLinked: true))
        case .visibility:
            spec = .visibility(VisibilityAction(isVisible: !state.isShown))
            name = state.isShown ? "Hide" : "Show"
        case .color:
            spec = .color(ColorAction(end: contrasting(state.fill ?? .solid(.white))))
        case .stroke:
            let look = state.stroke ?? StrokeLook(width: 1, paint: .solid(.black))
            spec = .stroke(StrokeAction(end: StrokeLook(width: max(look.width + 4, look.width * 2), paint: look.paint)))
        case .trim:
            // Draws the line on: nothing until the action, then all of it.
            spec = .trim(TrimAction(initial: TrimRange(amount: 0), end: .whole))
        case .dash:
            spec = .dash(DashAction())
        case .cornerRadius:
            let radii = state.cornerRadii ?? .zero
            let most = min(state.size.width, state.size.height) / 2
            let current = max(radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft)
            spec = .cornerRadius(CornerRadiusAction(end: CornerRadii(all: current >= most * 0.75 ? 0 : (most / 2).rounded())))
        case .shadow:
            var shadow = state.shadow
            if shadow.opacity <= 0 || shadow.color.a <= 0 {
                shadow = DropShadow(color: .black, offset: Vec2(0, 12), blur: 32, opacity: 0.35)
            } else {
                shadow.offset = shadow.offset == .zero ? Vec2(0, 12) : Vec2(shadow.offset.x * 2, shadow.offset.y * 2)
                shadow.blur = max(shadow.blur * 2, 16)
            }
            spec = .shadow(ShadowAction(end: shadow))
        case .innerShadow:
            // A soft one in from nothing, or the designed one deepened.
            var shadow = state.innerShadow.shadow
            if shadow.opacity <= 0 || shadow.color.a <= 0 {
                shadow = DropShadow(color: .black, offset: Vec2(0, 4), blur: 16, opacity: 0.35)
            } else {
                shadow.offset = shadow.offset == .zero ? Vec2(0, 4) : Vec2(shadow.offset.x * 2, shadow.offset.y * 2)
                shadow.blur = max(shadow.blur * 2, 16)
            }
            spec = .innerShadow(ShadowAction(end: shadow))
        case .layerBlur:
            spec = .layerBlur(LayerBlurAction(end: state.layerBlur > 0 ? 0 : 12))
        case .backgroundBlur:
            spec = .backgroundBlur(BackgroundBlurAction(end: BackgroundBlur(radius: state.backgroundBlur.radius > 0 ? 0 : 24)))
        case .letterSpacing:
            let current = state.letterSpacing ?? 0
            spec = .letterSpacing(LetterSpacingAction(end: current > 0 ? 0 : (fontSize(of: layer) * 0.2).rounded()))
        case .lineHeight:
            let current = state.lineHeight ?? fontSize(of: layer) * 1.2
            spec = .lineHeight(LineHeightAction(end: (current * 1.5).rounded()))
        case .counter:
            // Up by a hundred from the number in the text, or from 0.
            let from = NumberFormat.read(state.text?.text ?? "")?.value ?? 0
            spec = .counter(CounterAction(to: from + 100))
            counting = true
        case .changeText:
            spec = .changeText(ChangeTextAction(text: state.text?.text == "Hello" ? "World" : "Hello"))
        case .arc:
            let arc = state.arc ?? .full
            spec = .arc(ArcAction(end: arc.isWhole ? EllipseArc(start: arc.start, end: arc.start + 270, innerRadius: arc.innerRadius)
                                                  : EllipseArc(start: arc.start, end: arc.start + 360, innerRadius: arc.innerRadius)))
        case .star:
            var star = state.star ?? StarShape(points: 5, innerRadius: 0.4)
            star.points += 3
            spec = .star(StarAction(end: star))
        case .path:
            // Sharp corners rounded off, or round points made sharp, for a
            // shape plain to see; the canvas then sets it point by point.
            let path = state.path ?? PathEditing.path(of: layer) ?? BezierPath()
            spec = .path(PathAction(end: PathEditing.reshapedForNewAction(path)))
        case .play:
            spec = .play(PlayAction(trimStart: 0))
            playing = true
        case .volume:
            // Fades the sound out, or in to its own level when it is silent.
            let level = state.volume ?? 1
            spec = .volume(VolumeAction(end: level > 0.01 ? 0 : 1))
        case .preset:
            // Presets come from `Presets.action`; this is only for completeness.
            spec = .preset(PresetRecipe.defaults(.fadeIn))
        }
        // Counting a hundred numbers in half a second is a blur; a counter
        // gets long enough to read.
        let length = kind == .visibility ? 0 : counting ? frameRate.snapped(counterDuration)
            : kind == .volume ? frameRate.snapped(fadeDuration)
            : playing ? max(frameRate.snapped(mediaLength ?? defaultDuration), frameRate.frameDuration) : duration
        return Action(target: layer.id, start: start, duration: length, easing: easing,
                      name: name, rowOrder: rowOrder, spec: spec)
    }

    /// A paint that is plainly different from `paint`: for a colour, the
    /// farthest of three bright ones; for a gradient, its colours reversed.
    static func contrasting(_ paint: Paint) -> Paint {
        switch paint {
        case .solid(let color):
            let options = [RGBA(hex: "4C9FEF")!, RGBA(hex: "FF5C8A")!, RGBA(hex: "FFC94D")!]
            func distance(_ c: RGBA) -> Double {
                (c.r - color.r) * (c.r - color.r) + (c.g - color.g) * (c.g - color.g) + (c.b - color.b) * (c.b - color.b)
            }
            var end = options.max { distance($0) < distance($1) } ?? options[0]
            end.a = color.a
            return .solid(end)
        case .linearGradient(var g), .radialGradient(var g), .angularGradient(var g):
            let colors = g.stops.map(\.color).reversed()
            g.stops = zip(g.stops, colors).map { GradientStop(position: $0.position, color: $1) }
            return paint.withGradient(g)
        case .image:
            return .solid(RGBA(hex: "4C9FEF")!)
        }
    }

    /// The row at the bottom of the timeline, after every other action.
    public static func nextRowOrder(in project: Project) -> Int {
        (project.actions.map(\.rowOrder).max() ?? -1) + 1
    }
}

extension Project {
    /// Whether a layer makes sound: a sound always, a video when its file
    /// has a sound track.
    public func hasSound(_ layer: Layer) -> Bool {
        switch layer.content {
        case .audio: return true
        case .video(let v): return media.first { $0.id == v.mediaID }?.hasAudio ?? false
        default: return false
        }
    }
}
