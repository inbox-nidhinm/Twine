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

    /// Draws the project at `time`. Called by SwiftUI whenever anything the
    /// canvas shows changes; it only renders and never writes to the model.
    func show(_ project: Project, time: Double, selection: [UUID], tool: Tool, playing: Bool) {
        setClockRunning(playing)
        self.project = project
        self.selection = selection
        if self.tool != tool {
            self.tool = tool
            window?.invalidateCursorRects(for: self)
        }
        let scene = evaluate(project, at: time)
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
        for id in selection {
            guard let corners = scene.worldCorners(of: id) else { continue }
            outlines.append(corners.map(compositionToView))
        }

        var handles: [CGPoint] = []
        var anchor: CGPoint?
        var union: [CGPoint]?
        if selection.count == 1, let id = selection.first, !controller.isLocked(id),
           let corners = scene.worldCorners(of: id), let layer = scene.layer(id),
           let world = scene.worldTransform(of: id) {
            let view = corners.map(compositionToView)
            handles = CanvasHandles.positions(for: view, isLine: isLine(layer))
            anchor = compositionToView(world.apply(layer.anchor))
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
                       hover: hover, marquee: drag?.marqueeRect)
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

        if tool.isShape {
            drag = .create(CanvasDrag.Create(tool: tool, start: point, layerID: nil))
            return
        }

        // A handle of the one selected layer comes first, before the layers
        // under it, so a handle over another shape still resizes.
        if selection.count == 1, let id = selection.first, !controller.isLocked(id),
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
        case .move, .resize, .rotate, .anchor:
            controller.end()
        case .marquee:
            break
        }
        redrawOverlay()
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
        guard let scene, let controller, selection.count == 1, let id = selection.first, !controller.isLocked(id),
              let corners = scene.worldCorners(of: id), let resolved = scene.layer(id) else { return }
        let view = corners.map(compositionToView)
        if let handle = CanvasHandles.handle(at: viewPoint, box: view, isLine: isLine(resolved)) {
            CanvasHandles.cursor(for: handle).set()
        } else if CanvasHandles.isRotateZone(viewPoint, box: view) {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        if PlaybackKeys.handle(event, controller) { return }
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
            if flags.isEmpty, let key = event.charactersIgnoringModifiers, let tool = Tool.forKey(key) {
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

