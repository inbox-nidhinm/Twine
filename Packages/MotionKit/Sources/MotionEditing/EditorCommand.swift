import Foundation
import MotionModel

/// Every way the interface is allowed to change a project.
///
/// The UI never writes to a `Project` directly. It describes the change as one
/// of these and hands it to `ProjectStore`, which applies it and records the
/// state before it for undo. Keeping the list short and explicit is what makes
/// "every change is undoable" something the compiler can check rather than a
/// habit: a view has no other route to the document.
///
/// Later milestones add keyframe, timing and property commands here.
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
        }
    }

    /// Applies the change. Throws, leaving `project` untouched, if the command
    /// refers to something that is not there, so a stale command can never
    /// half-apply.
    public func apply(to project: inout Project) throws {
        var draft = project
        try apply(into: &draft)
        project = draft
    }

    private func apply(into p: inout Project) throws {
        switch self {
        case .setComposition(let composition):
            guard composition.width > 0, composition.height > 0, composition.duration > 0 else {
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
            // A layer masked by something that no longer exists would render
            // unmasked anyway; dropping the reference keeps the file honest.
            let remaining = Set(p.allLayers.map(\.id))
            for layer in p.allLayers {
                if let mask = layer.mask, !remaining.contains(mask.layerID) {
                    p.updateLayer(layer.id) { $0.mask = nil }
                }
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
