import Foundation
import MotionModel
import MotionEvaluation

/// Grouping, ungrouping and restacking, worked out as commands.
public enum Arrangement {
    /// Puts layers that share a parent into a new group, in their current
    /// front-to-back order, where the frontmost of them was. The group's box
    /// is the union of theirs at `time`, so the group's anchor sits in their
    /// middle, and the children are moved into the group's own space so
    /// nothing moves on screen.
    public static func group(_ ids: [UUID], in project: Project, at time: Double, name: String) throws -> (EditorCommand, UUID) {
        let locations = ids.compactMap { id in project.location(of: id).map { (id, $0) } }
        guard !locations.isEmpty, locations.count == ids.count else { throw EditorError.invalidValue }
        let parentID = locations[0].1.parentID
        guard locations.allSatisfy({ $0.1.parentID == parentID }) else { throw EditorError.invalidMove }

        let ordered = locations.sorted { $0.1.index < $1.1.index }
        let layers = ordered.compactMap { project.layer(withID: $0.0) }
        let boxes = layers.compactMap { Self.box(of: $0, at: time) }
        guard let first = boxes.first else { throw EditorError.invalidValue }
        let bounds = boxes.dropFirst().reduce(first) { $0.union($1) }

        let origin = Vec2(bounds.minX, bounds.minY)
        let children = layers.map { $0.translated(by: Vec2(-origin.x, -origin.y)) }
        let group = LayerFactory.group(in: bounds, children: children, name: name, duration: project.composition.duration)

        let frontmost = ordered.last!.1.index
        let index = frontmost - (ordered.count - 1)
        return (.batch([.deleteLayers(Set(ids)), .insertLayers([group], parentID: parentID, index: index)],
                       name: "Group"), group.id)
    }

    /// Takes a group's children out into its parent, where the group was,
    /// carrying the group's transform and opacity over onto each of them.
    ///
    /// Exact for a group that is moved, turned or scaled evenly. A group
    /// stretched unevenly and turned cannot be reproduced child by child with
    /// a position, a rotation and a scale, so its children come out as close
    /// as those allow.
    public static func ungroup(_ id: UUID, in project: Project, at time: Double) throws -> (EditorCommand, [UUID]) {
        guard let group = project.layer(withID: id), group.isGroup,
              let location = project.location(of: id) else { throw EditorError.notFound(id) }
        let g = group.transform
        let groupTransform = Affine.layer(position: g.position.value(at: time), anchor: g.anchor.value(at: time),
                                          scale: g.scale.value(at: time), rotation: g.rotation.value(at: time))
        let rotation = g.rotation.value(at: time), scale = g.scale.value(at: time)
        let opacity = group.opacity.value(at: time)

        let children = group.children.map { child -> Layer in
            var c = child
            c.transform.position = remap(child.transform.position) { groupTransform.apply($0) }
            c.transform.rotation = remap(child.transform.rotation) { $0 + rotation }
            c.transform.scale = remap(child.transform.scale) { Vec2($0.x * scale.x, $0.y * scale.y) }
            c.opacity = remap(child.opacity) { $0 * opacity }
            return c
        }
        return (.batch([.deleteLayers([id]), .insertLayers(children, parentID: location.parentID, index: location.index)],
                       name: "Ungroup"), children.map(\.id))
    }

    public enum Direction: Sendable { case forward, backward, front, back }

    /// Moves layers one step or all the way through their siblings' stack.
    /// Layers are only restacked among siblings, never out of their group.
    public static func restack(_ ids: [UUID], _ direction: Direction, in project: Project) -> EditorCommand? {
        guard let first = ids.first, let location = project.location(of: first) else { return nil }
        let siblings = location.parentID.flatMap { project.layer(withID: $0)?.children } ?? project.layers
        let indices = ids.compactMap { id in siblings.firstIndex { $0.id == id } }
        guard indices.count == ids.count, !indices.isEmpty else { return nil }
        let remaining = siblings.count - ids.count
        let target: Int
        switch direction {
        case .front: target = remaining
        case .back: target = 0
        // Index among the siblings with the moving layers taken out.
        case .forward: target = min(indices.max()! - ids.count + 2, remaining)
        case .backward: target = max(indices.min()! - 1, 0)
        }
        return .moveLayers(ids, parentID: location.parentID, index: target)
    }

    /// The layer's box in its parent's space at `time`.
    public static func box(of layer: Layer, at time: Double) -> Box? {
        let t = layer.transform
        let transform = Affine.layer(position: t.position.value(at: time), anchor: t.anchor.value(at: time),
                                     scale: t.scale.value(at: time), rotation: t.rotation.value(at: time))
        return Box(around: Box(origin: .zero, size: layer.size.value(at: time)).corners.map(transform.apply))
    }

    private static func remap<V>(_ property: AnimatableProperty<V>, _ f: (V) -> V) -> AnimatableProperty<V> {
        AnimatableProperty(f(property.value), keyframes: property.keyframes.map { key in
            var k = key
            k.value = f(key.value)
            return k
        })
    }
}
