import Foundation
import MotionModel
import MotionEvaluation

/// New layers, set up the way the tools make them.
public enum LayerFactory {
    public enum ShapeKind: String, CaseIterable, Sendable {
        case rectangle, ellipse, line, polygon, star

        public var title: String {
            switch self {
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .line: return "Line"
            case .polygon: return "Polygon"
            case .star: return "Star"
            }
        }
    }

    /// Figma's default fill, a light grey that reads on white and on black.
    public static let defaultFill = RGBA(hex: "D9D9D9")!
    /// Lines have no area to fill, so they get a stroke instead.
    public static let defaultStroke = RGBA(hex: "1E1E1E")!

    /// A shape filling `box` in its parent's space, with its anchor at the
    /// centre, visible for the whole composition.
    public static func shape(_ kind: ShapeKind, in box: Box, name: String, duration: Double) -> Layer {
        let size = Size2(max(box.width, 0), max(box.height, 0))
        let geometry: ShapeGeometry
        switch kind {
        case .rectangle: geometry = .rectangle(cornerRadii: AnimatableProperty(.zero))
        case .ellipse: geometry = .ellipse
        case .line: geometry = .line
        case .polygon: geometry = .polygon(sides: 6)
        case .star: geometry = .star(points: 5, innerRadius: AnimatableProperty(0.4))
        }
        let content: ShapeContent
        if kind == .line {
            content = ShapeContent(geometry: geometry, strokes: [Stroke(paint: .color(defaultStroke), width: 4, cap: .round)])
        } else {
            content = ShapeContent(geometry: geometry, fills: [Fill(paint: .color(defaultFill))])
        }
        return Layer(name: name, content: .shape(content), size: size, position: box.center, outPoint: duration)
    }

    /// A line from `start` to `end`: a box as long as the line and no taller,
    /// turned to point the right way, with its anchor in the middle.
    public static func line(from start: Vec2, to end: Vec2, name: String, duration: Double) -> Layer {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        var layer = shape(.line, in: Box(origin: .zero, size: Size2(length, 0)), name: name, duration: duration)
        layer.transform.position = AnimatableProperty(Vec2((start.x + end.x) / 2, (start.y + end.y) / 2))
        layer.transform.rotation = AnimatableProperty(atan2(dy, dx) * 180 / .pi)
        return layer
    }

    /// An empty group whose box is `box`, in its parent's space.
    public static func group(in box: Box, children: [Layer], name: String, duration: Double) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)), size: Size2(box.width, box.height),
              position: box.center, outPoint: duration)
    }

    /// `Rectangle 3` when the project already has two rectangles, and so on.
    public static func nextName(_ base: String, in project: Project) -> String {
        let taken = project.allLayers.compactMap { layer -> Int? in
            guard layer.name.hasPrefix(base + " ") else { return nil }
            return Int(layer.name.dropFirst(base.count + 1))
        }
        return "\(base) \((taken.max() ?? 0) + 1)"
    }
}
