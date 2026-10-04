import Foundation
import MotionModel
import MotionEvaluation

/// Masks as projects kept them until 4 October 2026, made into Figma's
/// (the user's choice): each masked layer named its mask, which could sit
/// anywhere; now a mask masks the layers in front of it in its group. As a
/// project opens, each old mask goes into a Mask group with the layers it
/// masked, at the bottom, marked as a mask. Layers it masked in different
/// places get a mask group each, with a copy of the mask (and its actions)
/// in all but the first. Nothing moves on screen, but layers that sat
/// between masked ones may end up behind or in front of the new group, as
/// grouping does, and an inverted mask is no longer inverted (Figma has no
/// such mask).
public enum MaskConversion {
    public static let groupName = "Mask group"

    public static func converted(_ project: Project) -> Project {
        guard project.hasLegacyMasks else { return project }
        var p = project
        // Each mask with the layers it masked, in the order they come.
        var masks: [UUID] = []
        var uses: [UUID: [UUID]] = [:]
        p.forEachLayer { layer in
            guard let mask = layer.legacyMask?.layerID, mask != layer.id else { return }
            if uses[mask] == nil { masks.append(mask) }
            uses[mask, default: []].append(layer.id)
        }
        p.layers = clearingLegacy(p.layers)
        for maskID in masks {
            guard let mask = p.layer(withID: maskID), mask.canMask, !mask.isMask else { continue }
            // A mask's own mask was never followed.
            var places: [(parent: UUID?, ids: [UUID])] = []
            for id in uses[maskID] ?? [] {
                guard let location = p.location(of: id) else { continue }
                if let i = places.firstIndex(where: { $0.parent == location.parentID }) {
                    places[i].ids.append(id)
                } else {
                    places.append((location.parentID, [id]))
                }
            }
            for (i, place) in places.enumerated() {
                if let source = i == 0 ? maskID : copy(of: maskID, in: &p) {
                    _ = maskGroup(mask: source, over: place.ids, in: place.parent, project: &p)
                }
            }
        }
        return p
    }

    private static func clearingLegacy(_ layers: [Layer]) -> [Layer] {
        layers.map { layer in
            var l = layer
            l.legacyMask = nil
            if l.isGroup { l.children = clearingLegacy(l.children) }
            return l
        }
    }

    /// A copy of the mask beside it, with copies of its actions.
    private static func copy(of maskID: UUID, in p: inout Project) -> UUID? {
        guard let mask = p.layer(withID: maskID), let location = p.location(of: maskID) else { return nil }
        var map: [UUID: UUID] = [:]
        let copy = mask.duplicated(recordingIDs: &map)
        let actions = p.actionCopyPairs(for: map).map(\.copy)
        guard (try? EditorCommand.batch([.insertLayers([copy], parentID: location.parentID, index: location.index),
                                         .insertActions(actions)], name: "Copy Mask").apply(to: &p)) != nil else { return nil }
        return copy.id
    }

    /// The mask brought beside the layers (staying where it is on screen),
    /// grouped with them at the bottom of the group, and marked a mask.
    private static func maskGroup(mask: UUID, over ids: [UUID], in parent: UUID?, project p: inout Project) -> Bool {
        if p.location(of: mask)?.parentID != parent {
            let backmost = ids.compactMap { p.location(of: $0)?.index }.min()
            guard (try? Arrangement.move([mask], to: parent, index: backmost, in: p).apply(to: &p)) != nil else { return false }
        }
        guard let (grouping, groupID) = try? Arrangement.group([mask] + ids, in: p, name: groupName),
              (try? grouping.apply(to: &p)) != nil,
              (try? EditorCommand.moveLayers([mask], parentID: groupID, index: 0).apply(to: &p)) != nil else { return false }
        _ = p.updateLayer(mask) { $0.isMask = true }
        return true
    }
}
