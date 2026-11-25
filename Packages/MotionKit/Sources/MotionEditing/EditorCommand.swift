import Foundation
import MotionModel

/// Every way the interface is allowed to change a project.
///
/// The UI never writes to a `Project` directly. It describes the change as one
/// of these and hands it to `ProjectStore`, which applies it and records the
/// state before it for undo. Keeping the list short and explicit is what makes
/// "every change is undoable" something the compiler can check rather than a
/// habit: a view has no other route to the document.
public enum EditorCommand: Sendable {
    case setComposition(Composition)
    /// Inserts layers as siblings, in order, starting at `index` inside
    /// `parentID` (nil for the top level). A nil index puts them in front.
    case insertLayers([Layer], parentID: UUID?, index: Int?)
    case deleteLayers(Set<UUID>)
    /// Moves layers, keeping their current front-to-back order among
    /// themselves, to `index` inside `parentID`. The index is counted among the
    /// destination's children as they stand after the moved layers are taken out.
    case moveLayers([UUID], parentID: UUID?, index: Int?)
    case renameLayer(UUID, String)
    case setVisible(Set<UUID>, Bool)
    case setLocked(Set<UUID>, Bool)
    case setSoloed(Set<UUID>, Bool)
    /// Replaces layers wholesale with edited copies of themselves, matched by
    /// id. This is how property edits arrive until the property commands do.
    case updateLayers([Layer])
    case addMedia(MediaAsset)
    /// Adds actions. Each must aim at a layer that exists.
    case insertActions([Action])
    /// Replaces actions wholesale with edited copies, matched by id.
    case updateActions([Action])
    case deleteActions(Set<UUID>)
    /// The timeline's scenes, all of them, as they should be.
    case setScenes([TimelineScene])
    /// Several commands applied in order as one undo step, such as grouping,
    /// which takes layers out and puts a group in. If any fails, none apply.
    case batch([EditorCommand], name: String)

    /// What Edit > Undo calls it.
    public var actionName: String {
        switch self {
        case .setComposition: return "Composition Settings"
        case .insertLayers(let layers, _, _): return layers.count == 1 ? "Add Layer" : "Add Layers"
        case .deleteLayers(let ids): return ids.count == 1 ? "Delete Layer" : "Delete Layers"
        case .moveLayers: return "Move Layers"
        case .renameLayer: return "Rename Layer"
        case .setVisible(_, let on): return on ? "Show" : "Hide"
        case .setLocked(_, let on): return on ? "Lock" : "Unlock"
        case .setSoloed(_, let on): return on ? "Solo" : "Unsolo"
        case .updateLayers: return "Edit Layer"
        case .addMedia: return "Import"
        case .insertActions(let actions): return actions.count == 1 ? "Add Action" : "Add Actions"
        case .updateActions: return "Edit Action"
        case .deleteActions(let ids): return ids.count == 1 ? "Delete Action" : "Delete Actions"
        case .setScenes: return "Edit Scenes"
        case .batch(_, let name): return name
        }
    }

    /// Applies the change. Throws, leaving `project` untouched, if the command
    /// refers to something that is not there, so a stale command can never
    /// half-apply.
    public func apply(to project: inout Project) throws {
        var draft = project
        try apply(into: &draft)
        // An action on a layer that no longer exists does nothing, so it
        // goes with its layer, whichever command took the layer away.
        // Every pass here only looks, and changes the few layers that need
        // it, since this runs after every command, each step of a drag
        // included: three copies of a 5,000-layer tree took 4 ms a step.
        var remaining = Set<UUID>()
        draft.forEachLayer { remaining.insert($0.id) }
        draft.actions.removeAll { !remaining.contains($0.targetLayerID) }
        // A scene holds only actions still there, and goes when it holds none.
        if !draft.scenes.isEmpty {
            let actions = Set(draft.actions.map(\.id))
            draft.scenes = draft.scenes.compactMap { scene in
                var kept = scene
                kept.actionIDs = scene.actionIDs.filter(actions.contains)
                return kept.actionIDs.isEmpty ? nil : kept
            }
        }
        // A text box is always the size of its words, whatever changed them.
        var refitted: [Layer] = []
        draft.forEachLayer { layer in
            if layer.isText {
                let fitted = layer.fittedText()
                if fitted != layer { refitted.append(fitted) }
            }
        }
        for fitted in refitted { _ = draft.updateLayer(fitted.id) { $0 = fitted } }
        project = draft
    }

