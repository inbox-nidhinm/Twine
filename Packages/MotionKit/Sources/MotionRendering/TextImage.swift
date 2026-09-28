import Foundation
import CoreGraphics
import CoreText
import MotionModel
import MotionEvaluation

/// A text set by `TextLayout` and drawn into an image, with a margin all
/// round so letters that reach past their box (a descender, an italic's
/// tail) are not cut off.
struct TextImage {
    /// Everything the picture depends on, so it is only redrawn when one of
    /// them changes, not on every frame.
    struct Key: Hashable {
        let text: String
        let style: TextStyle
        let color: RGBA
        let width: Double?
        let scale: CGFloat
    }

    let image: CGImage?
    /// The text's own box, without the margin; for a region, the region
    /// with the margin above and below.
    let box: Size2
    let margin: Double
    /// A region's picture's top-left in the text's own space.
    let origin: CGPoint

    /// The whole text, or only what falls in `region` of the text's own
    /// space (one letter, word or line), a margin taller above and below.
    init(_ key: Key, region: Box? = nil) {
        let set = TextLayout.layout(key.text, style: key.style, width: key.width)
        margin = ceil(max(key.style.fontSize, 1) * 0.5)
        let total: Size2
        // Where the picture's top-left falls in the text's space.
        let left: Double, top: Double
        if let region {
            box = Size2(region.width, region.height + margin * 2)
            total = box
            left = region.minX
            top = region.minY - margin
        } else {
            box = set.size
            total = Size2(box.width + margin * 2, box.height + margin * 2)
            left = -margin
            top = -margin
        }
        origin = CGPoint(x: left, y: top)
        let w = max(Int((total.width * key.scale).rounded(.up)), 1), h = max(Int((total.height * key.scale).rounded(.up)), 1)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else {
            image = nil
            return
        }
        context.scaleBy(x: key.scale, y: key.scale)
        context.setFillColor(key.color.cgColor)
        context.setShouldSmoothFonts(false)
        // Core Graphics counts up from the bottom; the layout counts down
        // from the top.
        for line in set.lines {
            if let region, line.top + line.height < region.minY || line.top > region.maxY { continue }
            context.textPosition = CGPoint(x: line.origin.x - left, y: total.height - (line.origin.y - top))
            CTLineDraw(line.line, context)
        }
        image = context.makeImage()
    }
}
