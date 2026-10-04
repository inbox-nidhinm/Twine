import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering

/// A shape's points shown on the canvas: while the pen draws, while a shape's
/// points are edited in Design, and for a selected Path action's end in
/// Animate.
struct PathSession: Equatable {
    enum Target: Equatable {
        /// The layer's own points, in Design.
        case layer
        /// A Path action's end shape, in Animate.
        case action(UUID)
    }

    let layerID: UUID
    let target: Target
    var selected: Set<PointRef> = []
    /// While the pen draws: the open end the next click carries on from.
    var drawingFrom: PointRef?
    /// The pointer while the pen draws, in composition space, for the
    /// segment that follows it.
    var pointer: Vec2?
}

/// Editing points, as Figma does. The pen (P) clicks points in, drags curve
/// handles out, and closes a path on its first point; Escape or Return
/// leaves it open. A double-click or Return on a shape shows its points:
/// click, Shift-click or box-select them, drag points, handles or segments,
/// ⌘-click to bend a point between sharp and smooth, ⌘-drag to pull out
/// handles, Option-drag a handle to move it alone, Delete to take points out,
/// and the pen on a segment to add one. A rectangle, ellipse, polygon or star
/// becomes a path at its first change. In Animate a selected Path action
/// shows its end shape, whose points move but cannot be added or taken away;
/// the pen draws new paths there too (5 October 2026), but a shape's points
/// are edited only in Design.
extension CanvasNSView {
    var isEditingPoints: Bool { pathSession?.target == .layer }
    var isDrawingPath: Bool { pathSession?.drawingFrom != nil }

    // MARK: Beginning and ending

    func beginPathEditing(_ id: UUID) {
        guard let controller, !animating, let layer = controller.project.layer(withID: id),
              PathEditing.canEditPoints(layer), !controller.isLocked(id) else { return }
        controller.select([id])
        pathSession = PathSession(layerID: id, target: .layer)
        setHover(nil)
        window?.invalidateCursorRects(for: self)
        redrawOverlay()
    }

    func endPathEditing() {
        guard pathSession != nil else { return }
        if isDrawingPath { finishDrawing() }
        pathSession = nil
        overlay.updatePath(nil)
        window?.invalidateCursorRects(for: self)
        redrawOverlay()
    }

    /// The pen stops drawing and hands back the arrow, leaving the points
    /// showing. A path of a single point draws nothing, so it goes.
    func finishDrawing() {
        guard let controller, var session = pathSession, session.drawingFrom != nil else { return }
        session.drawingFrom = nil
        session.pointer = nil
        session.selected = []
        if let layer = controller.project.layer(withID: session.layerID), let path = PathEditing.path(of: layer),
           PathEditing.refs(in: path).count < 2 {
            controller.perform(.deleteLayers([session.layerID]))
            controller.editor.selection = []
            pathSession = nil
            overlay.updatePath(nil)
        } else {
            pathSession = session
        }
        if controller.editor.tool == .pen { controller.editor.tool = .select }
        window?.invalidateCursorRects(for: self)
        redrawOverlay()
    }

    /// Keeps the session in step with the project and the selection, called
    /// from `show`. It only changes what the canvas shows, never the project.
    func validatePathSession() {
        guard let controller else { return }
        let project = controller.project
        if let session = pathSession {
            switch session.target {
            case .layer:
                // In Animate, only a path being drawn keeps its points showing.
                guard !animating || session.drawingFrom != nil, selection == [session.layerID], tool == .select || tool == .pen,
                      let layer = project.layer(withID: session.layerID), let path = PathEditing.path(of: layer) else {
                    let wasDrawing = session.drawingFrom != nil
                    pathSession = nil
                    if wasDrawing, controller.editor.tool == .pen {
                        DispatchQueue.main.async { controller.editor.tool = .select }
                    }
                    break
                }
                var next = session
                next.selected = next.selected.filter { PathEditing.point($0, in: path) != nil }
                if let from = next.drawingFrom, !PathEditing.isOpenEnd(from, in: path) {
                    // An undo took the end away: carry on from the last open
                    // end, if there is one.
                    next.drawingFrom = path.subpaths.indices.last.flatMap { i in
                        path.subpaths[i].isClosed ? nil : PointRef(i, path.subpaths[i].points.count - 1)
                    }
                }
                if next != session { pathSession = next }
                if next.drawingFrom != nil, tool != .pen {
                    DispatchQueue.main.async { [weak self] in self?.finishDrawing() }
                }
            case .action(let id):
                if !animating || controller.canvasAction?.id != id { pathSession = nil }
            }
        }
        // Checked on every frame while playing, so the cheap test goes first.
        if pathSession == nil, animating, controller.editor.selectedActions.count == 1,
           let action = controller.canvasAction, case .path = action.spec,
           let layer = project.layer(withID: action.targetLayerID), case .shape(let shape) = layer.content,
           case .path = shape.geometry {
            pathSession = PathSession(layerID: action.targetLayerID, target: .action(action.id))
        }
        if pathSession == nil { overlay.updatePath(nil) }
    }

