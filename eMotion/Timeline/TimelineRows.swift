import Foundation
import MotionModel
import MotionEditing

/// The timeline's rows, top to bottom: one per action, in the order the
/// actions were added (or rows were dragged to), whatever their layer. Each
/// row's label names the layer and the action.
struct TimelineRow {
    let action: Action
    let layerName: String
    let y: CGFloat

    /// A row, a little taller than a panel row so a bar is easy to grab.
    static let height: CGFloat = 34
    /// The bar inside it.
    static let barHeight: CGFloat = 24
    /// The column of labels down the left, which the transport sits over.
    static let labelWidth: CGFloat = 240

    var layerID: UUID { action.targetLayerID }

    /// Every row for `project`, or only those on the layers in `only`.
    static func rows(of project: Project, only: Set<UUID>? = nil) -> [TimelineRow] {
        let names = Dictionary(project.allLayers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var y: CGFloat = 0
        return ActionEditing.timeline(in: project).compactMap { action in
            guard let name = names[action.targetLayerID] else { return nil }
            if let only, !only.contains(action.targetLayerID) { return nil }
            defer { y += height }
            return TimelineRow(action: action, layerName: name, y: y)
        }
    }

    /// Actions in the order their rows run down the timeline.
    static func order(of actions: [Action], in project: Project) -> [Action] {
        let ids = Set(actions.map(\.id))
        return ActionEditing.timeline(in: project).filter { ids.contains($0.id) }
    }
}
