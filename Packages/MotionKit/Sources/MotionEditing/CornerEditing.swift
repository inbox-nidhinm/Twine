import Foundation
import MotionModel
import MotionEvaluation

/// Corner radius on any shape with corners, as Figma has it: a rectangle's
/// four, a polygon's or star's every point, and each point of a path on its
/// own. Points are `PointRef`s into `PathEditing.path(of:)`.
public enum CornerEditing {
    /// Whether the layer has corners a radius can round: not an ellipse or
    /// a line, which have none. Frames keep their own corners.
    public static func hasCorners(_ layer: Layer) -> Bool {
        guard case .shape(let shape) = layer.content else { return false }
        switch shape.geometry {
        case .rectangle, .polygon, .star, .path: return true
        case .ellipse, .line: return false
        }
    }

    /// The radii of the points `refs`, or of every point when nil, in
    /// order. Empty when the layer has no corners.
    public static func radii(of layer: Layer, at refs: Set<PointRef>?) -> [Double] {
        guard hasCorners(layer), let path = PathEditing.path(of: layer) else { return [] }
        let chosen = refs.map { $0.sorted() } ?? PathEditing.refs(in: path)
        return chosen.compactMap { PathEditing.point($0, in: path)?.cornerRadius }
    }

    /// The layer with `radius` on the points `refs`, or on every point when
    /// nil, and the layer's Path actions that changed with it. A rectangle
    /// stays one, its picked corners changing; a polygon or star stays one
    /// while every point changes together, and becomes a path once its
    /// points differ. A Path action's points take the new radius where they
    /// still had the layer's old one, so the corner stays round through it.
    public static func setting(_ radius: Double, at refs: Set<PointRef>?, of layer: Layer,
                               actions: [Action]) -> (layer: Layer, actions: [Action]) {
        let radius = max(radius, 0)
        guard var shape = layer.look, let before = PathEditing.path(of: layer) else { return (layer, []) }
        let all = Set(PathEditing.refs(in: before))
        let chosen = (refs ?? all).intersection(all)
        guard !chosen.isEmpty else { return (layer, []) }
        var edited = layer
        switch shape.geometry {
        case .rectangle(var radii):
            for ref in chosen where ref.subpath == 0 {
                switch ref.index {
                case 0: radii.topLeft = radius
                case 1: radii.topRight = radius
                case 2: radii.bottomRight = radius
                default: radii.bottomLeft = radius
                }
            }
            shape.geometry = .rectangle(cornerRadii: radii)
            edited.look = shape
            return (edited, [])
        case .polygon(let sides, _) where chosen == all:
            shape.geometry = .polygon(sides: sides, cornerRadius: radius)
            edited.look = shape
            return (edited, [])
        case .star(let points, let inner, _) where chosen == all:
            shape.geometry = .star(points: points, innerRadius: inner, cornerRadius: radius)
            edited.look = shape
            return (edited, [])
        case .polygon, .star:
            // Its points no longer share one radius: a path of the same points.
            let (reshaped, moved) = PathEditing.reshaped(layer, to: settingRadius(radius, at: chosen, in: before), actions: actions)
            return (reshaped, moved)
        case .path(let stored):
            // The stored points are the edited ones, in the same order, so
            // the box and everything placed by it stays.
            shape.geometry = .path(settingRadius(radius, at: chosen, in: stored))
            edited.look = shape
            let followed = actions.compactMap { action -> Action? in
                guard action.targetLayerID == layer.id, case .path(var p) = action.spec else { return nil }
                let end = following(p.end, from: stored, radius: radius, at: chosen)
                let initial = p.initial.map { following($0, from: stored, radius: radius, at: chosen) }
                guard end != p.end || initial != p.initial else { return nil }
                p.end = end
                p.initial = initial
                var a = action
                a.spec = .path(p)
                return a
            }
            return (edited, followed)
        case .ellipse, .line:
            return (layer, [])
        }
    }

    static func settingRadius(_ radius: Double, at refs: Set<PointRef>, in path: BezierPath) -> BezierPath {
        var path = path
        for ref in refs where PathEditing.point(ref, in: path) != nil {
            path.subpaths[ref.subpath].points[ref.index].cornerRadius = radius
        }
        return path
    }

    /// An action's points given the new radius wherever they matched the
    /// design's old one, when they have the design's shape of points.
    static func following(_ path: BezierPath, from design: BezierPath, radius: Double, at refs: Set<PointRef>) -> BezierPath {
        guard path.subpaths.count == design.subpaths.count,
              zip(path.subpaths, design.subpaths).allSatisfy({ $0.points.count == $1.points.count }) else { return path }
        let same = refs.filter { ref in
            PathEditing.point(ref, in: path)?.cornerRadius == PathEditing.point(ref, in: design)?.cornerRadius
        }
        return settingRadius(radius, at: same, in: path)
    }
}
