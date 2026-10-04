import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation

/// A gradient's line on the canvas, as Figma shows it (4 October 2026):
/// shown whenever the one layer selected in Design has a gradient, its top
/// fill's or else its stroke's (or the paint `EditorModel.gradient` names),
/// over the layer's own handles, which it wins where they meet (the
/// user's choice, a switch for it at first). Drag either end to turn and
/// stretch it (Shift keeps the angle to steps of 15°), the line to move
/// it, a stop's dot to slide the stop along; a click on the line adds a
/// stop there. Delete removes the picked stop (a press anywhere else lets
/// it go, so Delete deletes the layer again). Escape hides the line until
/// the selection changes, giving back the handles under it; with Command
/// the anchor moves as usual. A radial or angular gradient's line runs
/// from its centre to its edge, its circle drawn.
extension CanvasNSView {
    /// The gradient being edited and where it is, when it can be shown.
    struct GradientPlace {
        let edit: GradientEdit
        let layer: Layer
        let paint: Paint
        let gradient: MotionModel.Gradient
        /// The layer's own size: a gradient's points are fractions of it.
        let size: Size2
        /// From the layer's own pixels into the composition, and back.
        let world: Affine
        let toLocal: Affine
        /// The ends and each stop, in view points.
        let start: CGPoint
        let end: CGPoint
        let stops: [CGPoint]

        func local(_ unit: Vec2) -> Vec2 { Vec2(unit.x * size.width, unit.y * size.height) }
        func unit(_ local: Vec2) -> Vec2 { Vec2(local.x / size.width, local.y / size.height) }
    }

    /// The selected layer's gradient: the paint named in `EditorModel.gradient`,
    /// else its top fill's, else its first stroke's.
    private func gradientEdit() -> GradientEdit? {
        guard let controller, selection.count == 1, let id = selection.first,
              let layer = controller.project.layer(withID: id), let look = layer.look else { return nil }
        if let edit = controller.editor.gradient, edit.layerID == id, layer.paint(at: edit.slot)?.gradient != nil { return edit }
        if let top = look.topFillIndex, look.fills[top].paint.gradient != nil { return GradientEdit(layerID: id, slot: .fill(top)) }
        if look.strokes.first?.paint.gradient != nil { return GradientEdit(layerID: id, slot: .stroke(0)) }
        return nil
    }

    func gradientPlace() -> GradientPlace? {
        guard let controller, let scene, !controller.editor.hidesGradient, let edit = gradientEdit(), !animating,
              tool == .select, textSession == nil, pathSession == nil, cropSession == nil,
              !controller.isLocked(edit.layerID), !isTilted(edit.layerID, in: scene),
              let layer = controller.project.layer(withID: edit.layerID), let paint = layer.paint(at: edit.slot),
              let gradient = paint.gradient, let resolved = scene.layer(edit.layerID),
              resolved.size.width > 0, resolved.size.height > 0,
              let world = scene.worldTransform(of: edit.layerID), let toLocal = world.inverted else { return nil }
        let size = resolved.size
        func view(_ unit: Vec2) -> CGPoint { compositionToView(world.apply(Vec2(unit.x * size.width, unit.y * size.height))) }
        let start = view(gradient.start), end = view(gradient.end)
        let stops = gradient.stops.map { stop in
            CGPoint(x: start.x + (end.x - start.x) * stop.position, y: start.y + (end.y - start.y) * stop.position)
        }
        return GradientPlace(edit: edit, layer: layer, paint: paint, gradient: gradient, size: size, world: world,
                             toLocal: toLocal, start: start, end: end, stops: stops)
    }

