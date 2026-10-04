import Foundation

/// Masks as Figma has them (4 October 2026): a layer marked `isMask` masks
/// the layers in front of it in the same group or frame, up to the next
/// mask.
extension Project {
    /// Every layer that is a mask.
    public var maskIDs: Set<UUID> {
        var out = Set<UUID>()
        forEachLayer { if $0.isMask { out.insert($0.id) } }
        return out
    }

    /// Whether any layer still carries a mask the way older projects kept
    /// them, for `Masks.convertingLegacy`.
    public var hasLegacyMasks: Bool {
        var found = false
        forEachLayer { if $0.legacyMask != nil { found = true } }
        return found
    }
}

extension Layer {
    /// Whether the layer can be a mask: it draws by itself. A group draws
    /// only through its children, which a mask cannot, and a sound draws
    /// nothing.
    public var canMask: Bool {
        switch content {
        case .shape, .text, .video: true
        case .group, .audio: false
        }
    }
}
