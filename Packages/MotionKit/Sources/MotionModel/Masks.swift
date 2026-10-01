import Foundation

/// Which layers mask which.
extension Project {
    /// Every layer used as another layer's mask.
    public var maskSourceIDs: Set<UUID> {
        var out = Set<UUID>()
        forEachLayer { if let mask = $0.mask { out.insert(mask.layerID) } }
        return out
    }

    /// The layers `id` can be masked by, back to front: anything that draws
    /// by itself (not a group, not a sound), other than the layer itself,
    /// the groups it sits in (a mask stops drawing, and would take the layer
    /// with it), and a layer it already masks. A layer inside a masked group
    /// is fine: that is how Figma masks a group.
    public func maskCandidates(for id: UUID) -> [Layer] {
        let blocked = Set(ancestors(of: id) + [id])
        var out: [Layer] = []
        forEachLayer { if Self.canMask($0, id, blocked: blocked) { out.append($0) } }
        return out
    }

    /// Whether `maskCandidates(for:)` has any, found without listing them,
    /// for a button shown on every redraw.
    public func hasMaskCandidates(for id: UUID) -> Bool {
        let blocked = Set(ancestors(of: id) + [id])
        func look(in list: [Layer]) -> Bool {
            for i in list.indices {
                if Self.canMask(list[i], id, blocked: blocked) { return true }
                if list[i].isGroup, look(in: list[i].children) { return true }
            }
            return false
        }
        return look(in: layers)
    }

    private static func canMask(_ layer: Layer, _ id: UUID, blocked: Set<UUID>) -> Bool {
        guard !blocked.contains(layer.id), layer.mask?.layerID != id else { return false }
        switch layer.content {
        case .group, .audio: return false
        case .shape, .text, .video: return true
        }
    }
}
