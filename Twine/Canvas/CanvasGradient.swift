import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation

/// A gradient's line on the canvas, as Figma shows it (4 October 2026):
/// shown while `EditorModel.gradient` names one of the selected layer's
/// paints (the switch beside the inspector's gradient bar, or picking a
/// stop there). Drag either end to turn and stretch it (Shift keeps the
/// angle to steps of 15°), the line to move it, a stop's dot to slide the
/// stop along; a click on the line adds a stop there. Delete removes the
/// picked stop; Escape, Return or a click away finishes. A radial
/// gradient's line runs from its centre to its edge, its circle drawn.
/// Design only; the layer's own handles hide meanwhile.
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

    var isEditingGradient: Bool { gradientPlace() != nil }

    func gradientPlace() -> GradientPlace? {
        guard let controller, let scene, let edit = controller.editor.gradient, !animating, tool == .select,
              textSession == nil, pathSession == nil, cropSession == nil, selection == [edit.layerID],
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
        if place.paint.isRadial {
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
    /// line. Anywhere else the editing finishes and the press carries on.
    func gradientMouseDown(_ event: NSEvent, at point: Vec2, viewPoint: CGPoint) -> Bool {
        guard let place = gradientPlace(), let controller else { return false }
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
            controller.editor.gradient = nil
            return false
        }
        if case .stop(let i) = part { controller.editor.gradient?.stop = i }
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
        controller.editor.gradient?.stop = added.index
    }

    /// Escape and Return finish; Delete removes the picked stop, and
    /// beeps when only the two ends' stops are left, rather than deleting
    /// the layer.
    func gradientKeyDown(_ event: NSEvent) -> Bool {
        guard let place = gradientPlace(), let controller else { return false }
        switch event.keyCode {
        case 53, 36, 76:
            controller.editor.gradient = nil
            return true
        case 51, 117:
            guard let stop = place.edit.stop, let fewer = GradientEditing.removing(stop, from: place.gradient) else {
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
