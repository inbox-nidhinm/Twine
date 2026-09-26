import Foundation
import MotionEvaluation

/// A text being typed into on the canvas: the words, the selection, and any
/// half-typed input a keyboard is composing (an accent held down, a Japanese
/// word being converted). Positions are UTF-16 offsets, as AppKit's text
/// input counts them, and the caret never lands inside a character made of
/// several units, such as an emoji.
public struct EditableText: Equatable, Sendable {
    public private(set) var text: String
    /// Where the selection started, and where it has been extended to. The
    /// same when there is only a caret.
    public private(set) var anchor: Int
    public private(set) var head: Int
    /// Text a keyboard is still composing, shown but not yet final.
    public private(set) var marked: NSRange?

    public init(text: String, selectAll: Bool = false) {
        self.text = text
        let length = (text as NSString).length
        anchor = selectAll ? 0 : length
        head = length
    }

    public var length: Int { (text as NSString).length }
    public var selection: NSRange { NSRange(location: min(anchor, head), length: abs(head - anchor)) }
    public var selectedText: String { (text as NSString).substring(with: selection) }

    public mutating func select(_ range: NSRange) {
        let r = clamped(range)
        anchor = r.location
        head = r.location + r.length
    }

    public mutating func selectAll() { select(NSRange(location: 0, length: length)) }

    /// Puts the caret at `position`, or with `extending`, moves the
    /// selection's far end there.
    public mutating func place(_ position: Int, extending: Bool = false) {
        let p = snapped(min(max(position, 0), length))
        head = p
        if !extending { anchor = p }
    }

    /// The word around `position`, for a double-click.
    public mutating func selectWord(at position: Int) {
        let p = min(max(position, 0), length)
        let ns = text as NSString
        var start = p, end = p
        while start > 0, isWord(ns.character(at: start - 1)) { start -= 1 }
        while end < length, isWord(ns.character(at: end)) { end += 1 }
        select(NSRange(location: start, length: end - start))
    }

    // MARK: Typing

    /// Replaces the half-typed text if there is some, otherwise the selection.
    public mutating func insert(_ string: String) {
        replace(marked ?? selection, with: string)
        marked = nil
    }

    /// Shows half-typed text in place of the selection (or the text already
    /// being composed), with `selected` its own caret or selection inside it.
    public mutating func setMarked(_ string: String, selected: NSRange) {
        let target = marked ?? selection
        replace(target, with: string)
        let count = (string as NSString).length
        marked = count > 0 ? NSRange(location: target.location, length: count) : nil
        let inner = NSRange(location: min(selected.location, count), length: min(selected.length, max(count - selected.location, 0)))
        anchor = target.location + inner.location
        head = anchor + inner.length
    }

    /// Accepts half-typed text as it stands.
    public mutating func unmark() { marked = nil }

    public mutating func deleteBackward() {
        if selection.length > 0 { return replace(selection, with: "") }
        guard head > 0 else { return }
        let range = (text as NSString).rangeOfComposedCharacterSequence(at: head - 1)
        replace(range, with: "")
    }

    public mutating func deleteForward() {
        if selection.length > 0 { return replace(selection, with: "") }
        guard head < length else { return }
        replace((text as NSString).rangeOfComposedCharacterSequence(at: head), with: "")
    }

    public mutating func deleteWordBackward() {
        if selection.length > 0 { return replace(selection, with: "") }
        let start = wordStart(before: head)
        replace(NSRange(location: start, length: head - start), with: "")
    }

    // MARK: Moving

    public enum Move {
        case left, right, wordLeft, wordRight, up, down, lineStart, lineEnd, textStart, textEnd
    }

    /// Moves the caret, or with `extending` the selection's far end. Left
    /// and right with a selection and no Shift collapse it to that side, as
    /// every Mac text field does. `goalX` keeps the column steady through a
    /// run of up and down moves; it is cleared by any other move.
    public mutating func move(_ move: Move, extending: Bool, in geometry: TextGeometry, goalX: inout Double?) {
        if move != .up && move != .down { goalX = nil }
        let s = selection
        var p: Int
        switch move {
        case .left:
            if !extending && s.length > 0 { return place(s.location) }
            p = head > 0 ? (text as NSString).rangeOfComposedCharacterSequence(at: head - 1).location : 0
        case .right:
            if !extending && s.length > 0 { return place(s.location + s.length) }
            p = head < length ? NSMaxRange((text as NSString).rangeOfComposedCharacterSequence(at: head)) : length
        case .wordLeft: p = wordStart(before: head)
        case .wordRight: p = wordEnd(after: head)
        case .up, .down:
            let row = geometry.line(of: head) + (move == .up ? -1 : 1)
            let x = goalX ?? Double(geometry.caret(at: head).minX)
            goalX = x
            if row < 0 { p = 0 } else if row >= geometry.lines.count { p = length } else { p = geometry.position(onLine: row, x: x) }
        case .lineStart: p = geometry.lineBounds(of: head).start
        case .lineEnd: p = geometry.lineBounds(of: head).end
        case .textStart: p = 0
        case .textEnd: p = length
        }
        place(p, extending: extending)
    }

    // MARK: Helpers

    private mutating func replace(_ range: NSRange, with string: String) {
        let r = clamped(range)
        text = (text as NSString).replacingCharacters(in: r, with: string)
        let p = r.location + (string as NSString).length
        anchor = p
        head = p
    }

    private func clamped(_ range: NSRange) -> NSRange {
        let lo = min(max(range.location, 0), length)
        return NSRange(location: lo, length: min(max(range.length, 0), length - lo))
    }

    /// Never inside a character made of several UTF-16 units.
    private func snapped(_ position: Int) -> Int {
        guard position > 0, position < length else { return position }
        return (text as NSString).rangeOfComposedCharacterSequence(at: position).location
    }

    private func isWord(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "’"
    }

    private func wordStart(before position: Int) -> Int {
        let ns = text as NSString
        var p = min(position, length)
        while p > 0, !isWord(ns.character(at: p - 1)) { p -= 1 }
        while p > 0, isWord(ns.character(at: p - 1)) { p -= 1 }
        return p
    }

    private func wordEnd(after position: Int) -> Int {
        let ns = text as NSString
        var p = max(position, 0)
        while p < length, !isWord(ns.character(at: p)) { p += 1 }
        while p < length, isWord(ns.character(at: p)) { p += 1 }
        return p
    }
}
