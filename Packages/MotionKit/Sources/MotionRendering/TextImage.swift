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
    /// The text's own box, without the margin.
    let box: Size2
    let margin: Double

    init(_ key: Key) {
        let set = TextLayout.layout(key.text, style: key.style, width: key.width)
        box = set.size
        margin = ceil(max(key.style.fontSize, 1) * 0.5)
        let total = Size2(box.width + margin * 2, box.height + margin * 2)
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
            context.textPosition = CGPoint(x: margin + line.origin.x, y: total.height - margin - line.origin.y)
            CTLineDraw(line.line, context)
        }
        image = context.makeImage()
    }
}
