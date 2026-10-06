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
    /// For the right-click menu.
    var menus: MenuHost?

    /// What the floating panels cover, so fitting lands in the visible area.
    var insets = NSEdgeInsets() {
        didSet { if !NSEdgeInsetsEqual(insets, oldValue) { layoutWorld() } }
    }

    private let renderer = CoreAnimationRenderer()
    /// Carries the composition from its own space into the view's.
    private let world = CALayer()
    private let checker = CALayer()
    private let frameEdge = CAShapeLayer()
    let overlay = CanvasOverlay()

    private(set) var zoom: Double = 1
    /// How far the composition's centre sits from the centre of the visible area.
    private var pan = CGPoint.zero
    private var hasFitted = false
    private var compositionSize: Size2?

    private(set) var scene: ResolvedScene?
    /// Keeps the layers no action moves from one scene to the next.
    private let evaluation = EvaluationCache()
    private(set) var project: Project?
    private(set) var selection: [UUID] = []
    private(set) var tool: Tool = .select
    /// Animate mode: the canvas shows the playhead's moment and only selects
    /// and moves. Resizing, turning and the anchor are design edits.
    private(set) var animating = false
    /// The layer outlined under the pointer, shared with the layers panel.
    private var hovered: UUID? { controller?.editor.hoveredLayer }
    /// What the canvas itself last hovered, so moving off a layer clears
    /// only its own hover and never one the layers panel has set.
    private var ownHover: UUID?
    /// Space is held: a drag pans rather than acting on layers.
    private var spaceHeld = false
    var drag: CanvasDrag?
    /// What the drag in progress has snapped to, for the guides.
    var snap: Snapping.Result?
    /// What a drag can snap to, gathered as it begins: the boxes of every
    /// layer not being dragged.
    var snapTargets: [Box] = []
    /// A move's boxes when it began, all together.
    private var snapBox: Box?
    /// Typing into a text layer on the canvas, when it is happening.
    var textSession: TextSession?
    /// Blinks the caret while typing.
    var caretTimer: Timer?
    /// A shape's points shown for editing, or the pen drawing, when happening.
    var pathSession: PathSession? {
        didSet { if pathSession != oldValue { publishPickedPoints() } }
    }
    /// A picture being cropped, when happening.
    var cropSession: CropSession?

    /// Ticks with the display while playing, so playback advances in step
    /// with what is shown.
    private var clock: CADisplayLink?
    private var lastTick: CFTimeInterval?

    static let minZoom = 0.02
    static let maxZoom = 64.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
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
        // Out of the window (it turned to the home screen), the playback
        // clock stops, or it would keep the canvas alive.
        if window == nil { setClockRunning(false) }
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
        let modeChanged = self.animating != animating
        self.animating = animating
        self.project = project
        self.selection = selection
        if self.tool != tool {
            self.tool = tool
            window?.invalidateCursorRects(for: self)
        }
        let scene = animating ? evaluate(project, at: time, cache: evaluation) : evaluateDesign(project, cache: evaluation)
        self.scene = scene
        if compositionSize != scene.size {
            // A new size means the old zoom no longer frames anything useful.
            compositionSize = scene.size
            hasFitted = false
        }
        if renderer.media == nil { renderer.media = controller?.media }
        renderer.render(scene)
        checker.isHidden = scene.background != nil
        // Typing stops when its layer goes, is deselected, or the mode changes.
        if let id = textSession?.layerID, modeChanged || playing || !selection.contains(id) || scene.layer(id) == nil {
            endTextEditing()
        }
        validatePathSession()
        validateCropSession()
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

    /// Each selected shape's own outline, in view points, as the user asked,
    /// so its shape shows however it is drawn. Not while its points are
    /// being edited (they draw it), nor while it is tilted (a flat outline
    /// would not follow the perspective).
    private func selectedShapeOutlines(in scene: ResolvedScene, skipping editing: UUID?) -> CGPath? {
        let path = CGMutablePath()
        for id in selection where id != editing {
            guard let layer = scene.layer(id), case .shape(let shape) = layer.content,
                  let outline = ownOutline(shape, of: id, in: scene) else { continue }
            path.addPath(outline)
        }
        return path.isEmpty ? nil : path
    }

    /// A layer's outline under the pointer, as Figma draws it: a shape's or
    /// a frame's own shape, anything else (text, groups, tilted layers) its
    /// box.
    private func hoverOutline(of id: UUID, in scene: ResolvedScene) -> CGPath? {
        if let layer = scene.layer(id) {
            if case .shape(let shape) = layer.content, let outline = ownOutline(shape, of: id, in: scene) { return outline }
            if let frame = layer.frame, let outline = ownOutline(frame, of: id, in: scene) { return outline }
        }
        guard let corners = scene.worldCorners(of: id), corners.count > 1 else { return nil }
        let path = CGMutablePath()
        path.addLines(between: corners.map(compositionToView))
        path.closeSubpath()
        return path
    }

    /// A shape's path in view points, or nil when it is tilted.
    private func ownOutline(_ shape: ResolvedShape, of id: UUID, in scene: ResolvedScene) -> CGPath? {
        guard !isTilted(id, in: scene), let w = scene.worldTransform(of: id) else { return nil }
        let o = origin
        let toView = CGAffineTransform(a: w.a * zoom, b: w.b * zoom, c: w.c * zoom, d: w.d * zoom,
                                       tx: w.tx * zoom + o.x, ty: w.ty * zoom + o.y)
        let path = CGMutablePath()
        path.addPath(shape.path.cgPath, transform: toView)
        return path
    }

    func redrawOverlay() {
        guard let scene, let controller else { return }
        var outlines: [[CGPoint]] = []
        let endBox = actionEndBox()
        // While a shape's points are showing, they stand in for its box.
        let editingPoints = isEditingPoints ? pathSession?.layerID : nil
        for id in selection where id != editingPoints {
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
        // A selected Resize or Scale shows its handles at its end, to set it;
        // otherwise the layer's own, in Animate too (5 October 2026), where
        // they change its design and its animation follows.
        if let endBox, actionKindOnCanvas != .rotate {
            handles = CanvasHandles.positions(for: endBox.box, isLine: endBox.isLine)
        } else if endBox == nil, selection.count == 1, let id = selection.first, id != editingPoints, !controller.isLocked(id),
                  !(animating && controller.editor.isPlaying),
           let corners = scene.worldCorners(of: id), let layer = scene.layer(id),
           let world = scene.worldProjection(of: id) {
            let view = corners.map(compositionToView)
            // A tilted layer's outline follows its perspective; handles
            // would not, so it is sized in the inspector.
            if !isTilted(id, in: scene) { handles = CanvasHandles.positions(for: view, isLine: isLine(layer)) }
            if !animating, let a = world.apply(layer.anchor) { anchor = compositionToView(a) }
        } else if selection.count > 1 {
            let points = outlines.flatMap { $0 }
            if let first = points.first {
                let box = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
                union = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                         CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            }
        }

        // A selected layer shows only its box: no wash under the pointer,
        // as the user asked.
        var hover: CGPath?
        if let hovered, drag == nil, hovered != editingPoints, !selection.contains(hovered) {
            hover = hoverOutline(of: hovered, in: scene)
        }

        // While typing, the box shows without handles: the letters are
        // being edited, not the layer.
        if textSession != nil {
            handles = []
            anchor = nil
        }
        // While cropping, the handles crop, and the layer is not turned or
        // moved about its anchor.
        if isCropping { anchor = nil }
        // A gradient's line shows over the layer's handles.
        let gradient = gradientMarks()
        overlay.update(outlines: outlines, union: union, handles: handles, anchor: anchor,
                       hover: textSession == nil ? hover : nil,
                       marquee: drag?.marqueeRect, motion: motionOverlay())
        overlay.updateShapes(selectedShapeOutlines(in: scene, skipping: editingPoints))
        let marks = snapMarks()
        overlay.updateSnap(lines: marks.lines, gaps: marks.gaps)
        updateTextOverlay()
        overlay.updatePath(pathSession == nil ? nil : pathMarks())
        overlay.updateCrop(isCropping ? cropMarks() : nil)
        overlay.updateGradient(gradient)
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
    /// as in Figma; Command reaches the layer itself. A masked layer is only
    /// picked where the mask lets it show. A mask draws nothing of its own, so
    /// it is picked only once selected (from the layers panel), to be moved.
    func layer(at point: Vec2, deep: Bool) -> UUID? {
        guard let scene, let controller else { return nil }
        let tolerance = 5 / zoom
        // Found once: asking for each layer searched the whole project for
        // its groups, which over thousands of layers took seconds a click.
        let locked = controller.project.lockedLayers
        for id in selection {
            guard let mask = scene.mask(id), !locked.contains(id),
                  let world = scene.worldProjection(of: id), let local = world.inverted?.apply(point) else { continue }
            if hits(mask, at: local.cg, tolerance: tolerance / max(sqrt(abs(world.determinant)), 1e-6)) {
                return id
            }
        }
        // By place, front first: `reversed()` and `for in` copied every
        // layer looked at.
        let layers = scene.layers
        for i in layers.indices.reversed() {
            // A plain group draws nothing of its own; a frame does.
            // Through what is drawn, tilts and all, so a click lands on what it sees.
            guard layers[i].content != .group || layers[i].frame != nil, !locked.contains(layers[i].id),
                  let world = scene.worldProjection(of: layers[i].id), let local = world.inverted?.apply(point)?.cg else { continue }
            // Scale the tolerance into the layer's space, so it is the same
            // few screen points whatever the layer's own scale.
            let localTolerance = tolerance / max(sqrt(abs(world.determinant)), 1e-6)
            guard hits(layers[i], at: local, tolerance: localTolerance), shows(layers[i], at: local, in: scene) else { continue }
            return deep ? layers[i].id : inContext(layers[i].id)
        }
        return nil
    }

    /// Which of a layer and the groups and frames around it a click picks:
    /// the outermost, as in Figma, unless the selection is already further
    /// in. Once inside a group (by a double-click), a click stays at that
    /// level: on the selected layer, on one beside it, or on what holds it.
    private func inContext(_ id: UUID) -> UUID {
        guard let project else { return id }
        let chain = project.ancestors(of: id) + [id]
        if let selected = chain.last(where: selection.contains) { return selected }
        let holders = Set(selection.compactMap { project.location(of: $0)?.parentID })
        if let i = chain.lastIndex(where: holders.contains), i + 1 < chain.count { return chain[i + 1] }
        return topLevel(of: id)
    }

    /// Whether a point in the layer's own space lands on what it draws: a
    /// shape's or a frame's fill or stroke, or anywhere in a text's or
    /// video's box.
    private func hits(_ resolved: ResolvedLayer, at local: CGPoint, tolerance: Double) -> Bool {
        let outline: ResolvedShape?
        if case .shape(let s) = resolved.content { outline = s } else { outline = resolved.frame }
        if let shape = outline {
            // A shape's path lies within its box, so a point beyond the box
            // and its widest stroke misses without the path being made, which
            // for every layer under a moving pointer was most of the work.
            let reach = (shape.strokes.map(\.width).max() ?? 0) / 2 + tolerance
            guard CGRect(origin: .zero, size: resolved.size.cg).insetBy(dx: -reach, dy: -reach).contains(local) else { return false }
            let path = shape.path.cgPath
            if shape.isClosed && (!shape.fills.isEmpty || shape.strokes.isEmpty) && path.contains(local, using: shape.fillRule.cg) {
                return true
            }
            let width = (shape.strokes.map(\.width).max() ?? 0) + tolerance * 2
            return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(local)
        }
        return CGRect(origin: .zero, size: resolved.size.cg).insetBy(dx: -tolerance, dy: -tolerance).contains(local)
    }

    /// Whether the layer's mask, if it has one, lets it show at a point in
    /// its own space, and whether any group or frame it sits in that clips
    /// lets it show there. A group's mask is honoured by its children too.
    private func shows(_ resolved: ResolvedLayer, at local: CGPoint, in scene: ResolvedScene) -> Bool {
        var layer: ResolvedLayer? = resolved
        var point = Vec2(Double(local.x), Double(local.y))
        while let current = layer {
            if let mask = current.mask, let source = scene.mask(mask.layerID), let inverse = mask.transform.inverted,
               let inMask = inverse.apply(point) {
                if !hits(source, at: inMask.cg, tolerance: 0) { return false }
            }
            guard let up = current.projection.apply(point) else { return false }
            point = up
            layer = current.parentID.flatMap { scene.layer($0) }
            if let parent = layer, parent.clipsContent {
                let inside = parent.frame.map { $0.path.cgPath.contains(point.cg) }
                    ?? CGRect(origin: .zero, size: parent.size.cg).contains(point.cg)
                if !inside { return false }
            }
        }
        return true
    }

    /// The innermost frame whose box a composition point is in, which a
    /// layer drawn there goes into.
    func frame(under point: Vec2) -> UUID? {
        guard let scene, let controller else { return nil }
        let locked = controller.project.lockedLayers
        for resolved in scene.layers.reversed() where resolved.frame != nil && !locked.contains(resolved.id) {
            guard let inverse = scene.worldTransform(of: resolved.id)?.inverted else { continue }
            if CGRect(origin: .zero, size: resolved.size.cg).contains(inverse.apply(point).cg) { return resolved.id }
        }
        return nil
    }

    private func topLevel(of id: UUID) -> UUID {
        guard let project else { return id }
        // The outermost unlocked group, so a click on a shape in a group
        // selects the group, and in a locked group selects nothing above it.
        return project.ancestors(of: id).first ?? id
    }

    // MARK: Dropping files

    private func importable(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { MediaImport.kind(of: $0) != nil }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        importable(sender).isEmpty ? [] : .copy
    }

    /// Pictures, video and sound dropped on the canvas come in where they
    /// land.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = importable(sender)
        guard !urls.isEmpty, let controller else { return false }
        controller.importMedia(urls, at: viewToComposition(convert(sender.draggingLocation, from: nil)))
        return true
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        // A Control-click is a right-click.
        if event.modifierFlags.contains(.control) { return rightMouseDown(with: event) }
        window?.makeFirstResponder(self)
        controller?.editor.focus = .canvas
        if dismissTransients() { return }
        guard let controller, let scene else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = viewToComposition(viewPoint)
        let shift = event.modifierFlags.contains(.shift)

        if spaceHeld { return beginPan(event) }

        // While typing, a click on the text places the caret; anywhere else
        // it ends the typing and carries on as a click.
        if textMouseDown(event, at: point) { return }

        // The pen, and a shape's points while they show, come before layers.
        if pathMouseDown(event, at: point, viewPoint: viewPoint) {
            redrawOverlay()
            return
        }

        // So does a picture being cropped.
        if cropMouseDown(event, at: point, viewPoint: viewPoint) {
            redrawOverlay()
            return
        }

        // And a gradient's line while it is being edited.
        if gradientMouseDown(event, at: point, viewPoint: viewPoint) {
            redrawOverlay()
            return
        }

        // The drawing tools work in Animate too (5 October 2026), drawing
        // into frames as they are at the playhead.
        if tool.draws {
            snapTargets = targets(excluding: [])
            drag = .create(CanvasDrag.Create(tool: tool, start: snapped(point, event), layerID: nil,
                                             parentID: frame(under: point)))
            return
        }

        // The Text tool places a text layer where it is clicked and puts the
        // keyboard in its text box, then hands back the arrow.
        if tool == .text {
            controller.editor.tool = .select
            let parent = frame(under: point)
            if let id = controller.addText(at: point, in: parent, parentWorld: animating ? parentWorld(parent) : nil) {
                beginTextEditing(id, selectAll: true)
            }
            return
        }

        // A handle of the one selected layer comes first, before the layers
        // under it, so a handle over another shape still resizes, and in
        // Animate before a selected Move, whose layer it sits on. A selected
        // Resize, Scale or Rotate has its own handles instead.
        if selection.count == 1, let id = selection.first, !controller.isLocked(id), !isTilted(id, in: scene),
           actionEndBox() == nil, !(animating && controller.editor.isPlaying),
           let layer = controller.project.layer(withID: id), let resolved = scene.layer(id),
           let corners = scene.worldCorners(of: id), let world = scene.worldTransform(of: id) {
            let view = corners.map(compositionToView)
            let anchorView = compositionToView(world.apply(resolved.anchor))
            // The anchor sits in the middle of the layer, which is exactly
            // where a move usually starts, so moving it takes Command.
            // The anchor is Design's.
            if !animating, event.modifierFlags.contains(.command),
               hypot(viewPoint.x - anchorView.x, viewPoint.y - anchorView.y) <= CanvasHandles.hitRadius {
                drag = .anchor(CanvasDrag.Edit(layer: layer, start: point))
                controller.begin("Move Anchor")
                return
            }
            if let handle = CanvasHandles.handle(at: viewPoint, box: view, isLine: isLine(resolved)) {
                snapTargets = targets(excluding: [id])
                // In Animate, worked out on the layer as it shows, and
                // carried back into its design.
                drag = .resize(animating ? CanvasDrag.Resize(layer: AnimateEditing.shown(layer, as: resolved), handle: handle,
                                                             start: point, design: layer)
                                         : CanvasDrag.Resize(layer: layer, handle: handle, start: point))
                controller.begin(layer.isGroup && !layer.isFrame ? "Scale" : "Resize")
                return
            }
            if CanvasHandles.isRotateZone(viewPoint, box: view) {
                drag = .rotate(CanvasDrag.Edit(layer: layer, start: point))
                controller.begin("Rotate")
                return
            }
        }

        // Then the selected action's own handles and path, in Animate.
        if animating, let action = controller.canvasAction,
           beginActionEdit(action, at: point, viewPoint: viewPoint, commandHeld: event.modifierFlags.contains(.command)) {
            redrawOverlay()
            return
        }

        let deep = event.modifierFlags.contains(.command)
        if let hit = layer(at: point, deep: deep) {
            // Shift on a layer already selected takes it out only once the
            // press turns out to be a click, as in Figma (4 October 2026):
            // taken out at the press, a Shift-drag to keep a move level or
            // upright had nothing left to move.
            var deselectsOnClick: UUID?
            if shift, selection.contains(hit) {
                deselectsOnClick = hit
            } else if shift {
                controller.select([hit], extending: true)
            } else if !selection.contains(hit) {
                controller.select([hit])
            }
            if event.clickCount == 2, controller.project.layer(withID: hit)?.isGroup == true,
               let deepest = layer(at: point, deep: true), deepest != hit {
                // A double-click goes one level into a group or frame, as in
                // Figma.
                let chain = controller.project.ancestors(of: deepest) + [deepest]
                let inner = chain.firstIndex(of: hit).map { chain[$0 + 1] } ?? deepest
                controller.select([inner])
            } else if event.clickCount == 2, controller.project.layer(withID: hit)?.isText == true,
                      !controller.isLocked(hit) {
                // And on text, it starts typing where it was clicked.
                return beginTextEditing(hit, selectAll: false, at: point)
            } else if event.clickCount == 2, !animating, controller.project.layer(withID: hit)?.picture != nil,
                      !controller.isLocked(hit) {
                // And on a picture, it crops it, as in Figma.
                controller.setPictureMode(hit, .crop)
                return redrawOverlay()
            } else if event.clickCount == 2, !animating, let layer = controller.project.layer(withID: hit),
                      PathEditing.canEditPoints(layer), !controller.isLocked(hit) {
                // And on a shape, it shows its points.
                return beginPathEditing(hit)
            }
            var moving = controller.topmost(controller.selectedLayers).filter { !controller.isLocked($0.id) }
            let sources = Set(moving.map(\.id))
            let boxes = moving.compactMap { scene.bounds(of: $0.id) }
            snapBox = boxes.dropFirst().reduce(boxes.first) { $0?.union($1) }
            // Option-drag leaves the originals behind and drags copies of
            // them, actions and all, as in Figma. The originals stay snap
            // targets.
            let duplicating = event.modifierFlags.contains(.option) && !moving.isEmpty
            if duplicating {
                controller.begin(moving.count == 1 ? "Duplicate Layer" : "Duplicate Layers")
                moving = controller.duplicateForDrag(moving)
            } else {
                controller.begin(moving.count == 1 ? "Move Layer" : "Move Layers")
            }
            snapTargets = targets(excluding: Set(moving.map(\.id)))
            drag = .move(CanvasDrag.Move(originals: moving, start: point, duplicating: duplicating, sources: sources,
                                         deselectsOnClick: deselectsOnClick))
        } else {
            if !shift { controller.deselectAll() }
            drag = .marquee(CanvasDrag.Marquee(start: viewPoint, current: viewPoint, additive: shift,
                                               base: shift ? Set(selection) : []))
        }
        redrawOverlay()
    }

    override func mouseDragged(with event: NSEvent) {
        if textSession != nil, textMouseDragged(at: viewToComposition(convert(event.locationInWindow, from: nil))) { return }
        guard let controller, let drag else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = viewToComposition(viewPoint)
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)

        switch drag {
        case .pan(let p):
            return continuePan(event, p)

        case .create(var create):
            // Held square, the corner follows the square rather than a guide.
            let reach = shift ? point : snapped(point, event, shaping: Box(around: [create.start, point]))
            let end = CanvasGeometry.constrainedEnd(create.start, reach, tool: create.tool, square: shift)
            let from = option && create.tool != .line ? Vec2(2 * create.start.x - end.x, 2 * create.start.y - end.y) : create.start
            guard let made = controller.makeShape(create.tool, from: from, to: end) else { return }
            var layer = placed(made, into: create.parentID)
            if let id = create.layerID, let existing = controller.project.layer(withID: id) {
                // Keep the first frame's id and name, so the shape is one
                // layer being drawn rather than a new one every step.
                layer = existing.replacingGeometry(with: layer)
                controller.update([layer])
            } else {
                controller.begin("Add \(create.tool.title)")
                controller.update(.insertLayers([layer], parentID: create.parentID, index: nil))
                create.layerID = layer.id
                controller.select([layer.id])
                self.drag = .create(create)
            }

        case .move(let move):
            guard let scene else { return }
            var delta = point - move.start
            var axes: Set<Snapping.Axis> = [.x, .y]
            if shift {
                let across = abs(delta.x) >= abs(delta.y)
                delta = across ? Vec2(delta.x, 0) : Vec2(0, delta.y)
                axes = across ? [.x] : [.y]
            }
            snap = nil
            if snapping(event), let box = snapBox {
                let result = Snapping.move(box.moved(by: delta), targets: snapTargets, frame: frameBox,
                                           threshold: snapReach, axes: axes)
                delta = delta + result.offset
                snap = result
            }
            controller.update(move.originals.map { $0.translated(by: controller.parentDelta(delta, for: $0.id, in: scene)) })

        case .resize(let resize):
            guard let parentInverse = parentInverse(of: resize.layer.id) else { return }
            // A layer set to keep its proportions keeps them as Shift would.
            let keep = shift || resize.layer.keepsProportions
            func resized(_ pointer: Vec2) -> Layer {
                CanvasGeometry.resized(resize.layer, handle: resize.handle, pointer: parentInverse.apply(pointer),
                                       keepAspect: keep, fromCenter: option)
            }
            var edited = resized(point)
            // Kept to its proportions, a corner cannot follow a guide on
            // both axes, so only a free resize snaps.
            snap = nil
            if snapping(event), !keep, let parentWorld = parentInverse.inverted,
               let result = snapped(edited, handle: resize.handle, parentWorld: parentWorld),
               result.offset != .zero || !result.guides.isEmpty {
                edited = resized(point + result.offset)
                snap = snapped(edited, handle: resize.handle, parentWorld: parentWorld)
            }
            // A text box given a new width keeps it and wraps inside it; its
            // height always follows its lines.
            if case .text(var t) = edited.content, abs(edited.size.width - resize.layer.size.width) > 0.5 {
                t.sizing = .fixedWidth
                edited.content = .text(t)
            }
            if let design = resize.design {
                controller.update(controller.animatedUpdate([AnimateEditing.designed(design, shown: resize.layer, edited: edited)]))
            } else {
                controller.update([edited])
            }

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
            if animating { controller.update(controller.animatedUpdate([layer])) } else { controller.update([layer]) }

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

        case .path(let edit):
            pathMouseDragged(edit, point: point, viewPoint: viewPoint, event: event)

        case .crop(let edit):
            cropMouseDragged(edit, point: point, event: event)
        case .gradient(let edit):
            gradientMouseDragged(edit, point: point, viewPoint: viewPoint, event: event)
        }
        redrawOverlay()
    }

    override func mouseUp(with event: NSEvent) {
        if textMouseUp() { return }
        guard let controller, let drag else { return }
        self.drag = nil
        snap = nil
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
                if let made = controller.makeShape(create.tool, from: start, to: end) {
                    let layer = placed(made, into: create.parentID)
                    let insert = EditorCommand.insertLayers([layer], parentID: create.parentID, index: nil)
                    // A frame takes in the layers it lands around, as in Figma.
                    let taking = layer.isFrame ? controller.enclosing(layer.id, after: insert) : nil
                    if controller.perform(taking.map { .batch([insert, $0], name: "Add Frame") } ?? insert) {
                        controller.select([layer.id])
                    }
                }
            } else {
                if create.tool == .frame, let id = create.layerID, let taking = controller.enclosing(id) {
                    controller.update(taking)
                }
                controller.end()
            }
            // Back to the arrow after drawing, as in Figma.
            controller.editor.tool = .select
        case .move(let move) where move.duplicating
            && viewToComposition(convert(event.locationInWindow, from: nil)) == move.start:
            // Option-clicked without moving: no copies after all.
            controller.cancel()
            controller.editor.selection = move.sources
        case .move(let move) where move.deselectsOnClick != nil && isClick(event, from: move.start):
            // Shift-clicked a selected layer without dragging: it leaves the
            // selection, and any wobble of the press is taken back.
            controller.cancel()
            if let id = move.deselectsOnClick { controller.select([id], extending: true) }
        case .move, .resize, .rotate, .anchor, .action:
            controller.end()
        case .marquee:
            break
        case .path(let edit):
            pathMouseUp(edit, event: event)
        case .crop(let edit):
            cropMouseUp(edit)
        case .gradient(let edit):
            gradientMouseUp(edit, point: viewToComposition(convert(event.locationInWindow, from: nil)))
        case .pan:
            (spaceHeld ? Cursors.hand : Cursors.arrow).set()
        }
        redrawOverlay()
    }

    /// Whether `event` is let go within a click's reach of `start`.
    private func isClick(_ event: NSEvent, from start: Vec2) -> Bool {
        let here = convert(event.locationInWindow, from: nil), there = compositionToView(start)
        return hypot(here.x - there.x, here.y - there.y) <= CanvasHandles.clickReach
    }

    // MARK: Snapping

    /// How near counts as lined up: a few screen points at any zoom.
    var snapReach: Double { 6 / zoom }

    var frameBox: Box { Box(origin: .zero, size: scene?.size ?? Size2(0, 0)) }

    /// Snapping is on, and Command is not held to set it aside for a moment.
    func snapping(_ event: NSEvent) -> Bool {
        controller?.editor.snaps == true && !event.modifierFlags.contains(.command)
    }

    /// The boxes of every drawn layer except those in `moving` and anything
    /// inside them. Groups are left out: their layers are there instead.
    func targets(excluding moving: Set<UUID>) -> [Box] {
        guard let scene else { return [] }
        snap = nil
        // Groups found through the scene, a step at a time: asking the
        // project for each layer's searched the whole tree every time, and
        // a press in a project of 5,000 layers stuck for seconds.
        func carried(_ id: UUID) -> Bool {
            var parent = scene.parentID(of: id)
            while let p = parent {
                if moving.contains(p) { return true }
                parent = scene.parentID(of: p)
            }
            return false
        }
        let layers = scene.layers
        return layers.indices.compactMap { i in
            guard layers[i].content != .group || layers[i].frame != nil, !moving.contains(layers[i].id),
                  !carried(layers[i].id) else { return nil }
            return scene.bounds(of: layers[i].id)
        }
    }

    /// A point being drawn to, pulled onto a guide when one is near.
    func snapped(_ point: Vec2, _ event: NSEvent, shaping box: Box? = nil) -> Vec2 {
        snap = nil
        guard snapping(event) else { return point }
        let result = Snapping.point(point, box: box ?? Box(around: [point])!, targets: snapTargets, frame: frameBox,
                                    threshold: snapReach)
        snap = result
        return point + result.offset
    }

    /// Where a resize handle wants to go to line up. Only for a layer that
    /// sits upright on screen, since a turned box has no edges to line up.
    private func snapped(_ layer: Layer, handle: Int, parentWorld: Affine) -> Snapping.Result? {
        let t = layer.transform
        let world = Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew).then(parentWorld)
        guard abs(world.b) < 1e-9, abs(world.c) < 1e-9,
              let box = Box(around: Box(origin: .zero, size: layer.size).corners.map(world.apply)) else { return nil }
        let left = [0, 6, 7].contains(handle), right = [2, 3, 4].contains(handle)
        let top = [0, 1, 2].contains(handle), bottom = [4, 5, 6].contains(handle)
        let w = layer.size.width, h = layer.size.height
        let local = Vec2(left ? 0 : right ? w : w / 2, top ? 0 : bottom ? h : h / 2)
        var axes = Set<Snapping.Axis>()
        if left || right { axes.insert(.x) }
        if top || bottom { axes.insert(.y) }
        return Snapping.point(world.apply(local), box: box, targets: snapTargets, frame: frameBox,
                              threshold: snapReach, axes: axes)
    }

    /// The guides and gaps in view points.
    private func snapMarks() -> (lines: [(CGPoint, CGPoint)], gaps: [CanvasOverlay.GapMark]) {
        guard let snap else { return ([], []) }
        let lines = snap.guides.map { g -> (CGPoint, CGPoint) in
            g.axis == .x ? (compositionToView(Vec2(g.value, g.from)), compositionToView(Vec2(g.value, g.to)))
                         : (compositionToView(Vec2(g.from, g.value)), compositionToView(Vec2(g.to, g.value)))
        }
        let gaps = snap.gaps.map { g -> CanvasOverlay.GapMark in
            let a = g.axis == .x ? Vec2(g.start, g.cross) : Vec2(g.cross, g.start)
            let b = g.axis == .x ? Vec2(g.end, g.cross) : Vec2(g.cross, g.end)
            return CanvasOverlay.GapMark(from: compositionToView(a), to: compositionToView(b),
                                         label: GuideLabel.text(g.length))
        }
        return (lines, gaps)
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
        default:
            // Opacity, visibility, styles and blurs have nothing to drag on
            // the canvas; a drag moves the layer as usual.
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

    /// A layer made in composition space, carried into `parentID`'s space
    /// where it shows: in Animate, the parent as it is at the playhead.
    func placed(_ layer: Layer, into parentID: UUID?) -> Layer {
        guard let controller else { return layer }
        if animating { return Arrangement.placed(layer, into: parentID, parentWorld: parentWorld(parentID)) }
        return Arrangement.placed(layer, into: parentID, in: controller.project)
    }

    /// A group's or frame's own space into the composition's, as it shows.
    func parentWorld(_ parentID: UUID?) -> Affine? {
        guard let parentID else { return nil }
        return scene?.worldTransform(of: parentID)
    }

    func parentInverse(of id: UUID) -> Affine? {
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
        addCursorRect(bounds, cursor: spaceHeld ? Cursors.hand : tool == .text ? .iBeam : tool.draws ? Cursors.crosshair
                                      : tool == .pen ? Cursors.pen : Cursors.arrow)
        // While typing, the text being edited takes the I-beam.
        if let id = textSession?.layerID, let corners = scene?.worldCorners(of: id) {
            let points = corners.map(compositionToView)
            let xs = points.map(\.x), ys = points.map(\.y)
            addCursorRect(CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!),
                          cursor: .iBeam)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        // Only while the canvas is really the view under the pointer, not a
        // panel floating over it.
        guard let top = (window as? ChromelessWindow)?.viewUnder(event.locationInWindow),
              top === self || top.isDescendant(of: self) else {
            setHover(nil)
            return
        }
        guard !spaceHeld else { return }
        if pathMouseMoved(viewPoint, event: event) { return }
        guard !tool.draws, tool != .text else { return }
        if tool == .select, gradientMouseMoved(viewPoint, event: event) {
            setHover(nil)
            return
        }
        setHover(layer(at: viewToComposition(viewPoint), deep: event.modifierFlags.contains(.command)))
        updateCursor(at: viewPoint)
    }

    override func mouseExited(with event: NSEvent) {
        setHover(nil)
    }

    func setHover(_ id: UUID?) {
        guard let editor = controller?.editor, ownHover != id else { return }
        let previous = ownHover
        ownHover = id
        if let id { editor.hoveredLayer = id } else if editor.hoveredLayer == previous { editor.hoveredLayer = nil }
    }

    private func updateCursor(at viewPoint: CGPoint) {
        guard let scene, let controller, selection.count == 1, let id = selection.first, !controller.isLocked(id) else {
            return Cursors.arrow.set()
        }
        if isCropping {
            if let corner = cropCursor(at: viewPoint) { return corner.set() }
            // The layer's handles crop, and nothing turns.
            guard let box = cropBoxCorners, CanvasHandles.handle(at: viewPoint, box: box, isLine: false) != nil else {
                return Cursors.arrow.set()
            }
        }
        let view: [CGPoint]
        let line: Bool
        if let end = actionEndBox() {
            view = end.box
            line = end.isLine
        } else {
            guard !isTilted(id, in: scene), let corners = scene.worldCorners(of: id), let resolved = scene.layer(id) else { return Cursors.arrow.set() }
            view = corners.map(compositionToView)
            line = isLine(resolved)
        }
        cursor(at: viewPoint, box: view, isLine: line).set()
    }

    /// Over a handle, the resize arrows that follow its direction; just past
    /// a corner, the turn arrows curling round it; otherwise the arrow.
    private func cursor(at viewPoint: CGPoint, box view: [CGPoint], isLine line: Bool) -> NSCursor {
        let center = CGPoint(x: view.map(\.x).reduce(0, +) / 4, y: view.map(\.y).reduce(0, +) / 4)
        func away(_ p: CGPoint) -> CGVector { CGVector(dx: p.x - center.x, dy: p.y - center.y) }
        if actionKindOnCanvas != .rotate, let handle = CanvasHandles.handle(at: viewPoint, box: view, isLine: line),
           let point = CanvasHandles.point(handle, in: view) {
            return Cursors.resize(toward: away(point))
        }
        if actionKindOnCanvas == .rotate || actionEndBox() == nil, CanvasHandles.isRotateZone(viewPoint, box: view),
           let corner = view.min(by: { hypot($0.x - viewPoint.x, $0.y - viewPoint.y) < hypot($1.x - viewPoint.x, $1.y - viewPoint.y) }) {
            return Cursors.rotate(toward: away(corner))
        }
        return Cursors.arrow
    }

    // MARK: Panning with Space

    /// Space's release goes to whoever has the keyboard, so losing it ends
    /// the hand rather than leaving it stuck on.
    override func resignFirstResponder() -> Bool {
        if spaceHeld {
            spaceHeld = false
            window?.invalidateCursorRects(for: self)
        }
        return super.resignFirstResponder()
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, spaceHeld {
            spaceHeld = false
            if drag == nil { Cursors.arrow.set() }
            window?.invalidateCursorRects(for: self)
            return
        }
        super.keyUp(with: event)
    }

    /// Starts panning from a press, with Space held or the middle button.
    private func beginPan(_ event: NSEvent) {
        drag = .pan(CanvasDrag.Pan(start: convert(event.locationInWindow, from: nil), origin: pan))
        Cursors.handGrabbed.set()
    }

    private func continuePan(_ event: NSEvent, _ p: CanvasDrag.Pan) {
        let now = convert(event.locationInWindow, from: nil)
        pan = CGPoint(x: p.origin.x + now.x - p.start.x, y: p.origin.y + now.y - p.start.y)
        hasFitted = true
        layoutWorld()
    }

    override func otherMouseDown(with event: NSEvent) {
        guard drag == nil else { return }
        beginPan(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        if case .pan(let p) = drag { continuePan(event, p) }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard case .pan = drag else { return }
        drag = nil
        (spaceHeld ? Cursors.hand : Cursors.arrow).set()
    }

    /// Whether a layer, or a group or frame it sits in, is tilted: its
    /// outline follows the perspective, but the handles' flat maths would
    /// not, so they hide and it is sized in the inspector.
    func isTilted(_ id: UUID, in scene: ResolvedScene) -> Bool {
        var current = scene.layer(id)
        while let layer = current {
            if layer.tilt.isTilted { return true }
            current = layer.parentID.flatMap { scene.layer($0) }
        }
        return false
    }

    // MARK: Right-click

    /// The layers panel's menu, for the layer under the pointer, which is
    /// selected first unless it already is (so a selection of several keeps
    /// together). Over nothing, it deselects and offers Paste.
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.editor.focus = .canvas
        _ = dismissTransients()
        guard let controller, let menus, drag == nil, !isEditingText, let content = window?.contentView else { return }
        let point = viewToComposition(convert(event.locationInWindow, from: nil))
        let inContent = content.convert(event.locationInWindow, from: nil)
        // The menu's space has its origin at the top-left.
        let origin = CGPoint(x: inContent.x, y: content.isFlipped ? inContent.y : content.bounds.height - inContent.y)
        if let id = layer(at: point, deep: event.modifierFlags.contains(.command)),
           let layer = controller.project.layer(withID: id) {
            if !selection.contains(id) { controller.select([id]) }
            menus.show(controller.layerMenu(for: layer), at: origin)
        } else {
            controller.deselectAll()
            guard controller.canPaste else { return }
            menus.show([.item("Paste") { controller.paste() }], at: origin)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        if ExportKeys.handle(event, controller) { return }
        if textKeyDown(event) { return }
        if pathKeyDown(event) { return }
        if cropKeyDown(event) { return }
        if gradientKeyDown(event) { return }
        // Return on one selected text layer starts typing into it.
        if event.keyCode == 36, selection.count == 1, let id = selection.first,
           controller.project.layer(withID: id)?.isText == true, !controller.isLocked(id) {
            return beginTextEditing(id, selectAll: true)
        }
        // In Design, holding Space turns the pointer into a hand that pans.
        // (In Animate, Space plays.)
        if event.keyCode == 49, !animating, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if !spaceHeld {
                spaceHeld = true
                setHover(nil)
                if drag == nil { Cursors.hand.set() }
                window?.invalidateCursorRects(for: self)
                redrawOverlay()
            }
            return
        }
        if EditorKeys.handle(event, controller) { return }
        if !animating, AlignKeys.handle(event, controller) { return }
        let step = event.modifierFlags.contains(.shift) ? AppSettings.shared.shiftNudge : AppSettings.shared.nudge
        switch event.keyCode {
        case 51 where event.modifierFlags.contains(.command):         // ⌘⌫ ungroups groups and frames
            controller.ungroupSelection()
        case 51, 117: controller.deleteSelection()                   // delete, forward delete
        case 53:                                                     // escape
            if dismissTransients() {
                // An open menu closes first.
            } else if controller.editor.tool != .select, drag == nil {
                // A tool in hand goes back to the arrow, as in Figma.
                controller.editor.tool = .select
            } else if controller.editor.showShortcuts {
                controller.editor.showShortcuts = false
            } else if drag != nil {
                controller.cancel()
                drag = nil
                snap = nil
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
            // The tools' keys work in Animate too, where there is no bar.
            if flags.isEmpty, let key = event.charactersIgnoringModifiers, let tool = Tool.forKey(key) {
                controller.editor.tool = tool
                if tool.isShape { controller.editor.lastShape = tool }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Menu commands while typing

    /// While typing, Copy, Cut, Paste, Select All, Delete, Undo and Redo work
    /// on the letters; otherwise the canvas lets them pass to the window,
    /// where they work on layers.
    nonisolated private static let textActions: Set<Selector> = [
        #selector(NSText.copy(_:)), #selector(NSText.cut(_:)), #selector(NSText.paste(_:)),
        #selector(NSText.selectAll(_:)), #selector(NSText.delete(_:)), Selector(("undo:")), Selector(("redo:")),
    ]

    /// AppKit asks this from the main thread, when it looks for a menu
    /// command's target.
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if let aSelector, Self.textActions.contains(aSelector) {
            return MainActor.assumeIsolated { isEditingText }
        }
        return super.responds(to: aSelector)
    }

    @objc func copy(_ sender: Any?) { textCopy(sender) }
    @objc func cut(_ sender: Any?) { textCut(sender) }
    @objc func paste(_ sender: Any?) { textPaste(sender) }
    @objc func delete(_ sender: Any?) { _ = textCommand(#selector(deleteBackward(_:))) }
    @objc func undo(_ sender: Any?) { textUndo(sender) }
    @objc func redo(_ sender: Any?) { textRedo(sender) }
    override func selectAll(_ sender: Any?) { textSelectAll(sender) }

    override func doCommand(by selector: Selector) {
        if textCommand(selector) { return }
        super.doCommand(by: selector)
    }

    // MARK: Transparency

    /// The checkerboard behind a transparent composition, shared with the
    /// export preview.
    static let checkerColor: CGColor = {
        let cell = Theme.checkerCell
        let image = NSImage(size: NSSize(width: cell * 2, height: cell * 2), flipped: false) { rect in
            NSColor(Theme.checkerDark).setFill()
            rect.fill()
            NSColor(Theme.checkerLight).setFill()
            NSRect(x: 0, y: 0, width: cell, height: cell).fill()
            NSRect(x: cell, y: cell, width: cell, height: cell).fill()
            return true
        }
        return NSColor(patternImage: image).cgColor
    }()
}


private extension Box {
    func moved(by d: Vec2) -> Box { Box(minX: minX + d.x, minY: minY + d.y, maxX: maxX + d.x, maxY: maxY + d.y) }
}

/// A distance as the guides label it: whole pixels, or one decimal place
/// when it falls between.
enum GuideLabel {
    static func text(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}
