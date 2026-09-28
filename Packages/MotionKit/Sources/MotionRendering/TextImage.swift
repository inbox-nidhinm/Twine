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
        var showsFill = true
        var stroke: ResolvedTextStroke? = nil
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
        // Room for letters that reach past their box, and for a stroke round them.
        margin = ceil(max(key.style.fontSize, 1) * 0.5 + (key.stroke?.width ?? 0))
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
        let lines = set.lines.filter { line in
            region.map { line.top + line.height >= $0.minY && line.top <= $0.maxY } ?? true
        }
        func baseline(_ line: PositionedLine) -> CGPoint {
            CGPoint(x: line.origin.x - left, y: total.height - (line.origin.y - top))
        }
        func fill() {
            guard key.showsFill else { return }
            for line in lines {
                context.textPosition = baseline(line)
                CTLineDraw(line.line, context)
            }
        }
        guard let stroke = key.stroke else {
            fill()
            image = context.makeImage()
            return
        }
        // The stroke follows the letters' outlines, centred on them, inside
        // (clipped to them) or outside (clipped away from them), as a
        // shape's does; the fill goes under it.
        let outlines = CGMutablePath()
        for line in lines { Self.addOutlines(of: line.line, at: baseline(line), to: outlines) }
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineJoin(stroke.join.cg)
        context.setMiterLimit(4)
        func strokeOutlines(_ width: Double) {
            context.setLineWidth(width)
            context.addPath(outlines)
            context.strokePath()
        }
        switch stroke.alignment {
        case .center:
            fill()
            strokeOutlines(stroke.width)
        case .inside:
            fill()
            context.saveGState()
            context.addPath(outlines)
            context.clip()
            strokeOutlines(stroke.width * 2)
            context.restoreGState()
        case .outside:
            context.saveGState()
            context.addRect(CGRect(x: 0, y: 0, width: total.width, height: total.height))
            context.addPath(outlines)
            context.clip(using: .evenOdd)
            strokeOutlines(stroke.width * 2)
            context.restoreGState()
            fill()
        }
        image = context.makeImage()
    }

    /// Every glyph of a set line as an outline, placed from its baseline's
    /// start, in the picture's own coordinates (y up).
    private static func addOutlines(of line: CTLine, at origin: CGPoint, to path: CGMutablePath) {
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName as String] else { continue }
            let font = value as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                path.addPath(outline, transform: CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y))
            }
        }
    }
}
