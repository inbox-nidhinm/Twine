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

    /// The longest side, in pixels, a text's picture is drawn to when it is
    /// shown bigger than its size (see `CoreAnimationRenderer.textZoom`).
    static let maxSide: Double = 8192

    let image: CGImage?
    /// Pixels per point.
    let scale: CGFloat
    /// The text's own box, without the margin; for one letter, word or
    /// line, its box with the margin all round.
    let box: Size2
    let margin: Double
    /// A letter's, word's or line's picture's top-left in the text's own
    /// space.
    let origin: CGPoint

    /// The whole text, or only the characters `unit` covers (one letter,
    /// word or line), in a picture of its box with a margin all round. Only
    /// its own glyphs are drawn: letters of the lines above and below, or
    /// beside it, that reach into its box stay with their own unit, so none
    /// moves off with it.
    init(_ key: Key, unit: (box: Box, characters: NSRange)? = nil) {
        scale = key.scale
        let set = TextLayout.layout(key.text, style: key.style, width: key.width)
        // Room for letters that reach past their box, and for a stroke round them.
        margin = ceil(max(key.style.fontSize, 1) * 0.5 + (key.stroke?.width ?? 0))
        let total: Size2
        // Where the picture's top-left falls in the text's space.
        let left: Double, top: Double
        if let region = unit?.box {
            box = Size2(region.width + margin * 2, region.height + margin * 2)
            total = box
            left = region.minX - margin
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
        let characters = unit?.characters
        let lines = set.lines.filter { line in characters.map { NSIntersectionRange(line.range, $0).length > 0 } ?? true }
        func baseline(_ line: PositionedLine) -> CGPoint {
            CGPoint(x: line.origin.x - left, y: total.height - (line.origin.y - top))
        }
        func fill() {
            guard key.showsFill else { return }
            for line in lines {
                context.textPosition = baseline(line)
                guard let characters else {
                    CTLineDraw(line.line, context)
                    continue
                }
                for run in (CTLineGetGlyphRuns(line.line) as? [CTRun]) ?? [] {
                    for glyphs in Self.glyphRanges(of: run, in: line, within: characters) {
                        CTRunDraw(run, context, glyphs)
                    }
                }
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
        for line in lines { Self.addOutlines(of: line, within: characters, at: baseline(line), to: outlines) }
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

    /// The glyphs of a run that draw `characters` (UTF-16 units of the whole
    /// text), as runs of neighbouring glyphs.
    private static func glyphRanges(of run: CTRun, in line: PositionedLine, within characters: NSRange) -> [CFRange] {
        let count = CTRunGetGlyphCount(run)
        var indices = [CFIndex](repeating: 0, count: count)
        CTRunGetStringIndices(run, CFRange(), &indices)
        var ranges: [CFRange] = []
        var start: Int?
        for i in 0...count {
            let inside = i < count && NSLocationInRange(line.paragraphStart + indices[i], characters)
            if inside, start == nil { start = i }
            if !inside, let s = start {
                ranges.append(CFRange(location: s, length: i - s))
                start = nil
            }
        }
        return ranges
    }

    /// Every glyph of a set line (or those drawing `characters`) as an
    /// outline, placed from its baseline's start, in the picture's own
    /// coordinates (y up).
    private static func addOutlines(of line: PositionedLine, within characters: NSRange?, at origin: CGPoint,
                                    to path: CGMutablePath) {
        for run in (CTLineGetGlyphRuns(line.line) as? [CTRun]) ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName as String] else { continue }
            let font = value as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetStringIndices(run, CFRange(), &indices)
            for (i, (glyph, position)) in zip(glyphs, positions).enumerated() {
                if let characters, !NSLocationInRange(line.paragraphStart + indices[i], characters) { continue }
                guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                path.addPath(outline, transform: CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y))
            }
        }
    }
}
