import Foundation
import MotionModel

/// Where a picture fill sits in its layer's box, for each of Figma's modes.
/// Everything is in the layer's own pixels, and every box is the picture as
/// it shows, after its quarter turns: a picture turned once is as tall as it
/// was wide.
public enum ImagePlacement {
    /// The picture's size once turned, from its own pixels. A picture whose
    /// size is not known is taken as the box's shape, so it fills it exactly.
    public static func turnedSize(_ paint: ImagePaint, picture: Size2?, box: Size2) -> Size2 {
        guard let picture, picture.width > 0, picture.height > 0 else { return box }
        return paint.turns % 2 == 1 ? Size2(picture.height, picture.width) : picture
    }

    /// The whole picture's box for Fill, Fit and Crop. For Tile, the first
    /// tile, at the box's top-left.
    public static func frame(of paint: ImagePaint, box: Size2, picture: Size2?) -> Box {
        let shown = turnedSize(paint, picture: picture, box: box)
        switch paint.mode {
        case .fill, .fit:
            return centred(shown, in: box, covering: paint.mode == .fill)
        case .crop:
            let c = paint.crop
            return Box(origin: Vec2(c.x * box.width, c.y * box.height),
                       size: Size2(c.width * box.width, c.height * box.height))
        case .tile:
            let s = max(paint.tileScale, 0.001)
            return Box(origin: .zero, size: Size2(shown.width * s, shown.height * s))
        }
    }

    /// A picture of `shown` size centred in `box`, as large as covers it or
    /// as fits inside it.
    public static func centred(_ shown: Size2, in box: Size2, covering: Bool) -> Box {
        guard shown.width > 0, shown.height > 0 else { return Box(origin: .zero, size: box) }
        let sx = box.width / shown.width, sy = box.height / shown.height
        let s = covering ? max(sx, sy) : min(sx, sy)
        let size = Size2(shown.width * s, shown.height * s)
        return Box(origin: Vec2((box.width - size.width) / 2, (box.height - size.height) / 2), size: size)
    }

    /// The crop that shows the picture exactly where it is now, for turning
    /// Fill, Fit or Tile into Crop without anything moving. A tiled picture
    /// has no one place, so it starts from Fill.
    public static func crop(of paint: ImagePaint, box: Size2, picture: Size2?) -> ImageCrop {
        var p = paint
        if p.mode == .tile { p.mode = .fill }
        return crop(frame(of: p, box: box, picture: picture), box: box)
    }

    /// A picture box in pixels as fractions of the layer's box.
    public static func crop(_ frame: Box, box: Size2) -> ImageCrop {
        let w = box.width > 0 ? box.width : 1, h = box.height > 0 ? box.height : 1
        return ImageCrop(x: frame.minX / w, y: frame.minY / h, width: frame.width / w, height: frame.height / h)
    }

    /// Kept with the layer on screen when its box changes: a crop measured
    /// against `old` as it must read against `new`, when the box's top-left
    /// moved by `shift` (in the layer's own pixels, before the change).
    public static func crop(_ crop: ImageCrop, from old: Size2, to new: Size2, shift: Vec2) -> ImageCrop {
        let frame = Box(origin: Vec2(crop.x * old.width - shift.x, crop.y * old.height - shift.y),
                        size: Size2(crop.width * old.width, crop.height * old.height))
        return self.crop(frame, box: new)
    }

    /// A new picture of `picture` size taking the place of an old crop: the
    /// same centre, and as large as covers the old picture's box, so the
    /// part that showed is still covered.
    public static func crop(replacing crop: ImageCrop, box: Size2, with paint: ImagePaint, picture: Size2?) -> ImageCrop {
        let old = Box(origin: Vec2(crop.x * box.width, crop.y * box.height),
                      size: Size2(crop.width * box.width, crop.height * box.height))
        let placed = centred(turnedSize(paint, picture: picture, box: box), in: Size2(old.width, old.height), covering: true)
        let frame = Box(origin: Vec2(old.minX + placed.minX, old.minY + placed.minY), size: Size2(placed.width, placed.height))
        return self.crop(frame, box: box)
    }
}
