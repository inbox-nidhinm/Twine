import Foundation
import MotionModel
import MotionEditing

/// One row of the timeline: a layer, or one of an open layer's animated
/// properties. Front of the stack at the top, as in the layers panel.
struct TimelineRow: Identifiable {
    enum Kind {
        case layer(Layer, depth: Int)
        case property(Layer, PropertyID, depth: Int)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .layer(let l, _): return l.id.uuidString
        case .property(let l, let p, _): return "\(l.id.uuidString)/\(p.kind.rawValue)/\(p.target?.uuidString ?? "")"
        }
    }

    var layer: Layer {
        switch kind {
        case .layer(let l, _), .property(let l, _, _): return l
        }
    }

    var depth: Int {
        switch kind {
        case .layer(_, let d), .property(_, _, let d): return d
        }
    }

    static let height: CGFloat = 26

    /// Open layers show their animated properties and, for groups, their
    /// children after them. A property without keyframes has nothing to show
    /// on a timeline, so only animated ones get rows.
    static func rows(of project: Project, expanded: Set<UUID>) -> [TimelineRow] {
        var out: [TimelineRow] = []
        func walk(_ layers: [Layer], depth: Int) {
            for layer in layers.reversed() {
                out.append(TimelineRow(kind: .layer(layer, depth: depth)))
                guard expanded.contains(layer.id) else { continue }
                for property in LayerProperties.animated(of: layer) {
                    out.append(TimelineRow(kind: .property(layer, property, depth: depth + 1)))
                }
                if layer.isGroup { walk(layer.children, depth: depth + 1) }
            }
        }
        walk(project.layers, depth: 0)
        return out
    }

    /// Whether a layer has anything to open.
    static func canExpand(_ layer: Layer) -> Bool {
        layer.isGroup || !LayerProperties.animated(of: layer).isEmpty
    }
}
