import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering

/// A picture being cropped on the canvas.
struct CropSession: Equatable {
    let layerID: UUID
}

/// Cropping, as Figma does it. Choosing Crop, or double-clicking a picture,
/// shows the whole picture, the part outside its shape faint: drag it to
/// move it inside the shape, drag its corners to scale it (it keeps its
/// shape), and drag the layer's own handles to crop more or less of it,
/// the picture staying put. Escape, Return, or a click away from both
/// finishes. Design only.
extension CanvasNSView {
    var isCropping: Bool { cropSession != nil }

    func beginCropping(_ id: UUID) {
        guard let controller, !animating, let layer = controller.project.layer(withID: id),
              layer.picture?.paint.mode == .crop, !controller.isLocked(id) else { return }
        if textSession != nil { endTextEditing() }
        if pathSession != nil { endPathEditing() }
        controller.select([id])
        cropSession = CropSession(layerID: id)
        setHover(nil)
        window?.makeFirstResponder(self)
        redrawOverlay()
    }

    func endCropping() {
        guard cropSession != nil else { return }
        cropSession = nil
        overlay.updateCrop(nil)
        redrawOverlay()
    }

    /// Keeps the session in step with the project and the selection, called
    /// from `show`. It only changes what the canvas shows.
    func validateCropSession() {
        guard let session = cropSession else { return }
        guard !animating, selection == [session.layerID], tool == .select, pathSession == nil, textSession == nil,
              let layer = controller?.project.layer(withID: session.layerID), layer.picture?.paint.mode == .crop else {
            cropSession = nil
            overlay.updateCrop(nil)
            return
        }
    }

    // MARK: Where the picture is

    private struct CropPlace {
        let layer: Layer
        let paint: ImagePaint
        /// The whole picture's box in the layer's own pixels.
        let frame: Box
        let world: Affine
        /// The picture's corners and the layer's, in view points.
        let pictureCorners: [CGPoint]
        let boxCorners: [CGPoint]
    }

    private func cropPlace() -> CropPlace? {
        guard let session = cropSession, let controller, let scene, let resolved = scene.layer(session.layerID),
              let world = scene.worldTransform(of: session.layerID),
              let layer = controller.project.layer(withID: session.layerID), let (_, paint) = layer.picture else { return nil }
        let frame = ImagePlacement.frame(of: paint, box: resolved.size, picture: controller.project.pictureSizes[paint.mediaID])
        return CropPlace(layer: layer, paint: paint, frame: frame, world: world,
                         pictureCorners: frame.corners.map { compositionToView(world.apply($0)) },
                         boxCorners: Box(origin: .zero, size: resolved.size).corners.map { compositionToView(world.apply($0)) })
    }

    func cropMarks() -> CanvasOverlay.CropMarks? {
        guard let place = cropPlace(), let controller else { return nil }
        let turns = place.paint.turns
        let frame = place.frame
        let upright = turns % 2 == 1 ? CGSize(width: frame.height, height: frame.width)
                                     : CGSize(width: frame.width, height: frame.height)
        let o = compositionToView(.zero)
        let toView = Affine.translation(Vec2(-upright.width / 2, -upright.height / 2))
            .then(.rotation(degrees: Double(turns) * 90))
            .then(.translation(frame.center))
            .then(place.world)
            .then(.scale(Vec2(zoom, zoom)))
            .then(.translation(Vec2(o.x, o.y)))
        return CanvasOverlay.CropMarks(image: controller.media.image(place.paint.mediaID), size: upright,
                                       transform: toView.caTransform, corners: place.pictureCorners)
    }

    /// The layer's handles while cropping, which crop rather than stretch.
    var cropBoxCorners: [CGPoint]? { cropPlace()?.boxCorners }

    // MARK: Pointer

    /// A press while cropping: on a corner of the picture, on one of the
    /// layer's handles, or on the picture or the shape. Anywhere else the
    /// crop finishes and the press carries on as usual.
    func cropMouseDown(_ event: NSEvent, at point: Vec2, viewPoint: CGPoint) -> Bool {
        guard let place = cropPlace() else { return false }
        func near(_ p: CGPoint) -> Bool { hypot(p.x - viewPoint.x, p.y - viewPoint.y) <= CanvasHandles.hitRadius }
        let part: CanvasDrag.CropEdit.Part
        if let corner = place.pictureCorners.firstIndex(where: near) {
            part = .corner(corner)
        } else if let handle = CanvasHandles.handle(at: viewPoint, box: place.boxCorners, isLine: false) {
            part = .box(handle)
        } else if Self.contains(place.pictureCorners, viewPoint) || Self.contains(place.boxCorners, viewPoint) {
            part = .move
        } else {
            endCropping()
            return false
        }
        guard let toLocal = place.world.inverted, let parentInverse = parentInverse(of: place.layer.id) else { return false }
        drag = .crop(CanvasDrag.CropEdit(part: part, layer: place.layer, start: point, toLocal: toLocal,
                                         parentInverse: parentInverse))
        return true
    }

    func cropMouseDragged(_ edit: CanvasDrag.CropEdit, point: Vec2, event: NSEvent) {
        guard let controller, let (_, paint) = edit.layer.picture else { return }
        var edit = edit
        if !edit.began {
            controller.begin("Crop")
            edit.began = true
            drag = .crop(edit)
        }
        let layer = edit.layer
        let edited: Layer
        switch edit.part {
        case .move:
            let delta = edit.toLocal.applyToVector(point - edit.start)
            edited = PictureEditing.editingPicture(layer) { $0.crop = PictureEditing.movedCrop(paint.crop, by: delta, box: layer.size) }
        case .corner(let corner):
            let local = edit.toLocal.apply(point)
            edited = PictureEditing.editingPicture(layer) {
                $0.crop = PictureEditing.scaledCrop(paint.crop, corner: corner, to: local, box: layer.size)
            }
        case .box(let handle):
            let resized = CanvasGeometry.resized(layer, handle: handle, pointer: edit.parentInverse.apply(point),
                                                 keepAspect: event.modifierFlags.contains(.shift),
                                                 fromCenter: event.modifierFlags.contains(.option))
            edited = PictureEditing.croppingResize(layer, to: resized)
        }
        controller.update([edited])
    }

    func cropMouseUp(_ edit: CanvasDrag.CropEdit) {
        if edit.began { controller?.end() }
    }

    /// Escape and Return finish cropping.
    func cropKeyDown(_ event: NSEvent) -> Bool {
        guard isCropping, event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 else { return false }
        endCropping()
        return true
    }

    /// The scaling arrows over the picture's corners.
    func cropCursor(at viewPoint: CGPoint) -> NSCursor? {
        guard let place = cropPlace() else { return nil }
        let corners = place.pictureCorners
        let center = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        if let corner = corners.first(where: { hypot($0.x - viewPoint.x, $0.y - viewPoint.y) <= CanvasHandles.hitRadius }) {
            return Cursors.resize(toward: CGVector(dx: corner.x - center.x, dy: corner.y - center.y))
        }
        return nil
    }

    private static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        guard polygon.count > 2 else { return false }
        let path = CGMutablePath()
        path.addLines(between: polygon)
        path.closeSubpath()
        return path.contains(p)
    }
}
