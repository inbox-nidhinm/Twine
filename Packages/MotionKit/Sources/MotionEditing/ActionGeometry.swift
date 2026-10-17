import Foundation
import MotionModel
import MotionEvaluation

/// A Move's path in its layer's parent space: where it starts, where it
/// ends, and, when curved, where its two handles sit.
public struct MovePath: Equatable, Sendable {
    public var start: Vec2
    public var end: Vec2
    /// Absolute handle positions, nil for a straight move.
    public var startHandle: Vec2?
    public var endHandle: Vec2?
}

/// Canvas and inspector edits to an action's values, in the terms a person
/// uses (a point, a size, an angle), turned into what the action stores.
/// `from` is always the value the action starts from: its initial value, or
/// what it inherits.
public enum ActionGeometry {
    /// Where a Move goes, given the position it starts from.
    public static func path(of move: MoveAction, from start: Vec2) -> MovePath {
        let s = move.initial ?? start
        let e = move.mode == .to ? move.end : s + move.end
        return MovePath(start: s, end: e, startHandle: move.curve.map { s + $0.startHandle },
                        endHandle: move.curve.map { e + $0.endHandle })
    }

    /// The Move's end placed at `point`.
    public static func settingEnd(_ move: MoveAction, to point: Vec2, from start: Vec2) -> MoveAction {
        var m = move
        m.end = m.mode == .to ? point : point - (move.initial ?? start)
        return m
    }

    /// The Move's start placed at `point`, as its initial value. The end
    /// stays where it is on the canvas, whichever the mode.
    public static func settingStart(_ move: MoveAction, to point: Vec2, from start: Vec2) -> MoveAction {
        let end = path(of: move, from: start).end
        var m = move
        m.initial = point
        if m.mode == .by { m.end = end - point }
        return m
    }

    /// A curve's handle placed at `point`: the first is an offset from the
    /// start, the second from the end.
    public static func settingHandle(_ move: MoveAction, first: Bool, to point: Vec2, from start: Vec2) -> MoveAction {
        let p = path(of: move, from: start)
        var m = move
        var curve = m.curve ?? defaultCurve(from: p.start, to: p.end)
        if first { curve.startHandle = point - p.start } else { curve.endHandle = point - p.end }
        m.curve = curve
        return m
    }

    /// A gentle arch for a move just made curved: each handle a third of the
    /// way along, lifted to one side by a quarter of the distance, so the
    /// curve shows at once and its handles are there to drag.
    public static func defaultCurve(from start: Vec2, to end: Vec2) -> MotionCurve {
        var d = end - start
        if hypot(d.x, d.y) < 1 { d = Vec2(100, 0) }
        // At right angles to the move, towards the top of the screen for a
        // move to the right.
        let lift = Vec2(d.y * 0.25, -d.x * 0.25)
        return MotionCurve(startHandle: Vec2(d.x / 3 + lift.x, d.y / 3 + lift.y),
                           endHandle: Vec2(-d.x / 3 + lift.x, -d.y / 3 + lift.y))
    }

    /// A Scale's end set so the layer ends at `scale`.
    public static func settingEnd(_ action: ScaleAction, to scale: Vec2, from start: Vec2) -> ScaleAction {
        var s = action
        let base = action.initial ?? start
        s.end = s.mode == .to ? scale
            : Vec2(base.x != 0 ? scale.x / base.x : 1, base.y != 0 ? scale.y / base.y : 1)
        return s
    }

    /// A Rotate's end set so the layer ends at `angle` degrees.
    public static func settingEnd(_ action: RotateAction, to angle: Double, from start: Double) -> RotateAction {
        var r = action
        r.end = r.mode == .to ? angle : angle - (action.initial ?? start)
        return r
    }

    /// The action switched between To and By with its motion unchanged: the
    /// end value is converted, not reinterpreted. `from` is what the action
    /// inherits at its start.
    public static func switchingMode(_ action: Action, to mode: ActionMode, from state: LayerState) -> Action {
        var a = action
        switch action.spec {
        case .move(var m) where m.mode != mode:
            let p = path(of: m, from: state.position)
            m.mode = mode
            m.end = mode == .to ? p.end : p.end - p.start
            a.spec = .move(m)
        case .scale(var s) where s.mode != mode:
            let base = s.initial ?? state.scale
            let final = s.mode == .to ? s.end : Vec2(base.x * s.end.x, base.y * s.end.y)
            s.mode = mode
            s = settingEnd(s, to: final, from: state.scale)
            a.spec = .scale(s)
        case .rotate(var r) where r.mode != mode:
            let base = r.initial ?? state.rotation
            let final = r.mode == .to ? r.end : base + r.end
            r.mode = mode
            r = settingEnd(r, to: final, from: state.rotation)
            a.spec = .rotate(r)
        case .depth(var d) where d.mode != mode:
            let base = d.initial ?? state.z
            let final = d.mode == .to ? d.end : base + d.end
            d.mode = mode
            d.end = mode == .to ? final : final - base
            a.spec = .depth(d)
        default:
            break
        }
        return a
    }

