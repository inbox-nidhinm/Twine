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

    /// The layer given a new width or height as the inspector gives one: its
    /// top-left stays where it is and the anchor keeps its place in the box,
    /// as dragging the bottom-right handle would. A text box given a width
    /// keeps it, and wraps inside it.
    public func resized(width: Double? = nil, height: Double? = nil) -> Layer {
        var l = self
        let target = Size2(width ?? size.width, height ?? size.height)
        let anchor = transform.anchor
        let newAnchor = Vec2(size.width > 0 ? anchor.x / size.width * target.width : anchor.x,
                             size.height > 0 ? anchor.y / size.height * target.height : anchor.y)
        let old = Affine.layer(position: transform.position, anchor: anchor,
                               scale: transform.scale, rotation: transform.rotation, skew: transform.skew)
        let topLeft = old.apply(.zero)
        let offset = old.applyToVector(Vec2(-newAnchor.x, -newAnchor.y))
        l.size = target
        l.transform.anchor = newAnchor
        l.transform.position = Vec2(topLeft.x - offset.x, topLeft.y - offset.y)
        if width != nil, case .text(var t) = l.content {
            t.sizing = .fixedWidth
            l.content = .text(t)
        }
        return l
    }

    /// Whether width and height change together: the link in the inspector.
    /// Text sets its own height, so never for text.
    public var keepsProportionsWhenSized: Bool { !isText && keepsProportions }

    /// The layer given a new width, its height following when it keeps
    /// proportions.
    public func resized(toWidth w: Double) -> Layer {
        keepsProportionsWhenSized && size.width > 0 ? resized(width: w, height: size.height * w / size.width) : resized(width: w)
    }

    /// The layer given a new height, its width following when it keeps
    /// proportions.
    public func resized(toHeight h: Double) -> Layer {
        keepsProportionsWhenSized && size.height > 0 ? resized(width: size.width * h / size.height, height: h) : resized(height: h)
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
