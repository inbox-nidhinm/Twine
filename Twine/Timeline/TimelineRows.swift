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
    /// Set on a scene's own row, which heads its actions' rows and shows
    /// their span; `members` are its actions in row order.
    var header: TimelineScene? = nil
    var members: [Action] = []
    /// The scene a row's action is in, drawn with its colour.
    var inScene: UUID? = nil

    /// The actions the row stands for: a scene row's members, a folded
    /// layer's actions, or the row's own.
    var actions: [Action] { header != nil ? members : folded ?? [action] }

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
    /// scene's actions sit together under a row of its own where its first
    /// would be, or only that row while it is in `foldedScenes`. A layer in
    /// `folded` has one row, where its first would be, carrying all its
    /// actions (inside a scene, all its actions in that scene). With
    /// `soundLast`, the rows of sound layers that are in no scene come
    /// after all the others, in their own order (`isSoundRow`).
    static func rows(of project: Project, only: Set<UUID>? = nil, folded: Set<UUID> = [],
                     foldedScenes: Set<UUID> = [], soundLast: Bool = false) -> [TimelineRow] {
        let names = Dictionary(project.allLayers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var order = ActionEditing.timeline(in: project).filter { action in
            names[action.targetLayerID] != nil && (only?.contains(action.targetLayerID) ?? true)
        }
        var sceneOf: [UUID: TimelineScene] = [:]
        for scene in project.scenes { for id in scene.actionIDs { sceneOf[id] = scene } }
        if soundLast {
            let sounds = soundLayers(in: project)
            // A scene keeps its rows together, sound or not.
            let low = order.filter { sceneOf[$0.id] == nil && sounds.contains($0.targetLayerID) }
            if !low.isEmpty {
                let ids = Set(low.map(\.id))
                order = order.filter { !ids.contains($0.id) } + low
            }
        }
        var members: [UUID: [Action]] = [:]
        for action in order { if let scene = sceneOf[action.id] { members[scene.id, default: []].append(action) } }

        var y: CGFloat = 0
        var rows: [TimelineRow] = []
        /// Rows for `actions` (a scene's, or those in no scene), in their
        /// order, each folded layer as one row at its first, holding its
        /// actions among these.
        func folding(_ actions: [Action]) -> (layers: [UUID: [Action]], started: Set<UUID>) {
            var byLayer: [UUID: [Action]] = [:]
            for action in actions { byLayer[action.targetLayerID, default: []].append(action) }
            return (byLayer, [])
        }
        func addRow(_ action: Action, among group: inout (layers: [UUID: [Action]], started: Set<UUID>), scene: UUID?) {
            let layer = action.targetLayerID
            let first = group.started.insert(layer).inserted
            let mine = group.layers[layer] ?? []
            let name = names[layer] ?? ""
            if folded.contains(layer), mine.count > 1 {
                guard first else { return }
                rows.append(TimelineRow(action: action, layerName: name, y: y, folded: mine, foldable: true, inScene: scene))
            } else {
                rows.append(TimelineRow(action: action, layerName: name, y: y, foldable: first && mine.count > 1, inScene: scene))
            }
            y += height
        }

        var loose = folding(order.filter { sceneOf[$0.id] == nil })
        var shown: Set<UUID> = []
        for action in order {
            guard let scene = sceneOf[action.id] else {
                addRow(action, among: &loose, scene: nil)
                continue
            }
            guard shown.insert(scene.id).inserted else { continue }
            let mine = members[scene.id] ?? []
            rows.append(TimelineRow(action: mine[0], layerName: names[mine[0].targetLayerID] ?? "", y: y,
                                    header: scene, members: mine))
            y += height
            guard !foldedScenes.contains(scene.id) else { continue }
            var inside = folding(mine)
            for member in mine { addRow(member, among: &inside, scene: scene.id) }
        }
        return rows
    }

    /// The layers that are only sound, whose rows can be gathered at the
    /// foot of the timeline.
    static func soundLayers(in project: Project) -> Set<UUID> {
        var ids: Set<UUID> = []
        project.forEachLayer { layer in
            if case .audio = layer.content { ids.insert(layer.id) }
        }
        return ids
    }

    /// Whether `action` is one the timeline gathers at its foot with
    /// `soundLast`: on a sound layer, in no scene.
    static func isSoundRow(_ action: Action, sounds: Set<UUID>, in project: Project) -> Bool {
        sounds.contains(action.targetLayerID) && !project.scenes.contains { $0.actionIDs.contains(action.id) }
    }

    /// Actions in the order their rows run down the timeline.
    static func order(of actions: [Action], in project: Project) -> [Action] {
        let ids = Set(actions.map(\.id))
        return ActionEditing.timeline(in: project).filter { ids.contains($0.id) }
    }
}