    /// The action played backwards: it starts where it used to end and ends
    /// where it used to start, keeping its mode. An empty starting value is
    /// read from `from`, what the action inherits, so it is always set
    /// afterwards. A curved Move keeps its shape, run the other way. Nil for
    /// an action with no start and end to swap (Show, Change Text, Play,
    /// presets), or a start the layer does not have.
    public static func swappingEnds(_ action: Action, from state: LayerState) -> Action? {
        var a = action
        switch action.spec {
        case .move(var m):
            let p = path(of: m, from: state.position)
            m.initial = p.end
            m.end = m.mode == .to ? p.start : p.start - p.end
            // Each handle is an offset from its own end, so they trade places.
            m.curve = m.curve.map { MotionCurve(startHandle: $0.endHandle, endHandle: $0.startHandle) }
            a.spec = .move(m)
        case .scale(var s):
            let base = s.initial ?? state.scale
            s.initial = s.mode == .to ? s.end : Vec2(base.x * s.end.x, base.y * s.end.y)
            s = settingEnd(s, to: base, from: state.scale)
            a.spec = .scale(s)
        case .rotate(var r):
            let base = r.initial ?? state.rotation
            r.initial = r.mode == .to ? r.end : base + r.end
            r = settingEnd(r, to: base, from: state.rotation)
            a.spec = .rotate(r)
        case .skew(var k):
            let base = k.initial ?? state.skew
            let final = k.mode == .to ? k.end : base + k.end
            k.initial = final
            k.end = k.mode == .to ? base : base - final
            a.spec = .skew(k)
        case .tilt(var t):
            // The depth is the action's own, shared by both ends.
            let depth = t.end.depth
            let base = t.initial ?? state.tilt
            let final = t.mode == .to ? t.end : Tilt(x: base.x + t.end.x, y: base.y + t.end.y, depth: depth)
            t.initial = Tilt(x: final.x, y: final.y, depth: depth)
            t.end = t.mode == .to ? Tilt(x: base.x, y: base.y, depth: depth)
                : Tilt(x: base.x - final.x, y: base.y - final.y, depth: depth)
            a.spec = .tilt(t)
        case .depth(var d):
            let base = d.initial ?? state.z
            let final = d.mode == .to ? d.end : base + d.end
            d.initial = final
            d.end = d.mode == .to ? base : base - final
            a.spec = .depth(d)
        case .camera(var c):
            guard let start = c.initial ?? state.camera.space else { return nil }
            (c.initial, c.end) = (c.end, start)
            a.spec = .camera(c)
        case .opacity(var o):
            (o.initial, o.end) = (o.end, o.initial ?? state.opacity)
            a.spec = .opacity(o)
        case .resize(var r):
            (r.initial, r.end) = (r.end, r.initial ?? state.size)
            a.spec = .resize(r)
        case .color(var c):
            guard let start = c.initial ?? state.fill else { return nil }
            (c.initial, c.end) = (c.end, start)
            a.spec = .color(c)
        case .stroke(var k):
            guard let start = k.initial ?? state.stroke else { return nil }
            (k.initial, k.end) = (k.end, start)
            a.spec = .stroke(k)
        case .trim(var t):
            guard let start = t.initial ?? state.trim else { return nil }
            // The amounts trade places; the way it draws stays the action's.
            (t.initial, t.end) = (t.end, TrimRange(direction: t.end.direction, amount: start.amount))
            a.spec = .trim(t)
        case .cornerRadius(var r):
            guard let start = r.initial ?? state.cornerRadii else { return nil }
            (r.initial, r.end) = (r.end, start)
            a.spec = .cornerRadius(r)
        case .shadow(var s):
            (s.initial, s.end) = (s.end, s.initial ?? state.shadow)
            a.spec = .shadow(s)
        case .innerShadow(var s):
            (s.initial, s.end) = (s.end, s.initial ?? state.innerShadow.shadow)
            a.spec = .innerShadow(s)
        case .layerBlur(var b):
            (b.initial, b.end) = (b.end, b.initial ?? state.layerBlur)
            a.spec = .layerBlur(b)
        case .backgroundBlur(var b):
            (b.initial, b.end) = (b.end, b.initial ?? state.backgroundBlur)
            a.spec = .backgroundBlur(b)
        case .letterSpacing(var v):
            guard let start = v.initial ?? state.letterSpacing else { return nil }
            (v.initial, v.end) = (v.end, start)
            a.spec = .letterSpacing(v)
        case .lineHeight(var v):
            guard let start = v.initial ?? state.lineHeight else { return nil }
            (v.initial, v.end) = (v.end, start)
            a.spec = .lineHeight(v)
        case .counter(var c):
            // An empty From counts from the number in the text, or 0.
            let start = c.from ?? NumberFormat.read(state.text?.text ?? "")?.value ?? 0
            (c.from, c.to) = (c.to, start)
            a.spec = .counter(c)
        case .arc(var v):
            guard let start = v.initial ?? state.arc else { return nil }
            (v.initial, v.end) = (v.end, start)
            a.spec = .arc(v)
        case .star(var v):
            guard let start = v.initial ?? state.star else { return nil }
            (v.initial, v.end) = (v.end, start)
            a.spec = .star(v)
        case .path(var v):
            guard let start = v.initial ?? state.path else { return nil }
            (v.initial, v.end) = (v.end, start)
            a.spec = .path(v)
        case .volume(var v):
            guard let start = v.initial ?? state.volume else { return nil }
            (v.initial, v.end) = (v.end, start)
            a.spec = .volume(v)
        // Backwards, dashes travel the other way; following a trim, they
        // have no way of their own to turn.
        case .dash(var d):
            guard !d.followsTrim else { return nil }
            d.direction = d.direction == .forward ? .backward : .forward
            a.spec = .dash(d)
        case .visibility, .changeText, .play, .preset:
            return nil
        }
        return a
    }
}