    // MARK: The path and where it is

    /// The points being shown, in the path's own space.
    func sessionPath(_ session: PathSession) -> BezierPath? {
        guard let project = controller?.project else { return nil }
        switch session.target {
        case .layer:
            return project.layer(withID: session.layerID).flatMap(PathEditing.path(of:))
        case .action(let id):
            guard case .path(let p)? = project.actions.first(where: { $0.id == id })?.spec else { return nil }
            return p.end
        }
    }

    /// From the path's own space into composition space, worked out from the
    /// project as it is now, so it is right straight after an edit. A layer's
    /// points come already fitted to its box (`PathEditing.path(of:)`); a
    /// Path action's end is shown where the layer is at the action's end.
    func pathTransform(_ session: PathSession) -> Affine? {
        guard let controller, let layer = controller.project.layer(withID: session.layerID) else { return nil }
        switch session.target {
        case .layer:
            var parentWorld = Affine.identity
            if let parent = controller.project.location(of: layer.id)?.parentID {
                guard let world = (scene ?? evaluateDesign(controller.project)).worldTransform(of: parent) else { return nil }
                parentWorld = world
            }
            let t = layer.transform
            return Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew).then(parentWorld)
        case .action(let id):
            guard let action = controller.project.actions.first(where: { $0.id == id }) else { return nil }
            let end = evaluate(controller.project, at: action.end)
            guard let world = end.worldTransform(of: layer.id), let shown = end.layer(layer.id),
                  case .shape(let shape) = layer.content, case .path(let designed) = shape.geometry,
                  let box = designed.bounds else { return nil }
            // As it is drawn: stretched from the designed points' bounds onto
            // the box the layer has at the action's end.
            let stretch = Vec2(box.width > 1e-9 ? shown.size.width / box.width : 1,
                               box.height > 1e-9 ? shown.size.height / box.height : 1)
            return Affine.translation(Vec2(-box.minX, -box.minY)).then(.scale(stretch)).then(world)
        }
    }

    private func viewTransform(_ t: Affine) -> CGAffineTransform {
        let o = compositionToView(.zero)
        return CGAffineTransform(a: t.a * zoom, b: t.b * zoom, c: t.c * zoom, d: t.d * zoom,
                                 tx: t.tx * zoom + o.x, ty: t.ty * zoom + o.y)
    }

    /// The handles shown: those of the selected points and the point being
    /// drawn from, and the handles facing them from either side.
    private func visibleHandles(_ session: PathSession, _ path: BezierPath) -> [(PointRef, HandleSide)] {
        var around = session.selected
        if let from = session.drawingFrom { around.insert(from) }
        var shown: [(PointRef, HandleSide)] = []
        var seen = Set<String>()
        func add(_ ref: PointRef, _ side: HandleSide) {
            guard let p = PathEditing.point(ref, in: path), (side == .inHandle ? p.inHandle : p.outHandle) != .zero,
                  seen.insert("\(ref.subpath).\(ref.index).\(side)").inserted else { return }
            shown.append((ref, side))
        }
        for ref in around.sorted() {
            guard path.subpaths.indices.contains(ref.subpath) else { continue }
            let sub = path.subpaths[ref.subpath], n = sub.points.count
            add(ref, .inHandle)
            add(ref, .outHandle)
            if sub.isClosed || ref.index > 0 { add(PointRef(ref.subpath, (ref.index + n - 1) % n), .outHandle) }
            if sub.isClosed || ref.index < n - 1 { add(PointRef(ref.subpath, (ref.index + 1) % n), .inHandle) }
        }
        return shown
    }

    /// The points, handles and segment following the pen, for the overlay.
    func pathMarks() -> CanvasOverlay.PathMarks? {
        guard let session = pathSession, let path = sessionPath(session), let t = pathTransform(session) else { return nil }
        func view(_ p: Vec2) -> CGPoint { compositionToView(t.apply(p)) }
        var marks = CanvasOverlay.PathMarks()
        var transform = viewTransform(t)
        marks.outline = path.cgPath.copy(using: &transform)
        for ref in PathEditing.refs(in: path) {
            guard let p = PathEditing.point(ref, in: path) else { continue }
            if session.selected.contains(ref) || ref == session.drawingFrom {
                marks.selected.append(view(p.position))
            } else {
                marks.points.append(view(p.position))
            }
        }
        for (ref, side) in visibleHandles(session, path) {
            guard let p = PathEditing.point(ref, in: path) else { continue }
            marks.arms.append((view(p.position), view(p.position + (side == .inHandle ? p.inHandle : p.outHandle))))
        }
        if let from = session.drawingFrom, let pointer = session.pointer, let last = PathEditing.point(from, in: path) {
            // Drawing carries on from the end: at a subpath's start the curve
            // leaves along what is now its in-handle.
            let leaving = from.index == 0 && path.subpaths[from.subpath].points.count > 1 ? last.inHandle : last.outHandle
            let rubber = CGMutablePath()
            rubber.move(to: view(last.position))
            let end = compositionToView(pointer)
            rubber.addCurve(to: end, control1: view(last.position + leaving), control2: end)
            marks.rubber = rubber
        }
        return marks
    }

    // MARK: Hit testing

    enum PathHit: Equatable {
        case handle(PointRef, HandleSide)
        case point(PointRef)
        case segment(PointRef, Double)
    }

    /// What of the path lies under a view point: the nearest point or shown
    /// handle within reach (points win ties), else a segment within a few
    /// points of the line.
    func pathHit(_ session: PathSession, _ path: BezierPath, _ t: Affine, at viewPoint: CGPoint,
                 handles: Bool = true) -> PathHit? {
        let reach = CanvasHandles.hitRadius + 1
        func distance(_ p: Vec2) -> CGFloat {
            let v = compositionToView(t.apply(p))
            return hypot(v.x - viewPoint.x, v.y - viewPoint.y)
        }
        var best: (hit: PathHit, distance: CGFloat)?
        for ref in PathEditing.refs(in: path) {
            guard let p = PathEditing.point(ref, in: path) else { continue }
            let d = distance(p.position)
            if d <= reach, d < (best?.distance ?? .infinity) { best = (.point(ref), d) }
        }
        if handles {
            for (ref, side) in visibleHandles(session, path) {
                guard let p = PathEditing.point(ref, in: path) else { continue }
                let d = distance(p.position + (side == .inHandle ? p.inHandle : p.outHandle))
                if d <= reach, d < (best?.distance ?? .infinity) - 0.5 { best = (.handle(ref, side), d) }
            }
        }
        if let best { return best.hit }
        guard let inverse = t.inverted else { return nil }
        let local = inverse.apply(viewToComposition(viewPoint))
        let tolerance = 5 / (zoom * max(sqrt(abs(t.determinant)), 1e-6))
        return PathEditing.nearestSegment(in: path, to: local, tolerance: tolerance).map { .segment($0.ref, $0.t) }
    }

    /// Each point but `except` as a box of no size, for points to snap to.
    private func pointBoxes(_ path: BezierPath, _ t: Affine, except: Set<PointRef>) -> [Box] {
        PathEditing.refs(in: path).filter { !except.contains($0) }.compactMap { ref in
            guard let p = PathEditing.point(ref, in: path) else { return nil }
            let c = t.apply(p.position)
            return Box(minX: c.x, minY: c.y, maxX: c.x, maxY: c.y)
        }
    }

    // MARK: Changing the path

    /// A press working from the project as it is now.
    private func pathPress(_ session: PathSession, _ part: CanvasDrag.PathEdit.Part, at point: Vec2) -> CanvasDrag.PathEdit? {
        guard let controller, let layer = controller.project.layer(withID: session.layerID), let path = sessionPath(session),
              let t = pathTransform(session), let toLocal = t.inverted else { return nil }
        var action: Action?
        if case .action(let id) = session.target { action = controller.project.actions.first { $0.id == id } }
        return CanvasDrag.PathEdit(part: part, start: point, path: path, layer: layer, actions: controller.project.actions,
                                   action: action, toLocal: toLocal)
    }

    /// Starts dragging, as one undo step. A Path action's end is edited
    /// where it shows, so the playhead goes there.
    private func startPress(_ press: CanvasDrag.PathEdit?, name: String) {
        guard let controller, var press else { return }
        if !press.began {
            controller.begin(name)
            press.began = true
        }
        if let action = press.action {
            controller.stop()
            controller.seek(to: action.end)
        }
        drag = .path(press)
    }

    /// The command that gives the layer (or its Path action) a new path. A
    /// layer's box is refitted to its points, taking its Move and Path
    /// actions along.
    private func pathCommand(_ path: BezierPath, layer: Layer, actions: [Action], action: Action?,
                             restyle: Bool = false, name: String) -> EditorCommand? {
        guard let controller else { return nil }
        if var a = action {
            guard case .path(var p) = a.spec else { return nil }
            p.end = path
            a.spec = .path(p)
            return .batch([.updateActions([a])], name: name)
        }
        let base = restyle ? PathEditing.styledForClosing(layer) : layer
        let (edited, moved) = PathEditing.reshaped(base, to: path, actions: actions)
        let update = controller.layerUpdate([edited])
        return moved.isEmpty ? .batch([update], name: name) : .batch([update, .updateActions(moved)], name: name)
    }

    /// One step of a press, inside its continuous change.
    private func commit(_ path: BezierPath, _ press: CanvasDrag.PathEdit, restyle: Bool = false) {
        guard let command = pathCommand(path, layer: press.layer, actions: press.actions, action: press.action,
                                        restyle: restyle, name: "Edit Points") else { return }
        controller?.update(command)
    }

    /// A change made at once, as its own undo step.
    private func performPath(_ path: BezierPath, _ session: PathSession, name: String) {
        guard let controller, let layer = controller.project.layer(withID: session.layerID) else { return }
        var action: Action?
        if case .action(let id) = session.target { action = controller.project.actions.first { $0.id == id } }
        guard let command = pathCommand(path, layer: layer, actions: controller.project.actions, action: action, name: name) else { return }
        controller.perform(command)
    }

    /// Commits a change made by a pen press straight away, inside the
    /// continuous change the press has begun.
    private func commitNow(_ path: BezierPath, _ session: PathSession, restyle: Bool = false) {
        guard let controller, let layer = controller.project.layer(withID: session.layerID),
              let command = pathCommand(path, layer: layer, actions: controller.project.actions, action: nil,
                                        restyle: restyle, name: "Edit Points") else { return }
        controller.update(command)
    }

    // MARK: Mouse

    /// A press while points are showing or the pen is in hand. Returns false
    /// when the canvas should treat it as an ordinary click.
    func pathMouseDown(_ event: NSEvent, at point: Vec2, viewPoint: CGPoint) -> Bool {
        guard controller != nil else { return false }
        if tool == .pen {
            penMouseDown(event, at: point, viewPoint: viewPoint)
            return true
        }
        guard var session = pathSession else { return false }
        if session.target == .layer, tool != .select {
            endPathEditing()
            return false
        }
        guard let path = sessionPath(session), let t = pathTransform(session) else { return false }
        let shift = event.modifierFlags.contains(.shift), command = event.modifierFlags.contains(.command)
        let isAction = session.target != .layer

        switch pathHit(session, path, t, at: viewPoint) {
        case .handle(let ref, let side)?:
            startPress(pathPress(session, .handle(ref, side), at: point), name: "Edit Handle")
        case .point(let ref)?:
            if command {
                session.selected = [ref]
                pathSession = session
                var press = pathPress(session, .pull(ref), at: point)
                press?.bendsOnClick = true
                startPress(press, name: "Bend Point")
            } else if shift {
                if session.selected.contains(ref) { session.selected.remove(ref) } else { session.selected.insert(ref) }
                pathSession = session
                if session.selected.contains(ref) {
                    snapTargets = targets(excluding: [session.layerID]) + pointBoxes(path, t, except: session.selected)
                    startPress(pathPress(session, .points(session.selected), at: point), name: "Move Points")
                }
            } else {
                if !session.selected.contains(ref) { session.selected = [ref] }
                pathSession = session
                snapTargets = targets(excluding: [session.layerID]) + pointBoxes(path, t, except: session.selected)
                startPress(pathPress(session, .points(session.selected), at: point),
                           name: session.selected.count == 1 ? "Move Point" : "Move Points")
            }
        case .segment(let ref, _)?:
            let n = path.subpaths[ref.subpath].points.count
            session.selected = [ref, PointRef(ref.subpath, (ref.index + 1) % n)]
            pathSession = session
            snapTargets = targets(excluding: [session.layerID]) + pointBoxes(path, t, except: session.selected)
            startPress(pathPress(session, .segment(ref), at: point), name: "Move Segment")
        case nil:
            // Off the path, a selected action lets the canvas carry on as
            // usual; the layer's own points are box-selected.
            if isAction { return false }
            if !shift { session.selected = [] }
            pathSession = session
            drag = pathPress(session, .marquee(start: viewPoint, current: viewPoint, base: shift ? session.selected : []),
                             at: point).map(CanvasDrag.path)
        }
        return true
    }

    /// The pen: carries on the path being drawn, closes it on its first
    /// point, carries on from an open end, adds a point on a segment, moves
    /// a point, or starts a new path.
    private func penMouseDown(_ event: NSEvent, at pointer: Vec2, viewPoint: CGPoint) {
        guard let controller else { return }
        let shift = event.modifierFlags.contains(.shift)

        if var session = penTarget(), let layer = controller.project.layer(withID: session.layerID),
           let path = PathEditing.path(of: layer), let t = pathTransform(session), let toLocal = t.inverted {
            snapTargets = targets(excluding: [session.layerID]) + pointBoxes(path, t, except: [])
            let hit = pathHit(session, path, t, at: viewPoint, handles: false)

            if let from = session.drawingFrom {
                if case .point(let ref)? = hit, ref != from, PathEditing.isOpenEnd(ref, in: path) {
                    // Onto an open end: the start of this path closes it, the
                    // end of another joins the two.
                    let (continued, _) = PathEditing.continuing(from: from, in: path)
                    let last = continued.subpaths.count - 1
                    let target: PointRef
                    if ref.subpath == from.subpath {
                        target = PointRef(last, 0)
                    } else {
                        let sub = ref.subpath > from.subpath ? ref.subpath - 1 : ref.subpath
                        target = PointRef(sub, ref.index)
                    }
                    let joinedAt = ref.subpath == from.subpath ? target
                        : PointRef(last - 1, continued.subpaths[last].points.count)
                    let closed = PathEditing.closing(continued, onto: target)
                    controller.begin("Close Path")
                    commitNow(closed, session, restyle: closed.subpaths.allSatisfy(\.isClosed))
                    session.drawingFrom = nil
                    session.selected = [joinedAt]
                    pathSession = session
                    var press = pathPress(session, .pull(joinedAt), at: pointer)
                    press?.began = true
                    press?.finishesDrawing = true
                    // The drag bends the curve arriving at the point it
                    // closed on; a plain click leaves it as it was.
                    press?.bendsOnClick = false
                    drag = press.map(CanvasDrag.path)
                    return
                }
                // Anywhere else, the next point.
                guard let lastPoint = PathEditing.point(from, in: path) else { return }
                let place = shift ? CanvasGeometry.constrainedEnd(t.apply(lastPoint.position), pointer, tool: .line, square: true)
                                  : snapped(pointer, event)
                let (continued, _) = PathEditing.continuing(from: from, in: path)
                let (added, ref) = PathEditing.appending(PathPoint(toLocal.apply(place)), to: continued)
                controller.begin("Add Point")
                commitNow(added, session)
                session.drawingFrom = ref
                session.selected = []
                session.pointer = place
                pathSession = session
                var press = pathPress(session, .pull(ref), at: place)
                press?.began = true
                drag = press.map(CanvasDrag.path)
                return
            }

            switch hit {
            case .point(let ref)? where PathEditing.isOpenEnd(ref, in: path):
                // Carries on drawing from an open end.
                session.drawingFrom = ref
                session.selected = []
                pathSession = session
                if selection != [session.layerID] { controller.select([session.layerID]) }
                return
            case .point(let ref)?:
                session.selected = [ref]
                pathSession = session
                startPress(pathPress(session, .points([ref]), at: pointer), name: "Move Point")
                return
            case .segment(let ref, let at)?:
                let (split, added) = PathEditing.inserting(on: ref, at: at, in: path)
                controller.begin("Add Point")
                commitNow(split, session)
                session.selected = [added]
                pathSession = session
                var press = pathPress(session, .points([added]), at: pointer)
                press?.began = true
                drag = press.map(CanvasDrag.path)
                return
            default:
                break
            }
        }

        // A new path, where the pen was pressed.
        snapTargets = targets(excluding: [])
        let place = snapped(pointer, event)
        let layer = PathEditing.newPath(at: place, name: LayerFactory.nextName("Path", in: controller.project))
        controller.begin("Add Path")
        controller.update(.insertLayers([layer], parentID: nil, index: nil))
        controller.select([layer.id])
        let session = PathSession(layerID: layer.id, target: .layer, drawingFrom: PointRef(0, 0), pointer: place)
        pathSession = session
        var press = pathPress(session, .pull(PointRef(0, 0)), at: place)
        press?.began = true
        drag = press.map(CanvasDrag.path)
    }

    /// What the pen works on: the path it is drawing or whose points are
    /// showing, or else the one shape selected.
    private func penTarget() -> PathSession? {
        guard let controller else { return nil }
        if let session = pathSession, session.target == .layer { return session }
        // In Animate the pen only draws new paths: a shape's points are Design's.
        if animating { return nil }
        guard selection.count == 1, let id = selection.first, let layer = controller.project.layer(withID: id),
              PathEditing.canEditPoints(layer), !controller.isLocked(id) else { return nil }
        return PathSession(layerID: id, target: .layer)
    }

    func pathMouseDragged(_ press: CanvasDrag.PathEdit, point: Vec2, viewPoint: CGPoint, event: NSEvent) {
        var press = press
        let shift = event.modifierFlags.contains(.shift), option = event.modifierFlags.contains(.option)

        if case .marquee(let start, _, let base) = press.part {
            press.part = .marquee(start: start, current: viewPoint, base: base)
            drag = .path(press)
            selectPoints(in: press)
            return
        }
        // A press has to travel a few points before it moves anything, so a
        // click never nudges a point or sprouts tiny handles.
        let startView = compositionToView(press.start)
        guard press.moved || hypot(viewPoint.x - startView.x, viewPoint.y - startView.y) >= 3 else { return }
        press.moved = true
        drag = .path(press)

        switch press.part {
        case .points(let refs):
            commit(PathEditing.moving(refs, in: press.path, by: movedBy(press, refs: refs, to: point, event: event)), press)
        case .segment(let ref):
            let n = press.path.subpaths[ref.subpath].points.count
            let refs: Set<PointRef> = [ref, PointRef(ref.subpath, (ref.index + 1) % n)]
            commit(PathEditing.moving(refs, in: press.path, by: movedBy(press, refs: refs, to: point, event: event)), press)
        case .handle(let ref, let side):
            guard let p = PathEditing.point(ref, in: press.path) else { return }
            let offset = constrainedHandle(press.toLocal.apply(point) - p.position, shift: shift)
            commit(PathEditing.settingHandle(side, of: ref, in: press.path, to: offset, independent: option), press)
        case .pull(let ref):
            guard let p = PathEditing.point(ref, in: press.path) else { return }
            let offset = constrainedHandle(press.toLocal.apply(point) - p.position, shift: shift)
            // Option pulls only the handle leading on, leaving a corner.
            let pulled = option ? PathEditing.settingHandle(.outHandle, of: ref, in: press.path, to: offset, independent: true)
                                : PathEditing.pullingHandles(of: ref, in: press.path, out: offset)
            commit(pulled, press)
        case .marquee:
            break
        }
    }

    /// How far dragged points move in the path's own space: the pointer's
    /// travel, held to one axis with Shift, and pulled onto a guide or
    /// another point when the grabbed point comes near one.
    private func movedBy(_ press: CanvasDrag.PathEdit, refs: Set<PointRef>, to point: Vec2, event: NSEvent) -> Vec2 {
        var delta = point - press.start
        var axes: Set<Snapping.Axis> = [.x, .y]
        if event.modifierFlags.contains(.shift) {
            let across = abs(delta.x) >= abs(delta.y)
            delta = across ? Vec2(delta.x, 0) : Vec2(0, delta.y)
            axes = across ? [.x] : [.y]
        }
        snap = nil
        if snapping(event), let world = press.toLocal.inverted {
            // The point nearest where the press began is the one in hand.
            let grabbed = refs.compactMap { PathEditing.point($0, in: press.path).map { world.apply($0.position) } }
                .min { hypot($0.x - press.start.x, $0.y - press.start.y) < hypot($1.x - press.start.x, $1.y - press.start.y) }
            if let grabbed {
                let moved = grabbed + delta
                let result = Snapping.point(moved, box: Box(around: [moved])!, targets: snapTargets, frame: frameBox,
                                            threshold: snapReach, axes: axes)
                delta = delta + result.offset
                snap = result
            }
        }
        return press.toLocal.applyToVector(delta)
    }

    /// With Shift, a handle keeps to 45° steps.
    private func constrainedHandle(_ offset: Vec2, shift: Bool) -> Vec2 {
        guard shift else { return offset }
        return CanvasGeometry.constrainedEnd(.zero, offset, tool: .line, square: true)
    }

    private func selectPoints(in press: CanvasDrag.PathEdit) {
        guard case .marquee(let a, let b, let base) = press.part, var session = pathSession,
              let world = press.toLocal.inverted else { return }
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        let inside = PathEditing.refs(in: press.path).filter { ref in
            guard let p = PathEditing.point(ref, in: press.path) else { return false }
            return rect.contains(compositionToView(world.apply(p.position)))
        }
        session.selected = base.union(inside)
        pathSession = session
    }

    func pathMouseUp(_ press: CanvasDrag.PathEdit, event: NSEvent) {
        guard let controller else { return }
        if case .marquee(let a, let b, _) = press.part {
            guard hypot(b.x - a.x, b.y - a.y) < 3 else { return }
            // A click off the points: inside the shape it lets go of them;
            // anywhere else it stops editing and picks what is there.
            let point = viewToComposition(a)
            if press.path.cgPath.contains(press.toLocal.apply(point).cg) {
                pathSession?.selected = []
                return
            }
            endPathEditing()
            if let hit = layer(at: point, deep: event.modifierFlags.contains(.command)) {
                controller.select([hit])
            } else {
                controller.deselectAll()
            }
            return
        }
        if press.bendsOnClick, !press.moved, case .pull(let ref) = press.part {
            commit(PathEditing.togglingSmooth(ref, in: press.path), press)
        }
        if press.began { controller.end() }
        if press.finishesDrawing {
            // Closed: the arrow comes back, with the points still showing.
            if controller.editor.tool == .pen { controller.editor.tool = .select }
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Pointers while the pen is in hand or points are showing. Returns false
    /// to let the canvas set its usual hover and pointer.
    func pathMouseMoved(_ viewPoint: CGPoint, event: NSEvent) -> Bool {
        if tool == .pen {
            setHover(nil)
            var cursor = Cursors.pen
            if var session = penTarget(), let path = sessionPath(session), let t = pathTransform(session) {
                let hit = pathHit(session, path, t, at: viewPoint, handles: false)
                if let from = session.drawingFrom {
                    if case .point(let ref)? = hit, ref != from, PathEditing.isOpenEnd(ref, in: path) { cursor = Cursors.penConnect }
                    var pointer = viewToComposition(viewPoint)
                    if event.modifierFlags.contains(.shift), let last = PathEditing.point(from, in: path) {
                        pointer = CanvasGeometry.constrainedEnd(t.apply(last.position), pointer, tool: .line, square: true)
                    }
                    session.pointer = pointer
                    pathSession = session
                    redrawOverlay()
                } else {
                    switch hit {
                    case .point(let ref)? where PathEditing.isOpenEnd(ref, in: path): cursor = Cursors.penConnect
                    case .point?: cursor = Cursors.penMove
                    case .segment?: cursor = Cursors.penAdd
                    default: break
                    }
                }
            }
            cursor.set()
            return true
        }
        if isEditingPoints {
            setHover(nil)
            Cursors.arrow.set()
            return true
        }
        return false
    }

    // MARK: Keyboard

    /// Return shows a shape's points, finishes drawing and stops editing;
    /// Escape does the last two; Delete takes points out; arrows nudge them.
    func pathKeyDown(_ event: NSEvent) -> Bool {
        guard let controller else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if event.keyCode == 36 || event.keyCode == 76 {
            if isDrawingPath { finishDrawing(); return true }
            if isEditingPoints { endPathEditing(); return true }
            guard !animating, flags.isEmpty, selection.count == 1, let id = selection.first,
                  let layer = controller.project.layer(withID: id), PathEditing.canEditPoints(layer),
                  !controller.isLocked(id) else { return false }
            beginPathEditing(id)
            return true
        }
        guard let session = pathSession, flags.isEmpty else { return false }
        switch event.keyCode {
        case 53:                                                     // escape
            if case .path(let press)? = drag {
                if press.began { controller.cancel() }
                drag = nil
                snap = nil
                redrawOverlay()
                return true
            }
            if session.drawingFrom != nil { finishDrawing(); return true }
            if session.target == .layer { endPathEditing(); return true }
            guard !session.selected.isEmpty else { return false }
            pathSession?.selected = []
            redrawOverlay()
            return true
        case 51, 117:                                                // delete, forward delete
            // A Path action's points cannot be taken away, and a beep says
            // so rather than the layer going instead; with no points
            // selected, Delete leaves the layer alone while editing.
            guard session.target == .layer else {
                guard !session.selected.isEmpty else { return false }
                NSSound.beep()
                return true
            }
            guard !session.selected.isEmpty, let path = sessionPath(session) else { return true }
            let remaining = PathEditing.deleting(session.selected, from: path)
            if remaining.subpaths.isEmpty {
                controller.perform(.deleteLayers([session.layerID]))
                controller.editor.selection = []
                pathSession = nil
                overlay.updatePath(nil)
            } else {
                performPath(remaining, session, name: session.selected.count == 1 ? "Delete Point" : "Delete Points")
                pathSession?.selected = []
            }
            redrawOverlay()
            return true
        case 123, 124, 125, 126:                                     // arrows
            guard !session.selected.isEmpty, let path = sessionPath(session), let toLocal = pathTransform(session)?.inverted
            else { return false }
            let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
            let delta: Vec2 = switch event.keyCode {
            case 123: Vec2(-step, 0)
            case 124: Vec2(step, 0)
            case 125: Vec2(0, step)
            default: Vec2(0, -step)
            }
            performPath(PathEditing.moving(session.selected, in: path, by: toLocal.applyToVector(delta)), session,
                        name: session.selected.count == 1 ? "Nudge Point" : "Nudge Points")
            redrawOverlay()
            return true
        default:
            return false
        }
    }
}
