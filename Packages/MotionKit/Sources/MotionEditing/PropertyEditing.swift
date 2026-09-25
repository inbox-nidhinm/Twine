import Foundation
import MotionModel
import MotionEvaluation

/// Values that can be moved by a difference, so an edit to an animated
/// property can shift its whole animation rather than flatten it.
public protocol Offsettable: Interpolatable {
    static func + (a: Self, b: Self) -> Self
    static func - (a: Self, b: Self) -> Self
}

extension Double: Offsettable {}

extension Vec2: Offsettable {
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
}

extension Size2: Offsettable {
    public static func + (a: Size2, b: Size2) -> Size2 { Size2(a.width + b.width, a.height + b.height) }
    public static func - (a: Size2, b: Size2) -> Size2 { Size2(a.width - b.width, a.height - b.height) }
}

extension CornerRadii: Offsettable {
    public static func + (a: CornerRadii, b: CornerRadii) -> CornerRadii {
        CornerRadii(topLeft: a.topLeft + b.topLeft, topRight: a.topRight + b.topRight,
                    bottomRight: a.bottomRight + b.bottomRight, bottomLeft: a.bottomLeft + b.bottomLeft)
    }
    public static func - (a: CornerRadii, b: CornerRadii) -> CornerRadii {
        CornerRadii(topLeft: a.topLeft - b.topLeft, topRight: a.topRight - b.topRight,
                    bottomRight: a.bottomRight - b.bottomRight, bottomLeft: a.bottomLeft - b.bottomLeft)
    }
}

extension AnimatableProperty where Value: Offsettable {
    /// The static value and every keyframe moved by `delta`.
    public func shifted(by delta: Value) -> AnimatableProperty {
        AnimatableProperty(value + delta, keyframes: keyframes.map { key in
            var k = key
            k.value = key.value + delta
            return k
        })
    }

    /// A Design mode edit: a static property takes the new value, and an
    /// animated one moves its whole animation so that it passes through the
    /// new value at `time`, keeping its shape. (Animate mode, which keys the
    /// change at the playhead instead, arrives with the timeline.)
    public func designEdited(to new: Value, at time: Double) -> AnimatableProperty {
        guard isAnimated else { return AnimatableProperty(new) }
        return shifted(by: new - value(at: time))
    }
}

extension AnimatableProperty {
    /// A Design mode edit for values that cannot be offset, such as colours:
    /// a static property takes the new value; an animated one keeps its
    /// animation and takes the new value as its static fallback. Keying
    /// these at the playhead arrives with the timeline.
    public func designSet(_ new: Value) -> AnimatableProperty {
        var copy = self
        copy.value = new
        return copy
    }
}

extension Layer {
    /// The layer moved by `delta` in its parent's space, keyframes and all.
    public func translated(by delta: Vec2) -> Layer {
        var copy = self
        copy.transform.position = transform.position.shifted(by: delta)
        return copy
    }
}
