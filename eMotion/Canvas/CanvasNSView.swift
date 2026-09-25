import AppKit
import QuartzCore
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering
import Theme

/// The canvas: the composition drawn by `CoreAnimationRenderer`, zoomed and
/// panned inside the window, with the selection drawn over it at screen
/// resolution.
///
/// An AppKit view rather than SwiftUI because it needs every mouse event with
/// exact positions, the keyboard, pinch and scroll, and a layer tree the
/// renderer can own.
final class CanvasNSView: NSView {
    var controller: EditorController? {
        didSet { controller?.canvas = self }
    }
    /// Called first on every mouse down. Returns true when it put something
    /// away, such as an open menu, in which case the click does nothing else,
    /// the way a click outside a system menu only closes it.
    var dismissTransients: () -> Bool = { false }

    /// What the floating panels cover, so fitting lands in the visible area.
    var insets = NSEdgeInsets() {
        didSet { if !NSEdgeInsetsEqual(insets, oldValue) { layoutWorld() } }
    }

    private let renderer = CoreAnimationRenderer()
    /// Carries the composition from its own space into the view's.
    private let world = CALayer()
    private let checker = CALayer()
    private let frameEdge = CAShapeLayer()
    private let overlay = CanvasOverlay()

    private(set) var zoom: Double = 1
    /// How far the composition's centre sits from the centre of the visible area.
    private var pan = CGPoint.zero
    private var hasFitted = false
    private var compositionSize: Size2?

    private(set) var scene: ResolvedScene?
    private var project: Project?
    private var selection: [UUID] = []
    private var tool: Tool = .select
    /// Animate mode: the canvas shows the playhead's moment and only selects
    /// and moves. Resizing, turning and the anchor are design edits.
    private var animating = false
    private var hovered: UUID?
    private var drag: CanvasDrag?

    /// Ticks with the display while playing, so playback advances in step
    /// with what is shown.
    private var clock: CADisplayLink?
    private var lastTick: CFTimeInterval?

    static let minZoom = 0.02
    static let maxZoom = 64.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Core Image filters on layers, which layer blur uses, only render in
        // a view that allows them.
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true

