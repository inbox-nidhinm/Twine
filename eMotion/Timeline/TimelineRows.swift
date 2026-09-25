import Foundation
import MotionModel
import MotionEditing

/// The timeline's rows, top to bottom: for each layer with actions, in the
/// layers panel's order (front first), a thin divider with its name, then
/// one row per action in the layer's row order.
struct TimelineRow {
    enum Kind {
        case layer(Layer)
        case action(Action, layerName: String)
    }

    let kind: Kind
    let y: CGFloat
    let height: CGFloat

    static let actionHeight: CGFloat = 24
    static let dividerHeight: CGFloat = 20
    /// The column down the left of the rows, where each action's eye sits.
    static let gutter: CGFloat = 28

    var action: Action? {
        if case .action(let a, _) = kind { return a }
        return nil
    }

    var layerID: UUID {
        switch kind {
        case .layer(let l): return l.id
        case .action(let a, _): return a.targetLayerID
        }
    }

    /// Every row for `project`, or only those of `only` when it is given.
    static func rows(of project: Project, only: Set<UUID>? = nil) -> [TimelineRow] {
        var out: [TimelineRow] = []
        var y: CGFloat = 0
        for layer in panelOrder(project.layers) {
            if let only, !only.contains(layer.id) { continue }
            let actions = ActionEditing.rows(on: layer.id, in: project)
            guard !actions.isEmpty else { continue }
            out.append(TimelineRow(kind: .layer(layer), y: y, height: dividerHeight))
            y += dividerHeight
            for action in actions {
                out.append(TimelineRow(kind: .action(action, layerName: layer.name), y: y, height: actionHeight))
                y += actionHeight
            }
        }
        return out
    }

    /// Actions in the order their rows run down the timeline.
    static func order(of actions: [Action], in project: Project) -> [Action] {
        let ids = Set(actions.map(\.id))
        return rows(of: project).compactMap(\.action).filter { ids.contains($0.id) }
    }

    /// The layer tree flattened as the layers panel lists it: front first,
    /// each group followed by its children.
    static func panelOrder(_ layers: [Layer]) -> [Layer] {
        layers.reversed().flatMap { [$0] + panelOrder($0.children) }
    }
}
