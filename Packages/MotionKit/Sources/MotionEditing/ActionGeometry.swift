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
        default:
            break
        }
        return a
    }
}
