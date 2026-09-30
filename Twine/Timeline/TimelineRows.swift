import Foundation
import MotionModel
import Theme
import MotionEditing

/// The timeline's rows, top to bottom: one per action, in the order the
/// actions were added (or rows were dragged to), whatever their layer. Each
/// row's label names the layer and the action.
struct TimelineRow {
    /// The row's action; on a folded row, its layer's first.
    let action: Action
    let layerName: String
    let y: CGFloat
    /// On a folded layer's one row, every action of the layer, drawn
    /// together on it; nil on an ordinary row.
    var folded: [Action]? = nil
    /// The first row of a layer with more than one action, which carries
    /// the chevron that folds the layer's rows into one.
    var foldable = false

    /// The actions whose bars the row draws.
    var actions: [Action] { folded ?? [action] }

    /// A row, a little taller than a panel row so a bar is easy to grab.
    static let height: CGFloat = 34
    /// The bar inside it.
    static let barHeight: CGFloat = 24
    /// The column of labels down the left, which the transport sits over.
    /// As wide as the layers panel, so the timeline's divider lines up with
    /// that panel's right edge: both cards start at the same inset.
    static let labelWidth: CGFloat = Theme.panelWidth

    var layerID: UUID { action.targetLayerID }

    /// Every row for `project`, or only those on the layers in `only`. A
    /// layer in `folded` has one row, where its first would be, carrying all
    /// its actions.
    static func rows(of project: Project, only: Set<UUID>? = nil, folded: Set<UUID> = []) -> [TimelineRow] {
        let names = Dictionary(project.allLayers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let order = ActionEditing.timeline(in: project).filter { action in
            names[action.targetLayerID] != nil && (only?.contains(action.targetLayerID) ?? true)
        }
        var byLayer: [UUID: [Action]] = [:]
        for action in order { byLayer[action.targetLayerID, default: []].append(action) }
        var y: CGFloat = 0
        var started: Set<UUID> = []
        var rows: [TimelineRow] = []
        for action in order {
            let layer = action.targetLayerID
            let first = started.insert(layer).inserted
            let mine = byLayer[layer] ?? []
            if folded.contains(layer), mine.count > 1 {
                guard first else { continue }
                rows.append(TimelineRow(action: action, layerName: names[layer] ?? "", y: y, folded: mine, foldable: true))
            } else {
                rows.append(TimelineRow(action: action, layerName: names[layer] ?? "", y: y, foldable: first && mine.count > 1))
            }
            y += height
        }
        return rows
    }

    /// Actions in the order their rows run down the timeline.
    static func order(of actions: [Action], in project: Project) -> [Action] {
        let ids = Set(actions.map(\.id))
        return ActionEditing.timeline(in: project).filter { ids.contains($0.id) }
    }
}