    private func apply(into p: inout Project) throws {
        switch self {
        case .setComposition(let composition):
            guard composition.width > 0, composition.height > 0, composition.duration > 0,
                  composition.duration <= Composition.longest else {
                throw EditorError.invalidValue
            }
            p.composition = composition

        case .insertLayers(let layers, let parentID, let index):
            var at = index
            for layer in layers {
                guard p.layer(withID: layer.id) == nil else { throw EditorError.duplicateID(layer.id) }
                guard p.insertLayer(layer, parentID: parentID, at: at) else { throw EditorError.notFound(parentID ?? layer.id) }
                at = at.map { $0 + 1 }
            }

        case .deleteLayers(let ids):
            for id in ids where p.layer(withID: id) != nil {
                p.removeLayer(id)
            }

        case .moveLayers(let ids, let parentID, let index):
            if let parentID {
                guard p.layer(withID: parentID)?.isGroup == true else { throw EditorError.notFound(parentID) }
                // A group cannot go inside itself or anything it contains.
                let blocked = Set(p.ancestors(of: parentID) + [parentID])
                guard blocked.isDisjoint(with: ids) else { throw EditorError.invalidMove }
            }
            // A layer inside another moving group travels with that group
            // rather than on its own. Found, taken out and put back in one
            // walk of the tree each: done layer by layer, each of those
            // searched the whole tree, and moving two thousand layers at
            // once (Select All in a large import, then Group) took a third
            // of a second.
            let wanted = Set(ids)
            let parents = p.parents
            func travels(_ id: UUID) -> Bool {
                var current = id
                while let up = parents[current] {
                    if wanted.contains(up) { return true }
                    current = up
                }
                return false
            }
            var place: [UUID: Int] = [:]
            p.forEachLayer { layer in
                if wanted.contains(layer.id), place[layer.id] == nil, !travels(layer.id) { place[layer.id] = place.count }
            }
            // Back in the order they stood in, whatever order they came out.
            let moving = p.removeLayers(Set(place.keys)).sorted { (place[$0.id] ?? 0) < (place[$1.id] ?? 0) }
            p.insertLayers(moving, parentID: parentID, at: index)

        case .renameLayer(let id, let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw EditorError.invalidValue }
            guard p.updateLayer(id, { $0.name = trimmed }) else { throw EditorError.notFound(id) }

        case .setVisible(let ids, let on):
            try Self.each(ids, in: &p) { $0.isVisible = on }
        case .setLocked(let ids, let on):
            try Self.each(ids, in: &p) { $0.isLocked = on }
        case .setSoloed(let ids, let on):
            try Self.each(ids, in: &p) { $0.isSoloed = on }

        case .updateLayers(let layers):
            // Many at once go in one walk of the tree, when none sits
            // inside another (then the order they are given in matters,
            // and they go one by one as a few always do).
            if layers.count > 8 {
                let replacements = Dictionary(layers.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                let parents = p.parents
                let nested = replacements.keys.contains { id in
                    var current = id
                    while let up = parents[current] {
                        if replacements[up] != nil { return true }
                        current = up
                    }
                    return false
                }
                if !nested, replacements.count == layers.count {
                    let found = p.replaceLayers(replacements)
                    if let missing = layers.first(where: { !found.contains($0.id) }) { throw EditorError.notFound(missing.id) }
                    break
                }
            }
            for layer in layers {
                guard p.updateLayer(layer.id, { $0 = layer }) else { throw EditorError.notFound(layer.id) }
            }

        case .addMedia(let asset):
            guard !p.media.contains(where: { $0.id == asset.id }) else { throw EditorError.duplicateID(asset.id) }
            p.media.append(asset)

        // A few actions are each checked against the project as it stands.
        // Many (a paste, Split into Layers, a drag of thousands of bars)
        // are checked against the ids gathered once: checked one by one,
        // every action was compared with every other, which at a hundred
        // thousand actions froze the app for tens of seconds.
        case .insertActions(let actions):
            if actions.count > 8 {
                var taken = Set(p.actions.map(\.id))
                let layers = p.layerIDs
                for action in actions {
                    guard taken.insert(action.id).inserted else { throw EditorError.duplicateID(action.id) }
                    guard layers.contains(action.targetLayerID) else { throw EditorError.notFound(action.targetLayerID) }
                    guard action.fitsInTime else { throw EditorError.invalidValue }
                }
                p.actions.append(contentsOf: actions)
                break
            }
            for action in actions {
                guard !p.actions.contains(where: { $0.id == action.id }) else { throw EditorError.duplicateID(action.id) }
                guard p.layer(withID: action.targetLayerID) != nil else { throw EditorError.notFound(action.targetLayerID) }
                guard action.fitsInTime else { throw EditorError.invalidValue }
                p.actions.append(action)
            }

        case .updateActions(let actions):
            if actions.count > 8 {
                // A damaged file may repeat an id; the first place counts.
                let places = Dictionary(p.actions.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
                let layers = p.layerIDs
                for action in actions {
                    guard let i = places[action.id] else { throw EditorError.notFound(action.id) }
                    guard layers.contains(action.targetLayerID) else { throw EditorError.notFound(action.targetLayerID) }
                    guard action.fitsInTime else { throw EditorError.invalidValue }
                    p.actions[i] = action
                }
                break
            }
            for action in actions {
                guard let i = p.actions.firstIndex(where: { $0.id == action.id }) else { throw EditorError.notFound(action.id) }
                guard p.layer(withID: action.targetLayerID) != nil else { throw EditorError.notFound(action.targetLayerID) }
                guard action.fitsInTime else { throw EditorError.invalidValue }
                p.actions[i] = action
            }

        case .deleteActions(let ids):
            p.actions.removeAll { ids.contains($0.id) }
        case .setScenes(let scenes):
            p.scenes = scenes

        case .batch(let commands, _):
            for command in commands { try command.apply(into: &p) }
        }
    }

    private static func each(_ ids: Set<UUID>, in p: inout Project, _ change: (inout Layer) -> Void) throws {
        for id in ids {
            guard p.updateLayer(id, change) else { throw EditorError.notFound(id) }
        }
    }
}

public enum EditorError: Error, Equatable {
    case notFound(UUID)
    case duplicateID(UUID)
    case invalidMove
    case invalidValue
}

extension Action {
    /// Whether it starts and runs within `Composition.longest`.
    var fitsInTime: Bool {
        duration >= 0 && duration <= Composition.longest && abs(start) <= Composition.longest
    }
}
