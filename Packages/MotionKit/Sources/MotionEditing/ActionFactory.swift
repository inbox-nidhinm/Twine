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

    private static func fontSize(of layer: Layer) -> Double {
        if case .text(let t) = layer.content { return t.fontSize }
        return 48
    }

    /// The actions that make sense on `layer`, in menu order. Audio has
    /// nothing to move or fade; a group's size is its children's, so it
    /// scales rather than resizes. Style acts on what a shape has: Colour
    /// on its first fill, Stroke and Trim on its first stroke, Corner Radius
    /// on a rectangle. Background blur follows a shape's outline.
    public static func kinds(for layer: Layer) -> [ActionKind] {
        let transform: [ActionKind] = [.move, .scale, .rotate, .opacity, .resize, .visibility]
        switch layer.content {
        case .audio:
            // Sound has nothing to move or fade; it only plays.
            return [.play]
        case .group:
            return transform.filter { $0 != .resize } + [.shadow, .layerBlur]
        case .shape(let shape):
            var kinds = transform
            if !shape.fills.isEmpty { kinds.append(.color) }
            if !shape.strokes.isEmpty { kinds += [.stroke, .trim] }
            if case .rectangle = shape.geometry { kinds.append(.cornerRadius) }
            kinds += [.shadow, .layerBlur, .backgroundBlur]
            if case .ellipse = shape.geometry { kinds.append(.arc) }
            if case .star = shape.geometry { kinds.append(.star) }
            return kinds
        case .text:
            // A text box is always the size of its words, so it has nothing
            // to resize.
            return transform.filter { $0 != .resize } + [.color, .shadow, .layerBlur,
                                                        .letterSpacing, .lineHeight, .counter, .changeText]
        case .image:
            return transform + [.shadow, .layerBlur]
        case .video:
            return transform + [.shadow, .layerBlur, .play]
        }
    }

    /// Kinds offered for several layers at once: those every one of them takes.
    public static func kinds(for layers: [Layer]) -> [ActionKind] {
        guard let first = layers.first else { return [] }
        return layers.dropFirst().reduce(kinds(for: first)) { shared, layer in
            let allowed = Set(kinds(for: layer))
            return shared.filter(allowed.contains)
        }
    }

    /// A new action of `kind` on `layer`, starting at `time`. `state` is the
    /// layer at that moment, which sets defaults that depend on it: a Resize
    /// grows from the current size, and Hide/Show does whichever is not
    /// already the case. `rowOrder` should put it after the layer's others.
    public static func make(_ kind: ActionKind, for layer: Layer, at time: Double, state: LayerState,
                            frameRate: FrameRate, rowOrder: Int, mediaLength: Double? = nil) -> Action {
        let start = frameRate.snapped(max(time, 0))
        let duration = frameRate.snapped(defaultDuration)
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
            spec = .trim(TrimAction(initial: TrimRange(start: 0, end: 0), end: .whole))
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
        case .play:
            spec = .play(PlayAction(trimStart: 0))
            playing = true
        }
        // Counting a hundred numbers in half a second is a blur; a counter
        // gets long enough to read.
        let length = kind == .visibility ? 0 : counting ? frameRate.snapped(counterDuration)
            : playing ? max(frameRate.snapped(mediaLength ?? defaultDuration), frameRate.frameDuration) : duration
        return Action(target: layer.id, start: start, duration: length,
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
        case .linearGradient(var g), .radialGradient(var g):
            let colors = g.stops.map(\.color).reversed()
            g.stops = zip(g.stops, colors).map { GradientStop(position: $0.position, color: $1) }
            return paint.isRadialGradient ? .radialGradient(g) : .linearGradient(g)
        }
    }

    /// The row order that puts a new action after every other on its layer.
    public static func nextRowOrder(on layerID: UUID, in project: Project) -> Int {
        (project.actions(on: layerID).map(\.rowOrder).max() ?? -1) + 1
    }
}
