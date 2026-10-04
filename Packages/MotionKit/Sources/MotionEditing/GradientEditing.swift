import Foundation
import MotionModel

/// Editing a gradient's stops and ends, as the inspector's gradient bar and
/// the canvas's gradient handles do (4 October 2026). Stops are kept in the
/// order they were made, not by position, so a stop being dragged past
/// another keeps its index; `order` gives them by position for showing.
public enum GradientEditing {
    /// The fewest stops a gradient has: one at each end.
    public static let fewestStops = 2

    /// The stops' indices from the start of the gradient to its end, ties
    /// in the order they were made.
    public static func order(of gradient: Gradient) -> [Int] {
        gradient.stops.indices.sorted { a, b in
            let pa = gradient.stops[a].position, pb = gradient.stops[b].position
            return pa == pb ? a < b : pa < pb
        }
    }

    /// The colour the gradient shows at `position` (0 at its start, 1 at its
    /// end): before the first stop its colour, after the last its colour,
    /// and between two a straight mix of them, as Core Animation draws it.
    public static func color(of gradient: Gradient, at position: Double) -> RGBA {
        let sorted = order(of: gradient).map { gradient.stops[$0] }
        guard let first = sorted.first, let last = sorted.last else { return .black }
        if position <= first.position { return first.color }
        if position >= last.position { return last.color }
        for (a, b) in zip(sorted, sorted.dropFirst()) where position <= b.position {
            let span = b.position - a.position
            let t = span > 0 ? (position - a.position) / span : 0
            func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
            return RGBA(mix(a.color.r, b.color.r), mix(a.color.g, b.color.g), mix(a.color.b, b.color.b), mix(a.color.a, b.color.a))
        }
        return last.color
    }

    /// A stop added at `position`, in the colour the gradient already shows
    /// there, so nothing changes until it is moved or recoloured; with its
    /// index.
    public static func adding(to gradient: Gradient, at position: Double) -> (gradient: Gradient, index: Int) {
        let p = clamped(position)
        var g = gradient
        g.stops.append(GradientStop(position: p, color: color(of: gradient, at: p)))
        return (g, g.stops.count - 1)
    }

    /// The gradient without the stop at `index`, or nil when it has only
    /// its two ends' stops left.
    public static func removing(_ index: Int, from gradient: Gradient) -> Gradient? {
        guard gradient.stops.count > fewestStops, gradient.stops.indices.contains(index) else { return nil }
        var g = gradient
        g.stops.remove(at: index)
        return g
    }

    /// The stop at `index` moved to `position`, held between the ends.
    public static func moving(_ index: Int, in gradient: Gradient, to position: Double) -> Gradient {
        guard gradient.stops.indices.contains(index) else { return gradient }
        var g = gradient
        g.stops[index].position = clamped(position)
        return g
    }

    /// The gradient turned end for end: every stop at the other side.
    public static func reversed(_ gradient: Gradient) -> Gradient {
        var g = gradient
        for i in g.stops.indices { g.stops[i].position = 1 - g.stops[i].position }
        return g
    }

    /// How far along the line from `start` to `end` the point nearest
    /// `point` lies, from 0 at the start to 1 at the end.
    public static func position(of point: Vec2, from start: Vec2, to end: Vec2) -> Double {
        let line = end - start
        let length = line.x * line.x + line.y * line.y
        guard length > 0 else { return 0 }
        let along = point - start
        return clamped((along.x * line.x + along.y * line.y) / length)
    }

    /// `point` turned about `pivot` to the nearest whole step of `degrees`,
    /// keeping its distance, for an end dragged with Shift.
    public static func snapped(_ point: Vec2, around pivot: Vec2, every degrees: Double = 15) -> Vec2 {
        let v = point - pivot
        let length = (v.x * v.x + v.y * v.y).squareRoot()
        guard length > 0, degrees > 0 else { return point }
        let step = degrees * .pi / 180
        let angle = (atan2(v.y, v.x) / step).rounded() * step
        return Vec2(pivot.x + cos(angle) * length, pivot.y + sin(angle) * length)
    }

    private static func clamped(_ p: Double) -> Double { p.isFinite ? min(max(p, 0), 1) : 0 }
}
