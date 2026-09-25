import Foundation
import MotionModel

extension Layer {
    public var shapeContent: ShapeContent? {
        if case .shape(let s) = content { return s }
        return nil
    }

    public var shapeGeometry: ShapeGeometry? { shapeContent?.geometry }

    /// The layer moved by `delta` in its parent's space. Its By moves travel
    /// with it on their own; To moves are absolute and are moved separately,
    /// with `Action.remapped`.
    public func translated(by delta: Vec2) -> Layer {
        var copy = self
        copy.transform.position = transform.position + delta
        return copy
    }
}

extension Action {
    /// The action with its values carried into another space, for when its
    /// layer changes parent (grouping and ungrouping) and its animation
    /// should land where it was.
    ///
    /// `point` maps absolute positions: a To move's end and any move's initial
    /// value. `vector` maps offsets: a By move's end and a curve's handles.
    /// Rotations add `angle`, scales multiply by `scale`, and opacities
    /// multiply by `opacity`, for To values and initial values. By rotations
    /// and By scales are relative already and stay as they are.
    public func remapped(point: (Vec2) -> Vec2, vector: (Vec2) -> Vec2, angle: Double = 0,
                         scale: Vec2 = .one, opacity: Double = 1) -> Action {
        var copy = self
        func scaled(_ v: Vec2) -> Vec2 { Vec2(v.x * scale.x, v.y * scale.y) }
        switch spec {
        case .move(var m):
            m.end = m.mode == .to ? point(m.end) : vector(m.end)
            m.initial = m.initial.map(point)
            m.curve = m.curve.map { MotionCurve(startHandle: vector($0.startHandle), endHandle: vector($0.endHandle)) }
            copy.spec = .move(m)
        case .rotate(var r):
            if r.mode == .to { r.end += angle }
            r.initial = r.initial.map { $0 + angle }
            copy.spec = .rotate(r)
        case .scale(var s):
            if s.mode == .to { s.end = scaled(s.end) }
            s.initial = s.initial.map(scaled)
            copy.spec = .scale(s)
        case .opacity(var o):
            o.end *= opacity
            o.initial = o.initial.map { $0 * opacity }
            copy.spec = .opacity(o)
        case .resize, .visibility:
            break
        }
        return copy
    }
}

extension Project {
    /// Copies of the actions on the layers in `map` (old id to new id), aimed
    /// at the new layers, each with an id of its own. Duplicating or pasting
    /// a layer brings its animation with it this way.
    public func actionCopies(for map: [UUID: UUID]) -> [Action] {
        actions.compactMap { action in
            guard let target = map[action.targetLayerID] else { return nil }
            var copy = Action(target: target, start: action.start, duration: action.duration, easing: action.easing,
                              name: action.name, isEnabled: action.isEnabled, rowOrder: action.rowOrder,
                              spec: action.spec)
            copy.targetLayerID = target
            return copy
        }
    }

    /// The actions aimed at one layer.
    public func actions(on layerID: UUID) -> [Action] {
        actions.filter { $0.targetLayerID == layerID }
    }
}
