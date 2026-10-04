import Foundation
import MotionModel
import MotionEvaluation

/// Grouping, ungrouping and restacking, worked out as commands.
public enum Arrangement {
    /// Puts layers that share a parent into a new group, or with `asFrame`
    /// a new frame, in their current front-to-back order, where the
    /// frontmost of them was. The box is the union of their designed boxes,
    /// so its anchor sits in their middle, and the children, with their
    /// actions, are moved into its own space so nothing moves on screen.
    /// They are moved rather than taken out and put back, so a mask naming
    /// one of them keeps it.
    public static func group(_ ids: [UUID], in project: Project, name: String,
                             asFrame: Bool = false) throws -> (EditorCommand, UUID) {
        let locations = ids.compactMap { id in project.location(of: id).map { (id, $0) } }
        guard !locations.isEmpty, locations.count == ids.count else { throw EditorError.invalidValue }
        let parentID = locations[0].1.parentID
        guard locations.allSatisfy({ $0.1.parentID == parentID }) else { throw EditorError.invalidMove }

        let ordered = locations.sorted { $0.1.index < $1.1.index }
        let layers = ordered.compactMap { project.layer(withID: $0.0) }
        let boxes = layers.compactMap { Self.box(of: $0) }
        guard let first = boxes.first else { throw EditorError.invalidValue }
        let bounds = boxes.dropFirst().reduce(first) { $0.union($1) }

        let shift = Vec2(-bounds.minX, -bounds.minY)
        let group = asFrame ? LayerFactory.frame(in: bounds, name: name) : LayerFactory.group(in: bounds, children: [], name: name)
        let moved = project.actions.filter { ids.contains($0.targetLayerID) }
            .map { $0.remapped(point: { $0 + shift }, vector: { $0 }) }

        // Just in front of the frontmost, so once they have moved in, the
        // group is where that one was.
        let index = ordered.last!.1.index + 1
        return (.batch([.insertLayers([group], parentID: parentID, index: index),
                        .moveLayers(ordered.map(\.0), parentID: group.id, index: nil),
                        .updateLayers(layers.map { $0.translated(by: shift) }),
                        .updateActions(moved)],
                       name: asFrame ? "Frame" : "Group"), group.id)
    }

    /// Moves layers into a frame drawn around them, in front of what it
    /// holds already and in their own order, with nothing moving on screen.
    /// Only for a frame that is not turned or scaled, as one just drawn is,
    /// so its children need only shift. Nil when there is nothing to move.
    public static func adopt(_ ids: [UUID], into frameID: UUID, in project: Project) -> EditorCommand? {
        guard !ids.isEmpty, let frame = project.layer(withID: frameID), frame.isGroup,
              frame.transform.rotation == 0, frame.transform.scale == .one else { return nil }
        let layers = ids.compactMap(project.layer(withID:))
        guard layers.count == ids.count else { return nil }
        let t = frame.transform
        let shift = Vec2(t.anchor.x - t.position.x, t.anchor.y - t.position.y)
        let moved = project.actions.filter { ids.contains($0.targetLayerID) }
            .map { $0.remapped(point: { $0 + shift }, vector: { $0 }) }
        return .batch([.moveLayers(ids, parentID: frameID, index: nil),
                       .updateLayers(layers.map { $0.translated(by: shift) }),
                       .updateActions(moved)], name: "Frame")
    }

    /// The layers beside `frameID` (sharing its parent, behind it) whose
    /// designed boxes lie wholly inside its own: what a frame drawn around
    /// them takes in, as in Figma.
    public static func enclosed(by frameID: UUID, in project: Project) -> [UUID] {
        guard let frame = project.layer(withID: frameID), let location = project.location(of: frameID),
              let box = Self.box(of: frame) else { return [] }
        let siblings = location.parentID.flatMap { project.layer(withID: $0)?.children } ?? project.layers
        return siblings.prefix(location.index).filter { layer in
            guard !layer.isLocked, let b = Self.box(of: layer) else { return false }
            return b.minX >= box.minX - 1e-6 && b.minY >= box.minY - 1e-6 && b.maxX <= box.maxX + 1e-6 && b.maxY <= box.maxY + 1e-6
        }.map(\.id)
    }

    /// Takes a group's children out into its parent, where the group was,
    /// carrying the group's designed transform and opacity over onto each of
    /// them and their actions. Actions on the group itself go with it.
    ///
    /// Exact for a group that is moved, turned or scaled evenly. A group
    /// stretched unevenly and turned cannot be reproduced child by child with
    /// a position, a rotation and a scale, so its children come out as close
    /// as those allow.
    public static func ungroup(_ id: UUID, in project: Project) throws -> (EditorCommand, [UUID]) {
        guard let group = project.layer(withID: id), group.isGroup,
              let location = project.location(of: id) else { throw EditorError.notFound(id) }
        let g = group.transform
        let groupTransform = Affine.layer(position: g.position, anchor: g.anchor, scale: g.scale, rotation: g.rotation, skew: g.skew)
        let rotation = g.rotation, scale = g.scale, opacity = group.opacity
        // A group flipped over (one scale negative) turns its children's
        // turns and slants the other way.
        let mirrored = scale.x * scale.y < 0

        let children = group.children.map { child -> Layer in
            var c = child
            c.transform.position = groupTransform.apply(child.transform.position)
            c.transform.rotation = mirrored ? rotation - child.transform.rotation : child.transform.rotation + rotation
            if mirrored { c.transform.skew = Vec2(-child.transform.skew.x, -child.transform.skew.y) }
            c.transform.scale = Vec2(child.transform.scale.x * scale.x, child.transform.scale.y * scale.y)
            c.opacity = child.opacity * opacity
            return c
        }
        let childIDs = Set(group.children.map(\.id))
        let moved = project.actions.filter { childIDs.contains($0.targetLayerID) }
            .map { $0.remapped(point: groupTransform.apply, vector: groupTransform.applyToVector,
                               angle: rotation, scale: scale, opacity: opacity, mirrored: mirrored) }
        return (.batch([.deleteLayers([id]), .insertLayers(children, parentID: location.parentID, index: location.index),
                        .updateActions(moved)],
                       name: "Ungroup"), children.map(\.id))
    }