    func gradientMarks() -> CanvasOverlay.GradientMarks? {
        guard let place = gradientPlace() else { return nil }
        var circle: CGPath?
        if place.paint.isCentred {
            // The circle in the layer's own pixels, drawn through its
            // transform, so a scaled or turned layer's is too.
            let c = place.local(place.gradient.start), e = place.local(place.gradient.end)
            let r = hypot(e.x - c.x, e.y - c.y)
            let o = compositionToView(.zero), t = place.world
            var toView = CGAffineTransform(a: t.a * zoom, b: t.b * zoom, c: t.c * zoom, d: t.d * zoom,
                                           tx: t.tx * zoom + o.x, ty: t.ty * zoom + o.y)
            circle = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: &toView)
        }
        return CanvasOverlay.GradientMarks(
            start: place.start, end: place.end, circle: circle,
            stops: place.gradient.stops.indices.map { i in
                (place.stops[i], place.gradient.stops[i].color.cgColor, i == place.edit.stop)
            })
    }

    // MARK: Pointer

    /// A press while a gradient's line shows: on an end, a stop, or the
    /// line. Anywhere else, or with Command (the anchor), the picked stop
    /// is let go and the press carries on.
    func gradientMouseDown(_ event: NSEvent, at point: Vec2, viewPoint: CGPoint) -> Bool {
        guard let place = gradientPlace(), let controller else { return false }
        guard !event.modifierFlags.contains(.command) else {
            controller.editor.gradient?.stop = nil
            return false
        }
        func distance(_ p: CGPoint) -> CGFloat { hypot(p.x - viewPoint.x, p.y - viewPoint.y) }
        let part: CanvasDrag.GradientDrag.Part
        if distance(place.end) <= CanvasHandles.hitRadius {
            part = .end
        } else if distance(place.start) <= CanvasHandles.hitRadius {
            part = .start
        } else if let stop = place.stops.indices
            .filter({ distance(place.stops[$0]) <= CanvasHandles.hitRadius })
            .min(by: { distance(place.stops[$0]) < distance(place.stops[$1]) }) {
            part = .stop(stop)
        } else if Self.distance(from: viewPoint, toSegment: place.start, place.end) <= CanvasHandles.hitRadius {
            part = .line
        } else {
            controller.editor.gradient?.stop = nil
            return false
        }
        if case .stop(let i) = part { controller.editor.gradient = GradientEdit(layerID: place.edit.layerID, slot: place.edit.slot, stop: i) }
        drag = .gradient(CanvasDrag.GradientDrag(part: part, place: place, start: point, startView: viewPoint))
        return true
    }

    func gradientMouseDragged(_ edit: CanvasDrag.GradientDrag, point: Vec2, viewPoint: CGPoint, event: NSEvent) {
        guard let controller else { return }
        var edit = edit
        if !edit.began {
            // A wobble of a click is not a drag.
            guard hypot(viewPoint.x - edit.startView.x, viewPoint.y - edit.startView.y) > CanvasHandles.clickReach else { return }
            controller.begin(edit.part.isStop ? "Move Stop" : "Gradient")
            edit.began = true
            drag = .gradient(edit)
        }
        let place = edit.place
        var g = place.gradient
        let shift = event.modifierFlags.contains(.shift)
        func unit(_ composition: Vec2) -> Vec2 { place.unit(place.toLocal.apply(composition)) }
        func composition(_ unit: Vec2) -> Vec2 { place.world.apply(place.local(unit)) }
        switch edit.part {
        case .start, .end:
            let fixed = composition(edit.part == .start ? g.end : g.start)
            let reach = shift ? GradientEditing.snapped(point, around: fixed) : point
            if edit.part == .start { g.start = unit(reach) } else { g.end = unit(reach) }
        case .line:
            let shift = place.unit(place.toLocal.applyToVector(point - edit.start))
            g.start = g.start + shift
            g.end = g.end + shift
        case .stop(let i):
            let along = GradientEditing.position(of: point, from: composition(g.start), to: composition(g.end))
            g = GradientEditing.moving(i, in: g, to: along)
        }
        controller.update([place.layer.with(place.paint.withGradient(g), at: place.edit.slot)])
    }

    func gradientMouseUp(_ edit: CanvasDrag.GradientDrag, point: Vec2) {
        guard let controller else { return }
        if edit.began { return controller.end() }
        // A click on the line adds a stop there, in the colour already there.
        guard edit.part == .line else { return }
        let place = edit.place
        func composition(_ unit: Vec2) -> Vec2 { place.world.apply(place.local(unit)) }
        let along = GradientEditing.position(of: point, from: composition(place.gradient.start), to: composition(place.gradient.end))
        let added = GradientEditing.adding(to: place.gradient, at: along)
        controller.perform(.batch([.updateLayers([place.layer.with(place.paint.withGradient(added.gradient), at: place.edit.slot)])],
                                  name: "Add Stop"))
        controller.editor.gradient = GradientEdit(layerID: place.edit.layerID, slot: place.edit.slot, stop: added.index)
    }

    /// Escape hides the line until the selection changes. Delete removes
    /// the picked stop, and beeps when only the two ends' stops are left,
    /// rather than deleting the layer; with no stop picked it deletes the
    /// layer as usual.
    func gradientKeyDown(_ event: NSEvent) -> Bool {
        guard let place = gradientPlace(), let controller else { return false }
        switch event.keyCode {
        case 53:
            controller.editor.hidesGradient = true
            return true
        case 51, 117:
            guard let stop = place.edit.stop else { return false }
            guard let fewer = GradientEditing.removing(stop, from: place.gradient) else {
                NSSound.beep()
                return true
            }
            controller.perform(.batch([.updateLayers([place.layer.with(place.paint.withGradient(fewer), at: place.edit.slot)])],
                                      name: "Remove Stop"))
            controller.editor.gradient?.stop = nil
            return true
        default:
            return false
        }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1) : 0
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }
}
