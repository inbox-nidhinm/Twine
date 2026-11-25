import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation

/// Several selected layers resized or turned together from the box round
/// them all, and a layer dropped into or out of a frame (26 November 2026).
extension CanvasNSView {
    /// The selected layers that a drag on the box round them changes: the
    /// outermost of them, unlocked, and none of them tilted or a template's
    /// slot. Empty unless there are several, in Design.
    var manyLayers: [Layer] {
        guard !animating, selection.count > 1, let controller, let scene else { return [] }
        let slots = controller.project.templateSlotIDs
        let layers = controller.topmost(controller.selectedLayers).filter { !controller.isLocked($0.id) && !slots.contains($0.id) }
        guard layers.count > 1, !layers.contains(where: { isTilted($0.id, in: scene) }) else { return [] }
        return layers
    }

    /// The box round `layers` as they show, in the composition's space.
    func box(around layers: [Layer]) -> Box? {
        guard let scene else { return nil }
        return Box(around: layers.flatMap { scene.worldCorners(of: $0.id) ?? [] })
    }

    /// A box's corners in the view, from its top-left clockwise, as the
    /// handles are laid out.
    func viewCorners(of box: Box) -> [CGPoint] {
        [Vec2(box.minX, box.minY), Vec2(box.maxX, box.minY), Vec2(box.maxX, box.maxY), Vec2(box.minX, box.maxY)]
            .map(compositionToView)
    }

    /// A press on one of the box's handles or just past a corner begins a
    /// resize or a turn of all the layers.
    func beginManyEdit(at viewPoint: CGPoint, point: Vec2) -> Bool {
        let layers = manyLayers
        guard let controller, let box = box(around: layers), box.maxX - box.minX > 0, box.maxY - box.minY > 0 else { return false }
        let view = viewCorners(of: box)
        if let handle = CanvasHandles.handle(at: viewPoint, box: view, isLine: false) {
            snapTargets = []
            drag = .resizeMany(CanvasDrag.Many(originals: layers, box: box, handle: handle, start: point))
            controller.begin("Resize")
            return true
        }
        if CanvasHandles.isRotateZone(viewPoint, box: view) {
            drag = .rotateMany(CanvasDrag.Many(originals: layers, box: box, handle: 0, start: point))
            controller.begin("Rotate")
            return true
        }
        return false
    }

    /// The layers as the box, dragged by a handle to `pointer`, leaves
    /// them: each keeps its place within the box and grows as the box
    /// does. A layer lying square to the box takes its width and height
    /// each their own way; one turned between takes one size for both, as
    /// a turned shape cannot be stretched along the box's sides.
    func resizedMany(_ many: CanvasDrag.Many, pointer: Vec2, keepAspect: Bool, fromCenter: Bool) -> [Layer] {
        // A plain rectangle stands in for the box, so the handles behave
        // exactly as one layer's do.
        let stand = LayerFactory.shape(.rectangle, in: many.box, name: "")
        let grown = CanvasGeometry.resized(stand, handle: many.handle, pointer: pointer, keepAspect: keepAspect, fromCenter: fromCenter)
        let to = grown.transform
        let now = Affine.layer(position: to.position, anchor: to.anchor, scale: to.scale, rotation: to.rotation, skew: to.skew)
        let origin = now.apply(.zero)
        let oldWidth = many.box.maxX - many.box.minX, oldHeight = many.box.maxY - many.box.minY
        let sx = grown.size.width / oldWidth, sy = grown.size.height / oldHeight
        return many.originals.map { layer in
            let parent = parentWorld(of: layer.id)
            let world = local(layer).then(parent)
            let centre = world.apply(Vec2(layer.size.width / 2, layer.size.height / 2))
            let target = Vec2(origin.x + (centre.x - many.box.minX) * sx, origin.y + (centre.y - many.box.minY) * sy)
            // Which way the layer's own width runs across the box.
            let across = world.applyToVector(Vec2(1, 0))
            let length = hypot(across.x, across.y)
            let level = length > 0 ? abs(across.x) / length : 1
            let (kw, kh): (Double, Double)
            if level > 0.92 { (kw, kh) = (sx, sy) } else if level < 0.38 { (kw, kh) = (sy, sx) } else {
                let both = (sx * sy).squareRoot()
                (kw, kh) = (both, both)
            }
            var edited = layer
            if layer.isGroup && !layer.isFrame {
                edited.transform.scale = Vec2(layer.transform.scale.x * kw, layer.transform.scale.y * kh)
            } else if layer.isText {
                // A text keeps its letters' size: its box takes the width.
                if abs(kw - 1) > 1e-6 { edited = layer.resized(width: max(layer.size.width * kw, 1)) }
            } else {
                edited = layer.resized(width: max(layer.size.width * kw, 1),
                                       height: layer.size.height == 0 ? 0 : max(layer.size.height * kh, 1))
            }
            return placing(edited, centreAt: target, parent: parent)
        }
    }

