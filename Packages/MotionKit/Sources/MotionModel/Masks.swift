import Foundation

/// Which layers mask which.
extension Project {
    /// Every layer used as another layer's mask.
    public var maskSourceIDs: Set<UUID> {
        Set(allLayers.compactMap { $0.mask?.layerID })
    }

    /// The layers `id` can be masked by, back to front: anything that draws
    /// by itself (not a group, not a sound), other than the layer itself,
    /// the groups it sits in (a mask stops drawing, and would take the layer
    /// with it), and a layer it already masks. A layer inside a masked group
    /// is fine: that is how Figma masks a group.
    public func maskCandidates(for id: UUID) -> [Layer] {
        let blocked = Set(ancestors(of: id) + [id])
        return allLayers.filter { layer in
            guard !blocked.contains(layer.id), layer.mask?.layerID != id else { return false }
            switch layer.content {
            case .group, .audio: return false
            case .shape, .text, .image, .video: return true
            }
        }
    }
}
