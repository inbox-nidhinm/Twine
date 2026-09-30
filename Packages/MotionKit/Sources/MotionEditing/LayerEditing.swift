import Foundation
import MotionModel
import MotionEvaluation

extension Layer {
    public var shapeContent: ShapeContent? {
        if case .shape(let s) = content { return s }
        return nil
    }

    /// A shape's outline, or a frame's rectangle.
    public var shapeGeometry: ShapeGeometry? { look?.geometry }

    /// The layer moved by `delta` in its parent's space. Its By moves travel
    /// with it on their own; To moves are absolute and are moved separately,
    /// with `Action.remapped`.
    public func translated(by delta: Vec2) -> Layer {
        var copy = self
        copy.transform.position = transform.position + delta
        return copy
    }
}

extension Layer {
    public var isText: Bool {
        if case .text = content { return true }
        return false
    }

    /// A text layer with its box fitted to its words: as wide as its longest
    /// line for auto width, or its own width for fixed width, and as tall as
    /// its lines. The anchor moves so the text grows the way its alignment
    /// reads, and nothing else moves. Any other layer comes back unchanged.
    public func fittedText() -> Layer {
        guard case .text(let t) = content else { return self }
        let fitted = TextLayout.size(of: t.text, style: TextStyle(t), width: t.sizing == .fixedWidth ? size.width : nil)
        guard fitted != size else { return self }
        var l = self
        l.transform.anchor = TextLayout.anchor(transform.anchor, from: size, to: fitted, alignment: t.alignment)
        l.size = fitted
        return l
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
    ///
    /// Into a `mirrored` space (one flipped over, as a group with one scale
    /// negative is), turns run the other way and slants lean the other way.
    public func remapped(point: (Vec2) -> Vec2, vector: (Vec2) -> Vec2, angle: Double = 0,
                         scale: Vec2 = .one, opacity: Double = 1, mirrored: Bool = false) -> Action {
        var copy = self
        func scaled(_ v: Vec2) -> Vec2 { Vec2(v.x * scale.x, v.y * scale.y) }
        func turned(_ a: Double) -> Double { mirrored ? angle - a : a + angle }
        switch spec {
        case .move(var m):
            m.end = m.mode == .to ? point(m.end) : vector(m.end)
            m.initial = m.initial.map(point)
            m.curve = m.curve.map { MotionCurve(startHandle: vector($0.startHandle), endHandle: vector($0.endHandle)) }
            copy.spec = .move(m)
        case .rotate(var r):
            r.end = r.mode == .to ? turned(r.end) : mirrored ? -r.end : r.end
            r.initial = r.initial.map(turned)
            copy.spec = .rotate(r)
        case .skew(var k) where mirrored:
            k.end = Vec2(-k.end.x, -k.end.y)
            k.initial = k.initial.map { Vec2(-$0.x, -$0.y) }
            copy.spec = .skew(k)
        case .scale(var s):
            if s.mode == .to { s.end = scaled(s.end) }
            s.initial = s.initial.map(scaled)
            copy.spec = .scale(s)
        case .opacity(var o):
            o.end *= opacity
            o.initial = o.initial.map { $0 * opacity }
            copy.spec = .opacity(o)
        default:
            // Sizes, visibility and every style and blur live in the
            // layer's own space, which a new parent does not change.
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
        actionCopyPairs(for: map).map(\.copy)
    }

    /// The same copies, each with the id of the action it copies, so a copy
    /// can join its original's scene.
    public func actionCopyPairs(for map: [UUID: UUID]) -> [(original: UUID, copy: Action)] {
        actions.compactMap { action in
            guard let target = map[action.targetLayerID] else { return nil }
            var copy = Action(target: target, start: action.start, duration: action.duration, easing: action.easing,
                              name: action.name, isEnabled: action.isEnabled, rowOrder: action.rowOrder,
                              spec: action.spec)
            copy.targetLayerID = target
            copy.motionBlur = action.motionBlur
            return (action.id, copy)
        }
    }

    /// The actions aimed at one layer.
    public func actions(on layerID: UUID) -> [Action] {
        actions.filter { $0.targetLayerID == layerID }
    }
}
