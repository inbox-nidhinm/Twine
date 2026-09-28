import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// What a drag on the canvas is doing, from mouse down to mouse up.
enum CanvasDrag {
    struct Create {
        var tool: Tool
        var start: Vec2
        /// Nil until the pointer has moved, so a plain click can make a
        /// standard-size shape instead.
        var layerID: UUID?
        /// The frame the press landed in, which the new layer goes into, as
        /// in Figma. Nil for the top level.
        var parentID: UUID? = nil
    }

    struct Move {
        let originals: [Layer]
        let start: Vec2
        /// Option-dragged copies: a press that never moves takes them back,
        /// and the originals are selected again.
        var duplicating = false
        var sources: Set<UUID> = []
    }

    struct Resize {
        let layer: Layer
        let handle: Int
        let start: Vec2
    }

    struct Edit {
        let layer: Layer
        let start: Vec2
        var pivot: Vec2? = nil
    }

    struct Marquee {
        var start: CGPoint
        var current: CGPoint
        var additive: Bool
        var base: Set<UUID>
    }

    /// Editing the selected action from the canvas, in Animate.
    struct ActionEdit {
        enum Part {
            case pathStart, pathEnd, startHandle, endHandle
            /// The layer itself, for a Move: where it is dropped is the end,
            /// counted from where it shows at the playhead.
            case body
            /// A resize handle, for a Resize or a Scale.
            case handle(Int)
            /// Just outside a corner, for a Rotate.
            case rotate
        }

        /// The action as it was when the drag began; every step works from it.
        let action: Action
        let part: Part
        /// Where the drag began, in composition space.
        let start: Vec2
        /// What the action inherits at its start.
        let from: LayerState
        let parentInverse: Affine
        /// The layer's position at the playhead when the drag began, in its
        /// parent's space.
        let shown: Vec2
        /// The layer as it looks at the action's end, which is where the
        /// playhead goes for drags that set an end value.
        let atEnd: ResolvedLayer?
        let worldAtEnd: Affine?
    }

    /// A press on a path's points, handles or segments while its points
    /// are being edited or drawn. Every step works from the path as it was
    /// when the press began.
    struct PathEdit {
        enum Part: Equatable {
            /// Points moving together, their handles with them.
            case points(Set<PointRef>)
            case handle(PointRef, HandleSide)
            /// Both handles pulled out of a point as mirror images: the pen's
            /// click and drag, or ⌘-drag on a point.
            case pull(PointRef)
            /// A segment moving, and the points at both its ends.
            case segment(PointRef)
            /// A box selecting points, in view points.
            case marquee(start: CGPoint, current: CGPoint, base: Set<PointRef>)
        }

        var part: Part
        /// Where the press began, in composition space.
        let start: Vec2
        /// The path in the layer's own space, and the layer and actions it
        /// belongs to, when the press began.
        let path: BezierPath
        let layer: Layer
        let actions: [Action]
        /// The Path action being edited, in Animate.
        let action: Action?
        /// From composition space into the path's.
        let toLocal: Affine
        /// The press has moved, or has already changed the path.
        var moved = false
        /// A ⌘-click that never moves bends the point instead of pulling it.
        var bendsOnClick = false
        /// Releasing ends the pen's drawing: the press closed the path.
        var finishesDrawing = false
        /// A continuous change was begun for this press.
        var began = false
    }

    /// Cropping a picture: moving it inside its shape, scaling it by a
    /// corner, or resizing the shape around it. Every step works from the
    /// layer as it was when the press began.
    struct CropEdit {
        enum Part {
            case move
            /// One of the picture's corners, 0 top-left clockwise to 3.
            case corner(Int)
            /// One of the layer's own handles, numbered as `CanvasHandles`.
            case box(Int)
        }

        let part: Part
        let layer: Layer
        /// Where the press began, in composition space.
        let start: Vec2
        /// From composition space into the layer's own.
        let toLocal: Affine
        /// From composition space into the layer's parent's.
        let parentInverse: Affine
        /// A continuous change was begun: the press has moved.
        var began = false
    }

    /// Panning the view: where the press was, and the pan then.
    struct Pan {
        let start: CGPoint
        let origin: CGPoint
    }

    case create(Create)
    case pan(Pan)
    case move(Move)
    case resize(Resize)
    case rotate(Edit)
    case anchor(Edit)
    case marquee(Marquee)
    case action(ActionEdit)
    case path(PathEdit)
    case crop(CropEdit)

