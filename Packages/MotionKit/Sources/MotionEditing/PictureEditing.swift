import Foundation
import MotionModel
import MotionEvaluation

/// Changing a layer's picture or video without touching the rest of it:
/// Replace, the picture's mode and turn, and cropping on the canvas. The
/// layer keeps its id, box and actions, so its animation carries on.
public enum PictureEditing {
    // MARK: Replace

    /// The layer's first picture swapped for `asset`, in the same box and
    /// mode. A crop keeps its centre and covers what showed before, in the
    /// new picture's own shape. A layer still named after its old file takes
    /// the new file's name.
    public static func replacingPicture(_ layer: Layer, with asset: MediaAsset, old: MediaAsset?) -> Layer {
        guard var shape = layer.look, let (index, paint) = layer.picture else { return layer }
        var p = paint
        p.mediaID = asset.id
        if p.mode == .crop {
            p.crop = ImagePlacement.crop(replacing: paint.crop, box: layer.size, with: p, picture: asset.pixelSize)
        }
        shape.fills[index].paint = .image(p)
        var edited = layer
        edited.look = shape
        edited.name = renamed(layer.name, from: old, to: asset)
        return edited
    }

    /// The video swapped for `asset`, and its Play actions kept inside the
    /// new clip: a play that would run past the new file's end starts
    /// earlier in the file, as far as the file allows. Where it still runs
    /// past, the last frame holds, as it does for any play.
    public static func replacingVideo(_ layer: Layer, with asset: MediaAsset, old: MediaAsset?,
                                      actions: [Action]) -> (layer: Layer, actions: [Action]) {
        guard case .video(var video) = layer.content else { return (layer, []) }
        video.mediaID = asset.id
        var edited = layer
        edited.content = .video(video)
        edited.name = renamed(layer.name, from: old, to: asset)
        guard let length = asset.duration else { return (edited, []) }
        let changed = actions.compactMap { action -> Action? in
            guard action.targetLayerID == layer.id, case .play(var play) = action.spec,
                  play.trimStart + action.duration > length + 1e-9 else { return nil }
            let trim = max(0, min(play.trimStart, length - action.duration))
            guard abs(trim - play.trimStart) > 1e-9 else { return nil }
            play.trimStart = trim
            var a = action
            a.spec = .play(play)
            return a
        }
        return (edited, changed)
    }

    private static func renamed(_ name: String, from old: MediaAsset?, to new: MediaAsset) -> String {
        guard let old, name == base(of: old.originalName) else { return name }
        return base(of: new.originalName)
    }

    private static func base(of fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    // MARK: Mode and turn

    /// The first picture in another mode. Into Crop, the picture stays where
    /// it showed, so choosing Crop moves nothing until it is dragged.
    public static func settingMode(_ layer: Layer, to mode: ImageScaleMode, pictures: [UUID: Size2]) -> Layer {
        editingPicture(layer) { p in
            if mode == .crop, p.mode != .crop {
                p.crop = ImagePlacement.crop(of: p, box: layer.size, picture: pictures[p.mediaID])
            }
            p.mode = mode
        }
    }

    /// The picture turned a quarter clockwise. A crop turns about its own
    /// centre, becoming as tall as it was wide.
    public static func turned(_ layer: Layer) -> Layer {
        editingPicture(layer) { p in
            p.quarterTurns = (p.turns + 1) % 4
            guard p.mode == .crop else { return }
            let box = layer.size
            let w = p.crop.width * box.width, h = p.crop.height * box.height
            let cx = (p.crop.x + p.crop.width / 2) * box.width, cy = (p.crop.y + p.crop.height / 2) * box.height
            p.crop = ImagePlacement.crop(Box(origin: Vec2(cx - h / 2, cy - w / 2), size: Size2(h, w)), box: box)
        }
    }

    public static func editingPicture(_ layer: Layer, _ change: (inout ImagePaint) -> Void) -> Layer {
        guard var shape = layer.look, let (index, paint) = layer.picture else { return layer }
        var p = paint
        change(&p)
        shape.fills[index].paint = .image(p)
        var edited = layer
        edited.look = shape
        return edited
    }

    // MARK: Cropping

    /// The smallest a picture can be scaled to while cropping, in pixels.
    public static let minimumCropSide = 4.0

    /// The crop moved by `delta`, in the layer's own pixels.
    public static func movedCrop(_ crop: ImageCrop, by delta: Vec2, box: Size2) -> ImageCrop {
        var c = crop
        if box.width > 0 { c.x += delta.x / box.width }
        if box.height > 0 { c.y += delta.y / box.height }
        return c
    }

    /// The crop scaled by dragging one of its corners (0 top-left, clockwise
    /// to 3 bottom-left) to `point`, in the layer's own pixels. The opposite
    /// corner stays put and the picture keeps its shape.
    public static func scaledCrop(_ crop: ImageCrop, corner: Int, to point: Vec2, box: Size2) -> ImageCrop {
        let frame = Box(origin: Vec2(crop.x * box.width, crop.y * box.height),
                        size: Size2(crop.width * box.width, crop.height * box.height))
        guard frame.width > 0, frame.height > 0 else { return crop }
        let corners = frame.corners
        let fixed = corners[(corner + 2) % 4]
        let dragged = corners[corner % 4]
        // How far along the diagonal the pointer has gone, measured on it,
        // so the picture grows and shrinks without changing shape.
        let diagonal = Vec2(dragged.x - fixed.x, dragged.y - fixed.y)
        let along = Vec2(point.x - fixed.x, point.y - fixed.y)
        let length2 = diagonal.x * diagonal.x + diagonal.y * diagonal.y
        let smallest = minimumCropSide / min(frame.width, frame.height)
        let f = max((along.x * diagonal.x + along.y * diagonal.y) / length2, smallest)
        let end = Vec2(fixed.x + diagonal.x * f, fixed.y + diagonal.y * f)
        let scaled = Box(minX: min(fixed.x, end.x), minY: min(fixed.y, end.y),
                         maxX: max(fixed.x, end.x), maxY: max(fixed.y, end.y))
        return ImagePlacement.crop(scaled, box: box)
    }

    /// While cropping, resizing the layer's box crops the picture rather
    /// than stretching it: the picture keeps its place and size on screen,
    /// and the box shows more or less of it. `original` is the layer before
    /// the resize, `resized` after it.
    public static func croppingResize(_ original: Layer, to resized: Layer) -> Layer {
        guard let (_, paint) = original.picture, paint.mode == .crop else { return resized }
        let t = original.transform, n = resized.transform
        let before = Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
        let after = Affine.layer(position: n.position, anchor: n.anchor, scale: n.scale, rotation: n.rotation, skew: n.skew)
        guard let inverse = before.inverted else { return resized }
        let shift = inverse.apply(after.apply(.zero))
        let crop = ImagePlacement.crop(paint.crop, from: original.size, to: resized.size, shift: shift)
        return editingPicture(resized) { $0.crop = crop }
    }
}

extension MediaAsset {
    /// The picture's or video's own size in pixels, when it has one.
    public var pixelSize: Size2? {
        guard let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else { return nil }
        return Size2(Double(w), Double(h))
    }
}
