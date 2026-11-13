import Foundation
import CoreGraphics
import CoreText
import MotionModel
import MotionEvaluation

/// Text in a Lottie is its letters' outlines: a Lottie player has none of
/// the Mac's fonts, and a text layer in Lottie is drawn with whatever font
/// the player finds, so outlines are the only way it looks as it does in
/// Twine everywhere.
enum LottieText {
    struct Key: Hashable {
        var text: String
        var style: TextStyle
        var width: Double?
        /// One letter, word or line's characters, or nil for all of it.
        var range: NSRange?
    }

    /// Every glyph `key` draws, in the text's own space (origin at its
    /// top-left, y down), as `TextImage` places them, and the size of the
    /// whole text as set.
    static func outlines(_ key: Key) -> (path: BezierPath, size: Size2) {
        let set = TextLayout.layout(key.text, style: key.style, width: key.width)
        let path = CGMutablePath()
        for line in set.lines {
            if let range = key.range, NSIntersectionRange(line.range, range).length == 0 { continue }
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
                for i in 0..<count {
                    if let range = key.range, !NSLocationInRange(line.paragraphStart + indices[i], range) { continue }
                    guard let outline = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                    // Glyphs are drawn y up from their baseline; the text's
                    // space runs down from its top.
                    let place = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                  tx: line.origin.x + positions[i].x,
                                                  ty: line.origin.y - positions[i].y)
                    path.addPath(outline, transform: place)
                }
            }
        }
        return (LottieGeometry.bezierPath(path), set.size)
    }
}