    var marqueeRect: CGRect? {
        switch self {
        case .marquee(let m):
            return CGRect(x: min(m.start.x, m.current.x), y: min(m.start.y, m.current.y),
                          width: abs(m.current.x - m.start.x), height: abs(m.current.y - m.start.y))
        case .path(let p):
            guard case .marquee(let a, let b, _) = p.part else { return nil }
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        default:
            return nil
        }
    }
}

/// The eight handles round a selected layer, numbered clockwise from the
/// top-left: 0 top-left, 1 top, 2 top-right, 3 right, 4 bottom-right,
/// 5 bottom, 6 bottom-left, 7 left. All in view points.
enum CanvasHandles {
    nonisolated static let size: CGFloat = 8
    static let hitRadius: CGFloat = 6
    /// How far past a corner still turns the layer rather than missing it.
    static let rotateReach: CGFloat = 18

    /// `box` is the layer's four corners in view space, from its top-left
    /// clockwise. A line has only its two ends.
    static func positions(for box: [CGPoint], isLine: Bool) -> [CGPoint] {
        handles(for: box, isLine: isLine).map(\.1)
    }

    static func handles(for box: [CGPoint], isLine: Bool) -> [(Int, CGPoint)] {
        guard box.count == 4 else { return [] }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let all = [box[0], mid(box[0], box[1]), box[1], mid(box[1], box[2]),
                   box[2], mid(box[2], box[3]), box[3], mid(box[3], box[0])]
        if isLine { return [(7, all[7]), (3, all[3])] }
        // On a very small layer the side handles crowd the corners out, so
        // only the corners remain.
        let width = hypot(box[1].x - box[0].x, box[1].y - box[0].y)
        let height = hypot(box[3].x - box[0].x, box[3].y - box[0].y)
        return all.enumerated().filter { index, _ in
            if index == 1 || index == 5 { return width > size * 3 }
            if index == 3 || index == 7 { return height > size * 3 }
            return true
        }.map { ($0.offset, $0.element) }
    }

    static func handle(at point: CGPoint, box: [CGPoint], isLine: Bool) -> Int? {
        handles(for: box, isLine: isLine).first { hypot($0.1.x - point.x, $0.1.y - point.y) <= hitRadius }?.0
    }

    /// Just outside a corner.
    static func isRotateZone(_ point: CGPoint, box: [CGPoint]) -> Bool {
        guard box.count == 4, !contains(box, point) else { return false }
        return box.contains { hypot($0.x - point.x, $0.y - point.y) <= rotateReach }
    }

    private static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        let path = CGMutablePath()
        path.addLines(between: polygon)
        path.closeSubpath()
        return path.contains(p)
    }
}

