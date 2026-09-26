import Foundation
import CoreText
import CoreGraphics
import MotionModel

/// Where characters sit in a set text, for editing it in place: the caret
/// for a position, the position under a point, and the boxes a selection
/// covers. Positions are UTF-16 offsets into the text, as AppKit's text
/// input counts them, measured in the text box's own space, y down from its
/// top-left. It sets the text exactly as `TextLayout` does for drawing, so
/// the caret sits on the letters drawn.
public struct TextGeometry {
    public let text: String
    public let lines: [PositionedLine]
    public let size: Size2
    private let length: Int

    public init(text: String, style: TextStyle, width: Double?) {
        self.text = text
        let set = TextLayout.layout(text, style: style, width: width)
        lines = set.lines
        size = set.size
        length = (text as NSString).length
    }

    /// The line a position is on. A position at a wrap belongs to the line
    /// it starts, except at the very end of a paragraph.
    public func line(of position: Int) -> Int {
        let p = min(max(position, 0), length)
        for (i, l) in lines.enumerated() {
            let end = l.range.location + l.range.length
            let nextStartsHere = i + 1 < lines.count && lines[i + 1].range.location == p && lines[i + 1].paragraphStart == l.paragraphStart
            if p >= l.range.location && (p < end || (p == end && !nextStartsHere)) { return i }
        }
        return max(lines.count - 1, 0)
    }

    /// The caret before the character at `position`: its x, and the top and
    /// height of its line.
    public func caret(at position: Int) -> CGRect {
        guard !lines.isEmpty else { return CGRect(x: 0, y: 0, width: 0, height: size.height) }
        let l = lines[line(of: position)]
        let local = min(max(position, l.range.location), l.range.location + l.range.length) - l.paragraphStart
        let x = Double(l.origin.x) + Double(CTLineGetOffsetForStringIndex(l.line, local, nil))
        return CGRect(x: x, y: l.top, width: 0, height: l.height)
    }

    /// The position nearest `point`: on the line it is level with (the first
    /// or last line above or below the text), at the nearest gap between
    /// letters.
    public func position(at point: CGPoint) -> Int {
        guard !lines.isEmpty else { return 0 }
        let row = min(max(Int((Double(point.y) / max(lines[0].height, 1)).rounded(.down)), 0), lines.count - 1)
        return position(onLine: row, x: Double(point.x))
    }

    /// The position nearest `x` on line `row`, for clicks and for moving the
    /// caret up and down.
    public func position(onLine row: Int, x: Double) -> Int {
        let l = lines[min(max(row, 0), lines.count - 1)]
        var local = CTLineGetStringIndexForPosition(l.line, CGPoint(x: x - Double(l.origin.x), y: 0))
        if local == kCFNotFound { local = l.range.location - l.paragraphStart }
        let p = l.paragraphStart + local
        // A wrapped line ends before its trailing space, not after it.
        let end = l.range.location + l.range.length
        let wrapped = row + 1 < lines.count && lines[row + 1].paragraphStart == l.paragraphStart
        return min(max(p, l.range.location), wrapped ? max(end - 1, l.range.location) : end)
    }

    /// The first and last positions of the line `position` is on.
    public func lineBounds(of position: Int) -> (start: Int, end: Int) {
        guard !lines.isEmpty else { return (0, 0) }
        let row = line(of: position)
        let l = lines[row]
        let end = l.range.location + l.range.length
        let wrapped = row + 1 < lines.count && lines[row + 1].paragraphStart == l.paragraphStart
        return (l.range.location, wrapped ? max(end - 1, l.range.location) : end)
    }

    /// The boxes a selection covers, one per line it touches.
    public func selectionRects(_ range: NSRange) -> [CGRect] {
        guard range.length > 0 else { return [] }
        let lo = range.location, hi = range.location + range.length
        return lines.compactMap { l in
            let start = max(lo, l.range.location), end = min(hi, l.range.location + l.range.length)
            // A selected line break shows as a sliver at the line's end.
            let crossesBreak = hi > l.range.location + l.range.length && lo <= l.range.location + l.range.length
            guard start < end || crossesBreak else { return nil }
            let a = caretX(l, start), b = caretX(l, max(end, start)) + (crossesBreak ? 4 : 0)
            return CGRect(x: a, y: l.top, width: max(b - a, 0), height: l.height)
        }
    }

    private func caretX(_ l: PositionedLine, _ position: Int) -> Double {
        Double(l.origin.x) + Double(CTLineGetOffsetForStringIndex(l.line, position - l.paragraphStart, nil))
    }
}
