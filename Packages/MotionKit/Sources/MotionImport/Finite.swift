import Foundation
import MotionModel

/// Layers from a file with nothing at or near infinity. Every number an SVG
/// gives is checked as it is read, but sums of checked numbers can still
/// run away (a scale of a billion at each of a dozen nested levels is
/// infinite), and a Figma paste's numbers are only JSON's. A layer placed
/// or sized past `SVGNumber.limit` cannot be drawn or edited sensibly, so it
/// is left out, with everything inside it.
enum Finite {
    static func layers(_ layers: [Layer]) -> [Layer] {
        layers.compactMap { layer in
            guard isFinite(layer) else { return nil }
            var l = layer
            if l.isGroup { l.children = Self.layers(l.children) }
            return l
        }
    }

    private static func fits(_ value: Double) -> Bool { value.isFinite && abs(value) <= SVGNumber.limit }

    static func isFinite(_ layer: Layer) -> Bool {
        let t = layer.transform
        let numbers = [t.position.x, t.position.y, t.anchor.x, t.anchor.y, t.scale.x, t.scale.y, t.rotation,
                       t.skew.x, t.skew.y, layer.size.width, layer.size.height, layer.opacity]
        guard numbers.allSatisfy(fits) else { return false }
        guard case .path(let path)? = layer.look?.geometry else { return true }
        return path.subpaths.allSatisfy { subpath in
            subpath.points.allSatisfy { p in
                [p.position.x, p.position.y, p.inHandle.x, p.inHandle.y, p.outHandle.x, p.outHandle.y].allSatisfy(fits)
            }
        }
    }
}
