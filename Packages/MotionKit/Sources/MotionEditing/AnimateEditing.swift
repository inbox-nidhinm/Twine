import Foundation
import MotionModel
import MotionEvaluation

/// Editing a layer on the canvas in Animate (5 October 2026, the user's
/// request): the drawing tools, resizing and turning work there as in
/// Design, on the layer as it shows at the playhead, and change its design;
/// the animation follows, as a move already carried a layer's Move actions.
public enum AnimateEditing {
    /// `layer` as it shows: its design with the place, size, turn, scale,
    /// skew and anchor it has at the playhead, so a handle drag can be
    /// worked out where the handles are drawn.
    public static func shown(_ layer: Layer, as resolved: ResolvedLayer) -> Layer {
        var l = layer
        l.transform.position = resolved.position
        l.transform.anchor = resolved.anchor
        l.transform.scale = resolved.scale
        l.transform.rotation = resolved.rotation
        l.transform.skew = resolved.warp.skew
        l.size = resolved.size
        return l
    }

    /// The design that makes a resize of `shown` (giving `edited`) happen at
    /// the playhead: the place moved by as much, the size, anchor and scale
    /// grown by as much, so the layer ends up as `edited` shows whatever its
    /// actions add. Everything else is the edit's (a text taking a fixed
    /// width).
    public static func designed(_ design: Layer, shown: Layer, edited: Layer) -> Layer {
        func ratio(_ a: Double, _ b: Double) -> Double { abs(b) > 1e-9 ? a / b : 1 }
        var l = design
        l.content = edited.content
        l.transform.position = design.transform.position + (edited.transform.position - shown.transform.position)
        let grow = Vec2(ratio(edited.size.width, shown.size.width), ratio(edited.size.height, shown.size.height))
        l.size = Size2(design.size.width * grow.x, design.size.height * grow.y)
        l.transform.anchor = Vec2(design.transform.anchor.x * grow.x, design.transform.anchor.y * grow.y)
        l.transform.scale = Vec2(design.transform.scale.x * ratio(edited.transform.scale.x, shown.transform.scale.x),
                                 design.transform.scale.y * ratio(edited.transform.scale.y, shown.transform.scale.y))
        l.transform.rotation = design.transform.rotation + (edited.transform.rotation - shown.transform.rotation)
        return l
    }

    /// The layer's Rotate, Resize and Scale actions carried along when its
    /// design goes from `old` to `new`: absolute values (To ends, and every
    /// starting value, which is absolute in both modes) turned or grown by
    /// as much, so the whole animation travels with the layer; By values
    /// stay, as they already add to whatever the layer is. Only the actions
    /// that change come back.
    public static func following(_ actions: [Action], from old: Layer, to new: Layer) -> [Action] {
        func ratio(_ a: Double, _ b: Double) -> Double { abs(b) > 1e-9 ? a / b : 1 }
        let turn = new.transform.rotation - old.transform.rotation
        let grow = Vec2(ratio(new.size.width, old.size.width), ratio(new.size.height, old.size.height))
        let stretch = Vec2(ratio(new.transform.scale.x, old.transform.scale.x), ratio(new.transform.scale.y, old.transform.scale.y))
        func grown(_ s: Size2) -> Size2 { Size2(s.width * grow.x, s.height * grow.y) }
        func stretched(_ v: Vec2) -> Vec2 { Vec2(v.x * stretch.x, v.y * stretch.y) }
        return actions.compactMap { action in
            guard action.targetLayerID == new.id else { return nil }
            var a = action
            switch action.spec {
            case .rotate(var r) where turn != 0:
                if r.mode == .to { r.end += turn }
                r.initial = r.initial.map { $0 + turn }
                a.spec = .rotate(r)
            case .resize(var r) where grow != Vec2(1, 1):
                r.end = grown(r.end)
                r.initial = r.initial.map(grown)
                a.spec = .resize(r)
            case .scale(var s) where stretch != Vec2(1, 1):
                if s.mode == .to { s.end = stretched(s.end) }
                s.initial = s.initial.map(stretched)
                a.spec = .scale(s)
            default:
                return nil
            }
            return a == action ? nil : a
        }
    }
}