    /// The layers turned about the middle of the box round them, by the
    /// angle the pointer has gone round it since the press.
    func rotatedMany(_ many: CanvasDrag.Many, pointer: Vec2, stepped: Bool) -> [Layer] {
        let pivot = Vec2((many.box.minX + many.box.maxX) / 2, (many.box.minY + many.box.maxY) / 2)
        var angle = atan2(pointer.y - pivot.y, pointer.x - pivot.x) - atan2(many.start.y - pivot.y, many.start.x - pivot.x)
        if stepped { angle = (angle / (.pi / 12)).rounded() * (.pi / 12) }
        let cosine = cos(angle), sine = sin(angle)
        return many.originals.map { layer in
            let parent = parentWorld(of: layer.id)
            let centre = local(layer).then(parent).apply(Vec2(layer.size.width / 2, layer.size.height / 2))
            let dx = centre.x - pivot.x, dy = centre.y - pivot.y
            let target = Vec2(pivot.x + dx * cosine - dy * sine, pivot.y + dx * sine + dy * cosine)
            var edited = layer
            // Inside a mirrored group or frame its own turn shows the
            // other way round.
            edited.transform.rotation += (parent.determinant < 0 ? -1 : 1) * angle * 180 / .pi
            return placing(edited, centreAt: target, parent: parent)
        }
    }

    private func local(_ layer: Layer) -> Affine {
        let t = layer.transform
        return Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
    }

    /// The space of what holds a layer, into the composition's.
    private func parentWorld(of id: UUID) -> Affine {
        guard let parent = project?.location(of: id)?.parentID else { return .identity }
        return scene?.worldTransform(of: parent) ?? .identity
    }

    /// `layer` moved so the middle of its box shows at `target` in the
    /// composition.
    private func placing(_ layer: Layer, centreAt target: Vec2, parent: Affine) -> Layer {
        guard let inverse = parent.inverted else { return layer }
        let centre = local(layer).then(parent).apply(Vec2(layer.size.width / 2, layer.size.height / 2))
        var moved = layer
        moved.transform.position = layer.transform.position + inverse.applyToVector(target - centre)
        return moved
    }

    // MARK: Into and out of frames

    /// The frame a dragged layer would be dropped into: the front one
    /// under the pointer that is not being dragged, nor inside what is.
    /// Nil over none, which is the top level.
    func dropFrame(at point: Vec2, moving: [Layer]) -> UUID? {
        guard let scene, let controller else { return nil }
        let project = controller.project
        let dragged = Set(moving.map(\.id))
        let locked = project.lockedLayers
        let slots = project.templateSlotIDs
        for resolved in scene.layers.reversed() where resolved.frame != nil {
            let id = resolved.id
            guard !dragged.contains(id), !locked.contains(id), !slots.contains(id),
                  project.layer(withID: id)?.isTemplate == false,
                  !project.ancestors(of: id).contains(where: dragged.contains),
                  let inverse = scene.worldTransform(of: id)?.inverted,
                  CGRect(origin: .zero, size: resolved.size.cg).contains(inverse.apply(point).cg) else { continue }
            return id
        }
        return nil
    }

    /// Where a move would take its layers, when that is somewhere new:
    /// `.some(nil)` is out to the top level, nil is where they are.
    func dropChange(at point: Vec2, moving: [Layer]) -> UUID?? {
        guard let project, !moving.isEmpty else { return nil }
        let target = dropFrame(at: point, moving: moving)
        let parents = Set(moving.map { project.location(of: $0.id)?.parentID })
        // In a group that is not a frame, a layer stays the group's: it
        // was reached on purpose, and dragging it about should not lose it.
        for parent in parents {
            if let parent, project.layer(withID: parent)?.isFrame != true { return nil }
        }
        return parents == [target] ? nil : .some(target)
    }

    // MARK: Distances