/// The maths of the canvas's direct manipulation. Everything happens in the
/// layer's parent's space, which is what its position is measured in.
enum CanvasGeometry {
    /// Shift squares a shape, and snaps a line to the nearest 45 degrees.
    static func constrainedEnd(_ start: Vec2, _ end: Vec2, tool: Tool, square: Bool) -> Vec2 {
        guard square else { return end }
        let dx = end.x - start.x, dy = end.y - start.y
        if tool == .line {
            let length = hypot(dx, dy)
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            return Vec2(start.x + cos(angle) * length, start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return Vec2(start.x + (dx < 0 ? -side : side), start.y + (dy < 0 ? -side : side))
    }

    /// A layer resized by dragging one of its handles to `pointer`.
    ///
    /// The edge or corner opposite the handle stays where it is on screen,
    /// with Option the centre does, and with Shift the proportions are kept.
    /// The anchor keeps its place relative to the box. A shape changes size;
    /// a group changes scale, so the layers inside it resize with it.
    static func resized(_ layer: Layer, handle: Int, pointer: Vec2,
                        keepAspect: Bool, fromCenter: Bool) -> Layer {
        let t = layer.transform
        let size = layer.size
        let anchor = t.anchor, scale = t.scale
        let rotation = t.rotation, position = t.position, skew = t.skew
        let old = Affine.layer(position: position, anchor: anchor, scale: scale, rotation: rotation, skew: skew)
        guard let inverse = old.inverted else { return layer }
        let local = inverse.apply(pointer)

        let left = [0, 6, 7].contains(handle), right = [2, 3, 4].contains(handle)
        let top = [0, 1, 2].contains(handle), bottom = [4, 5, 6].contains(handle)
        let w = size.width, h = size.height
        var nw = w, nh = h
        if fromCenter {
            if left || right { nw = abs(local.x - w / 2) * 2 }
            if top || bottom { nh = abs(local.y - h / 2) * 2 }
        } else {
            if right { nw = local.x } else if left { nw = w - local.x }
            if bottom { nh = local.y } else if top { nh = h - local.y }
        }
        nw = max(nw, 1)
        nh = h == 0 ? 0 : max(nh, 1)
        if keepAspect, w > 0, h > 0 {
            let s: Double
            if (left || right) && (top || bottom) { s = max(nw / w, nh / h) }
            else if left || right { s = nw / w }
            else { s = nh / h }
            nw = w * s
            nh = h * s
        }

        func fixed(_ low: Bool, _ length: Double) -> Double { fromCenter ? length / 2 : (low ? length : 0) }
        let fixedOld = Vec2(fixed(left, w), fixed(top, h))
        let pinned = old.apply(fixedOld)

        var edited = layer
        if layer.isGroup && !layer.isFrame {
            let newScale = Vec2(w > 0 ? scale.x * nw / w : scale.x, h > 0 ? scale.y * nh / h : scale.y)
            let turned = Affine.layer(position: .zero, anchor: .zero, scale: newScale, rotation: rotation, skew: skew)
            let offset = turned.applyToVector(Vec2(fixedOld.x - anchor.x, fixedOld.y - anchor.y))
            edited.transform.scale = newScale
            edited.transform.position = Vec2(pinned.x - offset.x, pinned.y - offset.y)
        } else {
            let fixedNew = Vec2(fixed(left, nw), fixed(top, nh))
            let newAnchor = Vec2(w > 0 ? anchor.x / w * nw : anchor.x, h > 0 ? anchor.y / h * nh : anchor.y)
            let offset = old.applyToVector(Vec2(fixedNew.x - newAnchor.x, fixedNew.y - newAnchor.y))
            edited.size = Size2(nw, nh)
            edited.transform.anchor = newAnchor
            edited.transform.position = Vec2(pinned.x - offset.x, pinned.y - offset.y)
        }
        return edited
    }

    /// The anchor moved to `pointer`, with the position moved to match so the
    /// layer itself does not move.
    static func movedAnchor(_ layer: Layer, to pointer: Vec2) -> Layer {
        let t = layer.transform
        let old = Affine.layer(position: t.position, anchor: t.anchor,
                               scale: t.scale, rotation: t.rotation, skew: t.skew)
        guard let inverse = old.inverted else { return layer }
        let anchor = inverse.apply(pointer)
        var edited = layer
        edited.transform.anchor = anchor
        edited.transform.position = old.apply(anchor)
        return edited
    }
}

extension Layer {
    /// This layer, with its id and name, reshaped to another's box and
    /// transform. Used while a shape is being drawn.
    func replacingGeometry(with other: Layer) -> Layer {
        var copy = self
        copy.size = other.size
        copy.transform = other.transform
        return copy
    }
}

extension Alignment.Edge {
    var title: String {
        switch self {
        case .left: "Align Left"
        case .centerX: "Align Horizontal Centres"
        case .right: "Align Right"
        case .top: "Align Top"
        case .centerY: "Align Vertical Centres"
        case .bottom: "Align Bottom"
        }
    }

    var icon: Icon {
        switch self {
        case .left: .alignLeft
        case .centerX: .alignCenterX
        case .right: .alignRight
        case .top: .alignTop
        case .centerY: .alignCenterY
        case .bottom: .alignBottom
        }
    }

    /// Figma's keys: Option with A, H, D for left, centre, right, and W, V,
    /// S for top, middle, bottom.
    var shortcut: String {
        switch self {
        case .left: "⌥A"
        case .centerX: "⌥H"
        case .right: "⌥D"
        case .top: "⌥W"
        case .centerY: "⌥V"
        case .bottom: "⌥S"
        }
    }

    fileprivate var keyCode: UInt16 {
        switch self {
        case .left: 0
        case .centerX: 4
        case .right: 2
        case .top: 13
        case .centerY: 9
        case .bottom: 1
        }
    }
}

/// Aligning and distributing from the keyboard, on the canvas in Design.
/// Handled here rather than as menu keys, so Option with a letter still
/// types its accent in a text field. Matched by key code, since Option
/// changes the character a key types.
enum AlignKeys {
    static func handle(_ event: NSEvent, _ controller: EditorController) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .option, let edge = Alignment.Edge.allCases.first(where: { $0.keyCode == event.keyCode }) {
            guard controller.canAlign else { return false }
            controller.align(edge)
            return true
        }
        if flags == [.control, .option], event.keyCode == 4 || event.keyCode == 9 {
            guard controller.canDistribute else { return false }
            controller.distribute(event.keyCode == 4 ? .x : .y)
            return true
        }
        return false
    }
}
