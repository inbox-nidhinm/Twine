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
        return duplicated(recordingIDs: &map)
    }

    /// The same, adding each old id and its copy's id to `map`, so whatever
    /// refers to the originals (their actions) can be copied across too.
    public func duplicated(recordingIDs map: inout [UUID: UUID]) -> Layer {
        var local: [UUID: UUID] = [:]
        var copy = copied(into: &local)
        copy.remapMasks(local)
        map.merge(local) { $1 }
        return copy
    }

    private func copied(into map: inout [UUID: UUID]) -> Layer {
        let newID = UUID()
        map[id] = newID
        var copy = withID(newID)
        copy.effects = effects.map { Effect(isEnabled: $0.isEnabled, kind: $0.kind) }
        switch content {
        case .shape(var shape):
            shape.fills = shape.fills.map { Fill(isEnabled: $0.isEnabled, paint: $0.paint) }
            shape.strokes = shape.strokes.map { $0.withNewID() }
            copy.content = .shape(shape)
        case .group(var group):
            group.children = group.children.map { $0.copied(into: &map) }
            if var frame = group.frame {
                frame.fills = frame.fills.map { Fill(isEnabled: $0.isEnabled, paint: $0.paint) }
                frame.strokes = frame.strokes.map { $0.withNewID() }
                group.frame = frame
            }
            copy.content = .group(group)
        case .text(var text):
            text.stroke = text.stroke?.withNewID()
            copy.content = .text(text)
        default:
            break
        }
        return copy
    }

    /// The layer with every mask inside it that names a layer in `map`
    /// pointing at that layer's copy instead: for layers copied one by one
    /// together, such as a picture and its mask selected side by side, so
    /// each copy is masked by the other's copy, not the original.
    public func remappingMasks(_ map: [UUID: UUID]) -> Layer {
        var copy = self
        copy.remapMasks(map)
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