    /// Layers moved into another group or frame, or out to the top level
    /// with a nil `parentID`, at `index` among its children, staying where
    /// they are on screen: their positions, turns and scales, and their
    /// actions, are carried from the old parent's space into the new one's.
    /// Exact when the groups on the way are moved, turned or scaled evenly,
    /// as ungrouping is.
    public static func move(_ ids: [UUID], to parentID: UUID?, index: Int?, in project: Project) -> EditorCommand {
        let movingSet = Set(ids)
        // A layer inside another moving one travels with it.
        let own = ids.filter { Set(project.ancestors(of: $0)).isDisjoint(with: movingSet) }
        var edited: [Layer] = []
        var actions: [Action] = []
        if let into = designWorld(of: parentID, in: project).inverted {
            for id in own {
                guard let layer = project.layer(withID: id), let location = project.location(of: id),
                      location.parentID != parentID else { continue }
                let m = designWorld(of: location.parentID, in: project).then(into)
                let (angle, scale) = turnAndScale(of: m)
                edited.append(carried(layer, by: m))
                actions += project.actions.filter { $0.targetLayerID == id }
                    .map { $0.remapped(point: m.apply, vector: m.applyToVector, angle: angle, scale: scale,
                                       mirrored: Self.mirrors(m)) }
            }
        }
        var commands: [EditorCommand] = [.moveLayers(ids, parentID: parentID, index: index)]
        if !edited.isEmpty { commands.append(.updateLayers(edited)) }
        if !actions.isEmpty { commands.append(.updateActions(actions)) }
        return .batch(commands, name: ids.count == 1 ? "Move Layer" : "Move Layers")
    }

    /// A layer made in composition space, as the tools make them, carried
    /// into a group's or frame's own space, so it lands where it was drawn.
    public static func placed(_ layer: Layer, into parentID: UUID?, in project: Project) -> Layer {
        guard let parentID, let inverse = designWorld(of: parentID, in: project).inverted else { return layer }
        return carried(layer, by: inverse)
    }

    /// The same, into a parent drawn by `parentWorld` (its own space into
    /// the composition's): in Animate, the parent as it is at the playhead,
    /// so a layer drawn into a moving frame lands where it was drawn.
    public static func placed(_ layer: Layer, into parentID: UUID?, parentWorld: Affine?) -> Layer {
        guard parentID != nil, let inverse = parentWorld?.inverted else { return layer }
        return carried(layer, by: inverse)
    }

    /// A layer's place, turn and scale carried by a transform between two
    /// parents' spaces.
    private static func carried(_ layer: Layer, by m: Affine) -> Layer {
        let (angle, scale) = turnAndScale(of: m)
        var l = layer
        l.transform.position = m.apply(layer.transform.position)
        if mirrors(m) {
            l.transform.rotation = angle - layer.transform.rotation
            l.transform.skew = Vec2(-layer.transform.skew.x, -layer.transform.skew.y)
        } else {
            l.transform.rotation = layer.transform.rotation + angle
        }
        l.transform.scale = Vec2(layer.transform.scale.x * scale.x, layer.transform.scale.y * scale.y)
        return l
    }

    /// Whether `m` flips things over, as a group with one scale negative does.
    private static func mirrors(_ m: Affine) -> Bool { m.a * m.d - m.b * m.c < 0 }

    /// The turn and scale of `m`, the height's scale negative when it flips
    /// things over, so a flipped layer carried through it stays flipped.
    private static func turnAndScale(of m: Affine) -> (angle: Double, scale: Vec2) {
        (atan2(m.b, m.a) * 180 / .pi, Vec2(hypot(m.a, m.b), (mirrors(m) ? -1 : 1) * hypot(m.c, m.d)))
    }

    /// From a group's own space into the composition's, as designed; the
    /// identity for the top level.
    static func designWorld(of id: UUID?, in project: Project) -> Affine {
        guard let id, let layer = project.layer(withID: id) else { return .identity }
        let t = layer.transform
        return Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
            .then(designWorld(of: project.location(of: id)?.parentID, in: project))
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

    /// The layer's designed box in its parent's space.
    public static func box(of layer: Layer) -> Box? {
        let t = layer.transform
        let transform = Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
        return Box(around: Box(origin: .zero, size: layer.size).corners.map(transform.apply))
    }
}
