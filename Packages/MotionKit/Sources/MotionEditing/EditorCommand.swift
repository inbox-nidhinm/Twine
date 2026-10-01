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
        // Likewise a mask naming a layer that is not there. Checked once
        // the whole command is done, so a batch that takes a layer out and
        // puts it back, as ungrouping does, keeps the masks that name it,
        // and layers pasted from another project drop masks they left behind.
        var unmasked: [UUID] = []
        // A text box is always the size of its words, whatever changed them.
        var refitted: [Layer] = []
        draft.forEachLayer { layer in
            if let mask = layer.mask, !remaining.contains(mask.layerID) { unmasked.append(layer.id) }
            if layer.isText {
                let fitted = layer.fittedText()
                if fitted != layer { refitted.append(fitted) }
            }
        }
        for id in unmasked { draft.updateLayer(id) { $0.mask = nil } }
        for fitted in refitted {
            _ = draft.updateLayer(fitted.id) { layer in
                // Fitted again, as it may have just lost its mask.
                layer = layer.fittedText()
            }
        }
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
            // rather than on its own.
            let ordered = p.allLayers.map(\.id).filter {
                ids.contains($0) && Set(p.ancestors(of: $0)).isDisjoint(with: ids)
            }
            var moving: [Layer] = []
            for id in ordered {
                guard let removed = p.removeLayer(id) else { throw EditorError.notFound(id) }
                moving.append(removed)
            }
            var at = index
            for layer in moving {
                p.insertLayer(layer, parentID: parentID, at: at)
                at = at.map { $0 + 1 }
            }

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
            for layer in layers {
                guard p.updateLayer(layer.id, { $0 = layer }) else { throw EditorError.notFound(layer.id) }
            }

        case .addMedia(let asset):
            guard !p.media.contains(where: { $0.id == asset.id }) else { throw EditorError.duplicateID(asset.id) }
            p.media.append(asset)

        case .insertActions(let actions):
            for action in actions {
                guard !p.actions.contains(where: { $0.id == action.id }) else { throw EditorError.duplicateID(action.id) }
                guard p.layer(withID: action.targetLayerID) != nil else { throw EditorError.notFound(action.targetLayerID) }
                guard action.fitsInTime else { throw EditorError.invalidValue }
                p.actions.append(action)
            }

        case .updateActions(let actions):
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
