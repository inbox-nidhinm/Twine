import Foundation

extension Layer {
    /// A copy with fresh ids for the layer, everything inside it, and its
    /// fills, strokes and effects. A mask that pointed at a layer inside the
    /// copy points at that layer's copy; one that pointed outside is kept.
    ///
    /// This is the only way a layer gets a new id: a layer's own id never
    /// changes, so copying is always making a new layer.
    public func duplicated() -> Layer {
        var map: [UUID: UUID] = [:]
        var copy = copied(into: &map)
        copy.remapMasks(map)
        return copy
    }

    private func copied(into map: inout [UUID: UUID]) -> Layer {
        let newID = UUID()
        map[id] = newID
        var copy = Layer(id: newID, name: name, content: content, size: size.value, position: .zero,
                         inPoint: inPoint, outPoint: outPoint)
        copy.isVisible = isVisible
        copy.isLocked = isLocked
        copy.isSoloed = isSoloed
        copy.transform = transform
        copy.size = size
        copy.opacity = opacity
        copy.effects = effects.map { Effect(isEnabled: $0.isEnabled, kind: $0.kind) }
        copy.mask = mask
        switch content {
        case .shape(var shape):
            shape.fills = shape.fills.map { Fill(isEnabled: $0.isEnabled, paint: $0.paint) }
            shape.strokes = shape.strokes.map { $0.withNewID() }
            copy.content = .shape(shape)
        case .group(var group):
            group.children = group.children.map { $0.copied(into: &map) }
            copy.content = .group(group)
        default:
            break
        }
        return copy
    }

    private mutating func remapMasks(_ map: [UUID: UUID]) {
        if let m = mask, let moved = map[m.layerID] { mask?.layerID = moved }
        if case .group(var group) = content {
            for i in group.children.indices { group.children[i].remapMasks(map) }
            content = .group(group)
        }
    }
}

extension Stroke {
    /// The same stroke under a new id.
    public func withNewID() -> Stroke {
        var copy = Stroke(paint: paint, width: 0, alignment: alignment, cap: cap, join: join,
                          dashPattern: dashPattern, dashOffset: dashOffset)
        copy.isEnabled = isEnabled
        copy.width = width
        copy.trimStart = trimStart
        copy.trimEnd = trimEnd
        return copy
    }
}