        for l in [world, checker, frameEdge] {
            l.anchorPoint = .zero
            l.actions = ["transform": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
                         "hidden": NSNull(), "path": NSNull(), "backgroundColor": NSNull()]
        }
        checker.backgroundColor = Self.checkerColor
        frameEdge.fillColor = nil
        frameEdge.strokeColor = NSColor(Theme.edge).cgColor
        frameEdge.lineWidth = 1
        world.addSublayer(renderer.rootLayer)
        layer?.addSublayer(checker)
        layer?.addSublayer(world)
        layer?.addSublayer(frameEdge)
        layer?.addSublayer(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window as? ChromelessWindow else { return }
        // The canvas is where the keyboard goes by default, so tool letters
        // and the delete key work without clicking it first.
        window.preferredResponder = self
        DispatchQueue.main.async { [weak self] in
            guard let self, window.firstResponder === window else { return }
            window.makeFirstResponder(self)
        }
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    // MARK: Showing a scene

    /// Draws the project: as designed, or at `time` with its actions when
    /// `animating`. Called by SwiftUI whenever anything the canvas shows
    /// changes; it only renders and never writes to the model.
    func show(_ project: Project, time: Double, selection: [UUID], tool: Tool, playing: Bool, animating: Bool) {
        setClockRunning(playing)
        self.animating = animating
        self.project = project
        self.selection = selection
        if self.tool != tool {
            self.tool = tool
            window?.invalidateCursorRects(for: self)
        }
        let scene = animating ? evaluate(project, at: time) : evaluateDesign(project)
        self.scene = scene
        if compositionSize != scene.size {
            // A new size means the old zoom no longer frames anything useful.
            compositionSize = scene.size
            hasFitted = false
        }
        renderer.render(scene)
        checker.isHidden = scene.background != nil
        if hovered.map({ scene.layer($0) == nil }) == true { hovered = nil }
        layoutWorld()
    }

    override func layout() {
        super.layout()
        layoutWorld()
    }

    private var usableRect: CGRect {
        CGRect(x: insets.left, y: insets.top,
               width: max(bounds.width - insets.left - insets.right, 80),
               height: max(bounds.height - insets.top - insets.bottom, 80))
    }

    /// Where the composition's top-left lands in the view.
    private var origin: CGPoint {
        guard let size = compositionSize else { return .zero }
        let area = usableRect
        return CGPoint(x: area.midX + pan.x - size.width * zoom / 2, y: area.midY + pan.y - size.height * zoom / 2)
    }

    private func layoutWorld() {
        guard let size = compositionSize, bounds.width > 0 else { return }
        if !hasFitted { fitToWindow(animated: false) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let o = origin
        world.transform = CATransform3DConcat(CATransform3DMakeScale(zoom, zoom, 1), CATransform3DMakeTranslation(o.x, o.y, 0))
        let frame = CGRect(x: o.x, y: o.y, width: size.width * zoom, height: size.height * zoom)
        checker.frame = frame
        frameEdge.frame = bounds
        frameEdge.path = CGPath(rect: frame.insetBy(dx: -0.5, dy: -0.5), transform: nil)
        overlay.frame = bounds
        CATransaction.commit()
        redrawOverlay()
    }

    // MARK: Playback clock

    private func setClockRunning(_ running: Bool) {
        if running, clock == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            clock = link
            lastTick = nil
        } else if !running, let link = clock {
            link.invalidate()
            clock = nil
            lastTick = nil
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTick = link.targetTimestamp }
        guard let last = lastTick else { return }
        controller?.advance(by: link.targetTimestamp - last)
    }

    // MARK: Zoom and pan

    func fitToWindow(animated: Bool = false) {
        guard let size = compositionSize, size.width > 0, size.height > 0 else { return }
        let margin = 32.0
        let area = usableRect.insetBy(dx: margin, dy: margin)
        zoom = clampZoom(min(area.width / size.width, area.height / size.height))
        pan = .zero
        hasFitted = true
        updateContentsScale()
        if animated { layoutWorld() }
    }

    func zoomToActualSize() {
        zoom(to: 1, around: CGPoint(x: usableRect.midX, y: usableRect.midY))
    }

    func zoom(by factor: Double) {
        zoom(to: zoom * factor, around: CGPoint(x: usableRect.midX, y: usableRect.midY))
    }

    /// Changes the zoom keeping the composition point under `point` where it is.
    private func zoom(to newZoom: Double, around point: CGPoint) {
        let target = clampZoom(newZoom)
        let under = viewToComposition(point)
        zoom = target
        guard let size = compositionSize else { return }
        let area = usableRect
        let newOrigin = CGPoint(x: point.x - under.x * zoom, y: point.y - under.y * zoom)
        pan = CGPoint(x: newOrigin.x - (area.midX - size.width * zoom / 2),
                      y: newOrigin.y - (area.midY - size.height * zoom / 2))
        hasFitted = true
        updateContentsScale()
        layoutWorld()
    }

    private func clampZoom(_ z: Double) -> Double { min(max(z, Self.minZoom), Self.maxZoom) }

    /// Shapes are rasterised at their layer's scale, so zooming in without
    /// raising it would show soft edges.
    private func updateContentsScale() {
        let backing = window?.backingScaleFactor ?? 2
        let wanted = backing * min(max(zoom, 1), 8)
        if abs(renderer.contentsScale - wanted) > 0.01 { renderer.contentsScale = wanted }
    }

    override func magnify(with event: NSEvent) {
        zoom(to: zoom * (1 + event.magnification), around: convert(event.locationInWindow, from: nil))
    }

    /// Two fingers pan; with Command held, or on a plain mouse wheel with
    /// Command, the wheel zooms about the pointer.
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            zoom(to: zoom * exp(delta * 0.01), around: convert(event.locationInWindow, from: nil))
            return
        }
        let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        pan.x += event.scrollingDeltaX * scale
        pan.y += event.scrollingDeltaY * scale
        hasFitted = true
        layoutWorld()
    }

    // MARK: Coordinates

    func viewToComposition(_ p: CGPoint) -> Vec2 {
        let o = origin
        return Vec2((p.x - o.x) / zoom, (p.y - o.y) / zoom)
    }

    func compositionToView(_ p: Vec2) -> CGPoint {
        let o = origin
        return CGPoint(x: o.x + p.x * zoom, y: o.y + p.y * zoom)
    }

    // MARK: The overlay

    private func redrawOverlay() {
        guard let scene, let controller else { return }
        var outlines: [[CGPoint]] = []
        let endBox = actionEndBox()
        for id in selection {
            if let endBox, id == controller.canvasAction?.targetLayerID {
                outlines.append(endBox.box)
                continue
            }
            guard let corners = scene.worldCorners(of: id) else { continue }
            outlines.append(corners.map(compositionToView))
        }

        var handles: [CGPoint] = []
        var anchor: CGPoint?
        var union: [CGPoint]?
        // In Animate only a selected Resize or Scale brings the handles back,
        // to set its end.
        if let endBox, actionKindOnCanvas != .rotate {
            handles = CanvasHandles.positions(for: endBox.box, isLine: endBox.isLine)
        } else if selection.count == 1, let id = selection.first, !controller.isLocked(id), !animating,
           let corners = scene.worldCorners(of: id), let layer = scene.layer(id),
           let world = scene.worldTransform(of: id) {
            let view = corners.map(compositionToView)
            handles = CanvasHandles.positions(for: view, isLine: isLine(layer))
            if !animating { anchor = compositionToView(world.apply(layer.anchor)) }
        } else if selection.count > 1 {
            let points = outlines.flatMap { $0 }
            if let first = points.first {
                let box = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
                union = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                         CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            }
        }

        var hover: [CGPoint]?
        if let hovered, !selection.contains(hovered), drag == nil, let corners = scene.worldCorners(of: hovered) {
            hover = corners.map(compositionToView)
        }

        overlay.update(outlines: outlines, union: union, handles: handles, anchor: anchor,
                       hover: hover, marquee: drag?.marqueeRect, motion: motionOverlay())
    }

    /// The kind of the action the canvas is editing, in Animate.
    private var actionKindOnCanvas: ActionKind? {
        animating ? controller?.canvasAction?.spec.kind : nil
    }

    /// A selected Resize, Scale or Rotate edits the layer as it is at the
    /// action's end, so its outline and handles are drawn there, in view
    /// points: grabbing one takes the playhead to the end and the layer
    /// lines up under the pointer.
    private func actionEndBox() -> (box: [CGPoint], isLine: Bool)? {
        guard animating, let controller, let action = controller.canvasAction,
              [.resize, .scale, .rotate].contains(action.spec.kind) else { return nil }
        let end = evaluate(controller.project, at: action.end)
        guard let corners = end.worldCorners(of: action.targetLayerID), let layer = end.layer(action.targetLayerID) else { return nil }
        return (corners.map(compositionToView), isLine(layer))
    }

    /// The selected Move's path in view points, when there is one to show.
    private func motionOverlay() -> CanvasOverlay.Motion? {
        guard animating, let controller, let action = controller.canvasAction, case .move(let m) = action.spec,
              let from = controller.inheritedState(for: action), let toView = parentToView(action.targetLayerID) else { return nil }
        let p = ActionGeometry.path(of: m, from: from.position)
        return CanvasOverlay.Motion(start: toView(p.start), end: toView(p.end),
                                    startHandle: p.startHandle.map(toView), endHandle: p.endHandle.map(toView))
    }

    /// From a layer's parent's space, where its position lives, to view points.
    private func parentToView(_ id: UUID) -> ((Vec2) -> CGPoint)? {
        guard let scene, let project else { return nil }
        var world = Affine.identity
        if let parent = project.location(of: id)?.parentID {
            guard let w = scene.worldTransform(of: parent) else { return nil }
            world = w
        }
        return { [weak self] p in self?.compositionToView(world.apply(p)) ?? .zero }
    }

    private func isLine(_ layer: ResolvedLayer) -> Bool {
        if case .shape(let shape) = layer.content { return !shape.isClosed && layer.size.height == 0 }
        return false
    }

    // MARK: Hit testing

    /// The layer under a composition point, frontmost first. Locked layers
    /// cannot be picked. Unless `deep`, a click inside a group picks the group,
    /// as in Figma; Command reaches the layer itself.
    func layer(at point: Vec2, deep: Bool) -> UUID? {
        guard let scene, let controller else { return nil }
        let tolerance = 5 / zoom
        for resolved in scene.layers.reversed() {
            guard case .shape(let shape) = resolved.content, !controller.isLocked(resolved.id),
                  let world = scene.worldTransform(of: resolved.id), let inverse = world.inverted else { continue }
            let local = inverse.apply(point).cg
            let path = shape.path.cgPath
            // Scale the tolerance into the layer's space, so it is the same
            // few screen points whatever the layer's own scale.
            let localTolerance = tolerance / max(sqrt(abs(world.determinant)), 1e-6)
            var hit = false
            if shape.isClosed && (!shape.fills.isEmpty || shape.strokes.isEmpty) && path.contains(local) { hit = true }
            if !hit {
                let width = (shape.strokes.map(\.width).max() ?? 0) + localTolerance * 2
                hit = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(local)
            }
            if hit { return deep ? resolved.id : topLevel(of: resolved.id) }
        }
        return nil
    }

    private func topLevel(of id: UUID) -> UUID {
        guard let project else { return id }
        // The outermost unlocked group, so a click on a shape in a group
        // selects the group, and in a locked group selects nothing above it.
        return project.ancestors(of: id).first ?? id
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.editor.focus = .canvas
        if dismissTransients() { return }
        guard let controller, let scene else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = viewToComposition(viewPoint)
        let shift = event.modifierFlags.contains(.shift)

        if tool.isShape, !animating {
            drag = .create(CanvasDrag.Create(tool: tool, start: point, layerID: nil))
            return
        }

        // The selected action's own handles come first in Animate.
        if animating, let action = controller.canvasAction,
           beginActionEdit(action, at: point, viewPoint: viewPoint, commandHeld: event.modifierFlags.contains(.command)) {
            redrawOverlay()
            return
        }

        // A handle of the one selected layer comes first, before the layers
        // under it, so a handle over another shape still resizes.
        if selection.count == 1, let id = selection.first, !controller.isLocked(id), !animating,
           let layer = controller.project.layer(withID: id), let resolved = scene.layer(id),
           let corners = scene.worldCorners(of: id), let world = scene.worldTransform(of: id) {
            let view = corners.map(compositionToView)
            let anchorView = compositionToView(world.apply(resolved.anchor))
            // The anchor sits in the middle of the layer, which is exactly
            // where a move usually starts, so moving it takes Command.
            if event.modifierFlags.contains(.command),
               hypot(viewPoint.x - anchorView.x, viewPoint.y - anchorView.y) <= CanvasHandles.hitRadius {
                drag = .anchor(CanvasDrag.Edit(layer: layer, start: point))
                controller.begin("Move Anchor")
                return
            }
            if let handle = CanvasHandles.handle(at: viewPoint, box: view, isLine: isLine(resolved)) {
                drag = .resize(CanvasDrag.Resize(layer: layer, handle: handle, start: point))
                controller.begin(layer.isGroup ? "Scale" : "Resize")
                return
            }
            if CanvasHandles.isRotateZone(viewPoint, box: view) {
                drag = .rotate(CanvasDrag.Edit(layer: layer, start: point))
                controller.begin("Rotate")
                return
            }
        }

        let deep = event.modifierFlags.contains(.command)
        if let hit = layer(at: point, deep: deep) {
            if shift {
                controller.select([hit], extending: true)
            } else if !selection.contains(hit) {
                controller.select([hit])
            }
            if event.clickCount == 2, controller.project.layer(withID: hit)?.isGroup == true,
               let inner = layer(at: point, deep: true), inner != hit {
                // A double-click goes into a group, as in Figma.
                controller.select([inner])
            }
            let moving = controller.topmost(controller.selectedLayers).filter { !controller.isLocked($0.id) }
            drag = .move(CanvasDrag.Move(originals: moving, start: point))
            controller.begin(moving.count == 1 ? "Move Layer" : "Move Layers")
        } else {
            if !shift { controller.deselectAll() }
            drag = .marquee(CanvasDrag.Marquee(start: viewPoint, current: viewPoint, additive: shift,
                                               base: shift ? Set(selection) : []))
        }
        redrawOverlay()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller, let drag else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = viewToComposition(viewPoint)
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)

        switch drag {
        case .create(var create):
            let end = CanvasGeometry.constrainedEnd(create.start, point, tool: create.tool, square: shift)
            let from = option && create.tool != .line ? Vec2(2 * create.start.x - end.x, 2 * create.start.y - end.y) : create.start
            guard var layer = controller.makeShape(create.tool, from: from, to: end) else { return }
            if let id = create.layerID, let existing = controller.project.layer(withID: id) {
                // Keep the first frame's id and name, so the shape is one
                // layer being drawn rather than a new one every step.
                layer = existing.replacingGeometry(with: layer)
                controller.update([layer])
            } else {
                controller.begin("Add \(create.tool.title)")
                controller.update(.insertLayers([layer], parentID: nil, index: nil))
                create.layerID = layer.id
                controller.select([layer.id])
                self.drag = .create(create)
            }

        case .move(let move):
            guard let scene else { return }
            var delta = point - move.start
            if shift { delta = abs(delta.x) >= abs(delta.y) ? Vec2(delta.x, 0) : Vec2(0, delta.y) }
            controller.update(move.originals.map { $0.translated(by: controller.parentDelta(delta, for: $0.id, in: scene)) })

        case .resize(let resize):
            guard let parentInverse = parentInverse(of: resize.layer.id) else { return }
            let edited = CanvasGeometry.resized(resize.layer, handle: resize.handle,
                                                pointer: parentInverse.apply(point),
                                                keepAspect: shift, fromCenter: option)
            controller.update([edited])

        case .rotate(let rotate):
            guard let scene, let world = scene.worldTransform(of: rotate.layer.id),
                  let resolved = scene.layer(rotate.layer.id) else { return }
            // The anchor stays still while it turns, so its world point is
            // fixed for the whole drag.
            let pivot = rotate.pivot ?? world.apply(resolved.anchor)
            if rotate.pivot == nil {
                var r = rotate
                r.pivot = pivot
                self.drag = .rotate(r)
            }
            let a0 = atan2(rotate.start.y - pivot.y, rotate.start.x - pivot.x)
            let a1 = atan2(point.y - pivot.y, point.x - pivot.x)
            let original = rotate.layer.transform.rotation
            var angle = original + (a1 - a0) * 180 / .pi
            if shift { angle = (angle / 15).rounded() * 15 }
            var layer = rotate.layer
            layer.transform.rotation = angle
            controller.update([layer])

        case .anchor(let edit):
            guard let parentInverse = parentInverse(of: edit.layer.id) else { return }
            controller.update([CanvasGeometry.movedAnchor(edit.layer, to: parentInverse.apply(point))])

        case .marquee(var marquee):
            marquee.current = viewPoint
            self.drag = .marquee(marquee)
            selectInMarquee(marquee)

        case .action(let edit):
            if let edited = editedAction(edit, pointer: point, shift: shift) {
                controller.update(.updateActions([edited]))
            }
        }
        redrawOverlay()
    }

    override func mouseUp(with event: NSEvent) {
        guard let controller, let drag else { return }
        self.drag = nil
        switch drag {
        case .create(let create):
            if create.layerID == nil {
                // A click without a drag makes a shape of a standard size
                // centred on the click.
                let size = 100.0
                let start = create.tool == .line ? Vec2(create.start.x - size / 2, create.start.y) :
                    Vec2(create.start.x - size / 2, create.start.y - size / 2)
                let end = create.tool == .line ? Vec2(create.start.x + size / 2, create.start.y) :
                    Vec2(create.start.x + size / 2, create.start.y + size / 2)
                if let layer = controller.makeShape(create.tool, from: start, to: end),
                   controller.perform(.insertLayers([layer], parentID: nil, index: nil)) {
                    controller.select([layer.id])
                }
            } else {
                controller.end()
            }
            // Back to the arrow after drawing, as in Figma.
            controller.editor.tool = .select
        case .move, .resize, .rotate, .anchor, .action:
            controller.end()
        case .marquee:
            break
        }
        redrawOverlay()
    }

    // MARK: Editing the selected action

    /// Starts a drag on the selected action's path, handles or layer, if the
    /// click landed on one.
    private func beginActionEdit(_ action: Action, at point: Vec2, viewPoint: CGPoint, commandHeld: Bool) -> Bool {
        guard let controller, let scene, let from = controller.inheritedState(for: action),
              let parentInverse = parentInverse(of: action.targetLayerID) else { return false }
        let id = action.targetLayerID

        func start(_ part: CanvasDrag.ActionEdit.Part, seekingToEnd: Bool) -> Bool {
            let endScene = evaluate(controller.project, at: action.end)
            drag = .action(CanvasDrag.ActionEdit(action: action, part: part, start: point, from: from,
                                                 parentInverse: parentInverse, shown: scene.layer(id)?.position ?? from.position,
                                                 atEnd: endScene.layer(id), worldAtEnd: endScene.worldTransform(of: id)))
            // Handles set an end size, scale or angle against the layer as
            // it looks at the end, so the playhead goes there and the box
            // follows the pointer.
            if seekingToEnd {
                controller.stop()
                controller.seek(to: action.end)
            }
            controller.begin("Edit \(action.name)")
            return true
        }

        switch action.spec {
        case .move:
            let onLayer = layer(at: point, deep: false) == id || layer(at: point, deep: true) == id
            if let route = motionOverlay() {
                func near(_ p: CGPoint?) -> Bool {
                    p.map { hypot($0.x - viewPoint.x, $0.y - viewPoint.y) <= CanvasOverlay.motionHit } ?? false
                }
                if near(route.startHandle) { return start(.startHandle, seekingToEnd: false) }
                if near(route.endHandle) { return start(.endHandle, seekingToEnd: false) }
                if near(route.end) { return start(.pathEnd, seekingToEnd: false) }
                // The start usually sits right where the layer is grabbed to
                // set the end, so over the layer it takes Command, as the
                // anchor does in Design.
                if near(route.start), commandHeld || !onLayer { return start(.pathStart, seekingToEnd: false) }
            }
            if onLayer { return start(.body, seekingToEnd: false) }
        case .resize, .scale:
            if let end = actionEndBox(), let handle = CanvasHandles.handle(at: viewPoint, box: end.box, isLine: end.isLine) {
                return start(.handle(handle), seekingToEnd: true)
            }
        case .rotate:
            if let end = actionEndBox(), CanvasHandles.isRotateZone(viewPoint, box: end.box) {
                return start(.rotate, seekingToEnd: true)
            }
        case .opacity, .visibility:
            break
        }
        return false
    }

    /// The action as the drag has it now, worked out from the action as it
    /// was when the drag began.
    private func editedAction(_ edit: CanvasDrag.ActionEdit, pointer: Vec2, shift: Bool) -> Action? {
        var a = edit.action
        let inParent = edit.parentInverse.apply(pointer)
        switch (edit.part, edit.action.spec) {
        case (.pathStart, .move(let m)):
            a.spec = .move(ActionGeometry.settingStart(m, to: inParent, from: edit.from.position))
        case (.pathEnd, .move(let m)):
            a.spec = .move(ActionGeometry.settingEnd(m, to: inParent, from: edit.from.position))
        case (.startHandle, .move(let m)):
            a.spec = .move(ActionGeometry.settingHandle(m, first: true, to: inParent, from: edit.from.position))
        case (.endHandle, .move(let m)):
            a.spec = .move(ActionGeometry.settingHandle(m, first: false, to: inParent, from: edit.from.position))
        case (.body, .move(let m)):
            // The layer stays where it rests; its path's end follows the
            // pointer, and where it is dropped is where the move ends.
            let delta = edit.parentInverse.applyToVector(pointer - edit.start)
            a.spec = .move(ActionGeometry.settingEnd(m, to: edit.shown + delta, from: edit.from.position))
        case (.handle(let handle), .resize(var r)):
            guard let size = resizedEnd(edit, handle: handle, pointer: pointer, keepAspect: r.isLinked || shift) else { return nil }
            r.end = size
            a.spec = .resize(r)
        case (.handle(let handle), .scale(let s)):
            guard let scale = scaledEnd(edit, handle: handle, pointer: pointer, linked: s.isLinked || shift) else { return nil }
            a.spec = .scale(ActionGeometry.settingEnd(s, to: scale, from: edit.from.scale))
        case (.rotate, .rotate(let r)):
            guard let layer = edit.atEnd, let world = edit.worldAtEnd else { return nil }
            let pivot = world.apply(layer.anchor)
            let a0 = atan2(edit.start.y - pivot.y, edit.start.x - pivot.x)
            let a1 = atan2(pointer.y - pivot.y, pointer.x - pivot.x)
            // The turn since the drag began, the short way round, so crossing
            // the left of the pivot does not jump a whole circle.
            var turn = (a1 - a0) * 180 / .pi
            turn -= 360 * (turn / 360).rounded()
            var angle = layer.rotation + turn
            if shift { angle = (angle / 15).rounded() * 15 }
            a.spec = .rotate(ActionGeometry.settingEnd(r, to: angle, from: edit.from.rotation))
        default:
            return nil
        }
        return a
    }

    /// A Resize's end from a handle dragged to `pointer`. The box grows
    /// around its anchor, as the action does, so the far side moves too.
    private func resizedEnd(_ edit: CanvasDrag.ActionEdit, handle: Int, pointer: Vec2, keepAspect: Bool) -> Size2? {
        guard let layer = edit.atEnd, let inverse = edit.worldAtEnd?.inverted else { return nil }
        let local = inverse.apply(pointer)
        let size = layer.size, anchor = layer.anchor
        func span(_ p: Double, _ a: Double, _ length: Double, far: Bool) -> Double {
            let f = length > 0 ? a / length : 0.5
            if far { return f < 1 ? max((p - a) / (1 - f), 0) : max(2 * (p - a), 0) }
            return f > 0 ? max((a - p) / f, 0) : max(2 * (a - p), 0)
        }
        var w = size.width, h = size.height
        if [2, 3, 4].contains(handle) { w = span(local.x, anchor.x, size.width, far: true) }
        if [0, 6, 7].contains(handle) { w = span(local.x, anchor.x, size.width, far: false) }
        if [4, 5, 6].contains(handle) { h = span(local.y, anchor.y, size.height, far: true) }
        if [0, 1, 2].contains(handle) { h = span(local.y, anchor.y, size.height, far: false) }
        if keepAspect, size.width > 0, size.height > 0 {
            let rw = w / size.width, rh = h / size.height
            let r = [1, 5].contains(handle) ? rh : [3, 7].contains(handle) ? rw : max(rw, rh)
            w = size.width * r
            h = size.height * r
        }
        return Size2((w * 10).rounded() / 10, (h * 10).rounded() / 10)
    }

    /// A Scale's end from a handle dragged to `pointer`: how far the handle
    /// is from the anchor now, against how far it was.
    private func scaledEnd(_ edit: CanvasDrag.ActionEdit, handle: Int, pointer: Vec2, linked: Bool) -> Vec2? {
        guard let layer = edit.atEnd, let inverse = edit.worldAtEnd?.inverted else { return nil }
        let local = inverse.apply(pointer)
        let size = layer.size, anchor = layer.anchor
        let hx = [2, 3, 4].contains(handle) ? size.width : [0, 6, 7].contains(handle) ? 0 : anchor.x
        let hy = [4, 5, 6].contains(handle) ? size.height : [0, 1, 2].contains(handle) ? 0 : anchor.y
        var rx = abs(hx - anchor.x) > 0.5 ? (local.x - anchor.x) / (hx - anchor.x) : 1
        var ry = abs(hy - anchor.y) > 0.5 ? (local.y - anchor.y) / (hy - anchor.y) : 1
        if [1, 5].contains(handle) { rx = linked ? ry : 1 }
        if [3, 7].contains(handle) { ry = linked ? rx : 1 }
        if linked, [0, 2, 4, 6].contains(handle) {
            let r = abs(rx) > abs(ry) ? rx : ry
            rx = r
            ry = r
        }
        return Vec2(layer.scale.x * rx, layer.scale.y * ry)
    }

    private func parentInverse(of id: UUID) -> Affine? {
        guard let scene, let project else { return nil }
        guard let parent = project.location(of: id)?.parentID else { return .identity }
        return scene.worldTransform(of: parent)?.inverted
    }

    private func selectInMarquee(_ marquee: CanvasDrag.Marquee) {
        guard let scene, let controller, let project else { return }
        let a = viewToComposition(marquee.start), b = viewToComposition(marquee.current)
        let box = Box(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y))
        let hits = project.layers.filter { layer in
            guard !layer.isLocked, let corners = scene.worldCorners(of: layer.id),
                  let bounds = Box(around: corners) else { return false }
            return bounds.intersects(box)
        }.map(\.id)
        controller.editor.selection = marquee.base.union(hits)
    }

    // MARK: Hover and cursors

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited,
                                                               .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: tool.isShape ? .crosshair : .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        // Only while the canvas is really the view under the pointer, not a
        // panel floating over it.
        guard let content = window?.contentView,
              let top = content.hitTest(content.convert(event.locationInWindow, from: nil)),
              top === self || top.isDescendant(of: self) else {
            setHover(nil)
            return
        }
        guard !tool.isShape else { return }
        setHover(layer(at: viewToComposition(viewPoint), deep: event.modifierFlags.contains(.command)))
        updateCursor(at: viewPoint)
    }

    override func mouseExited(with event: NSEvent) {
        setHover(nil)
    }

    private func setHover(_ id: UUID?) {
        guard hovered != id else { return }
        hovered = id
        redrawOverlay()
    }

    private func updateCursor(at viewPoint: CGPoint) {
        guard let scene, let controller, selection.count == 1, let id = selection.first, !controller.isLocked(id) else { return }
        let view: [CGPoint]
        let line: Bool
        if animating {
            guard let end = actionEndBox() else { return }
            view = end.box
            line = end.isLine
        } else {
            guard let corners = scene.worldCorners(of: id), let resolved = scene.layer(id) else { return }
            view = corners.map(compositionToView)
            line = isLine(resolved)
        }
        if actionKindOnCanvas != .rotate, let handle = CanvasHandles.handle(at: viewPoint, box: view, isLine: line) {
            CanvasHandles.cursor(for: handle).set()
        } else if !animating || actionKindOnCanvas == .rotate, CanvasHandles.isRotateZone(viewPoint, box: view) {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        if EditorKeys.handle(event, controller) { return }
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        switch event.keyCode {
        case 51, 117: controller.deleteSelection()                   // delete, forward delete
        case 53:                                                     // escape
            if drag != nil {
                controller.cancel()
                drag = nil
                redrawOverlay()
            } else {
                controller.deselectAll()
            }
        case 123: controller.nudge(by: Vec2(-step, 0))
        case 124: controller.nudge(by: Vec2(step, 0))
        case 125: controller.nudge(by: Vec2(0, step))
        case 126: controller.nudge(by: Vec2(0, -step))
        default:
            let flags = event.modifierFlags.intersection([.command, .control, .option])
            if flags.isEmpty, !animating, let key = event.charactersIgnoringModifiers, let tool = Tool.forKey(key) {
                controller.editor.tool = tool
                if tool.isShape { controller.editor.lastShape = tool }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Transparency

    private static let checkerColor: CGColor = {
        let cell = 8.0
        let image = NSImage(size: NSSize(width: cell * 2, height: cell * 2), flipped: false) { rect in
            NSColor(white: 0.42, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.52, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: cell, height: cell).fill()
            NSRect(x: cell, y: cell, width: cell, height: cell).fill()
            return true
        }
        return NSColor(patternImage: image).cgColor
    }()
}