    /// With Option held and the pointer over another layer, how far the
    /// selection is from it, as in Figma: across the gap between them each
    /// way they are apart, or from edge to matching edge where they overlap.
    func measureMarks() -> [CanvasOverlay.GapMark] {
        guard measuring, drag == nil, !selection.isEmpty, let scene, let controller,
              let over = controller.editor.hoveredLayer, !selection.contains(over),
              let from = Box(around: selection.flatMap({ scene.worldCorners(of: $0) ?? [] })),
              let to = scene.worldCorners(of: over).flatMap({ Box(around: $0) }) else { return [] }
        var marks: [CanvasOverlay.GapMark] = []
        func mark(_ a: Vec2, _ b: Vec2) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length >= 0.5 else { return }
            marks.append(CanvasOverlay.GapMark(from: compositionToView(a), to: compositionToView(b),
                                               label: UnitField.trimmed(length, 1)))
        }
        // Level with the middle of whatever the two share, or of the selection.
        func middle(_ lowA: Double, _ highA: Double, _ lowB: Double, _ highB: Double) -> Double {
            let low = max(lowA, lowB), high = min(highA, highB)
            return low <= high ? (low + high) / 2 : (lowA + highA) / 2
        }
        let y = middle(from.minY, from.maxY, to.minY, to.maxY)
        if from.maxX <= to.minX {
            mark(Vec2(from.maxX, y), Vec2(to.minX, y))
        } else if to.maxX <= from.minX {
            mark(Vec2(to.maxX, y), Vec2(from.minX, y))
        } else {
            mark(Vec2(min(from.minX, to.minX), y), Vec2(max(from.minX, to.minX), y))
            mark(Vec2(min(from.maxX, to.maxX), y), Vec2(max(from.maxX, to.maxX), y))
        }
        let x = middle(from.minX, from.maxX, to.minX, to.maxX)
        if from.maxY <= to.minY {
            mark(Vec2(x, from.maxY), Vec2(x, to.minY))
        } else if to.maxY <= from.minY {
            mark(Vec2(x, to.maxY), Vec2(x, from.minY))
        } else {
            mark(Vec2(x, min(from.minY, to.minY)), Vec2(x, max(from.minY, to.minY)))
            mark(Vec2(x, min(from.maxY, to.maxY)), Vec2(x, max(from.maxY, to.maxY)))
        }
        return marks
    }

    // MARK: Quick keys

    /// Keys that act at once on the selection or the view, as Figma's do
    /// (26 November 2026): number keys set opacity, ] and [ send to the
    /// front and back, I picks a colour from the screen, Shift-X swaps
    /// fill and stroke, Option-/ and Shift-/ take fills and strokes away,
    /// and Shift-1 and Shift-0 fit the view and show it at actual size.
    /// What changes a layer's design works in Design only.
    func quickKeyDown(_ event: NSEvent, _ controller: EditorController) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        let shift = event.modifierFlags.contains(.shift)
        // The slash key, by its place: Option and Shift change what it types.
        if event.keyCode == 44, !animating {
            if flags == [.option], !shift {
                controller.removePaints(fills: true)
                return true
            }
            if flags.isEmpty, shift {
                controller.removePaints(fills: false)
                return true
            }
        }
        guard flags.isEmpty else { return false }
        if shift {
            // By their places too, as Shift turns 1 and 0 into ! and ).
            if event.keyCode == 18 {
                fitToWindow(animated: true)
                return true
            }
            if event.keyCode == 29 {
                zoomToActualSize()
                return true
            }
            if !animating, event.charactersIgnoringModifiers?.lowercased() == "x" {
                controller.swapFillAndStroke()
                return true
            }
            return false
        }
        guard let key = event.charactersIgnoringModifiers else { return false }
        switch key {
        case "]":
            controller.restack(.front)
            return true
        case "[":
            controller.restack(.back)
            return true
        case "i" where !animating:
            controller.pickFillFromScreen()
            return true
        default:
            break
        }
        if !animating, !selection.isEmpty, key.count == 1, let digit = Int(key) {
            // One digit is tens of a percent (4 is 40%, 0 is 100%); a
            // second straight after makes it exact (4 then 5 is 45%, 0
            // then 0 is 0%).
            let value: Int
            if let last = opacityKey, event.timestamp - last.at < 0.6 {
                value = last.digit * 10 + digit
                opacityKey = nil
            } else {
                value = digit == 0 ? 100 : digit * 10
                opacityKey = (digit, event.timestamp)
            }
            controller.setOpacity(Double(value) / 100)
            return true
        }
        return false
    }
}
