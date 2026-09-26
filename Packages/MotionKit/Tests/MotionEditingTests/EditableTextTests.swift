import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private let style = TextStyle(fontFamily: "SF Pro", fontWeight: 400, fontSize: 40, alignment: .left,
                              letterSpacing: 0, lineHeight: 50)

private func geometry(_ e: EditableText, width: Double? = nil) -> TextGeometry {
    TextGeometry(text: e.text, style: style, width: width)
}

@Suite struct EditableTextTests {
    @Test func typingReplacesTheSelection() {
        var e = EditableText(text: "Text", selectAll: true)
        e.insert("Launch")
        #expect(e.text == "Launch" && e.selection == NSRange(location: 6, length: 0))
        e.insert(" day")
        #expect(e.text == "Launch day")
    }

    @Test func deletingTakesWholeCharacters() {
        var e = EditableText(text: "Hi 👋🏽")
        e.deleteBackward()
        #expect(e.text == "Hi ")
        e.deleteWordBackward()
        #expect(e.text == "")
    }

    @Test func movingByLetterWordAndLine() {
        var e = EditableText(text: "one two\nthree")
        var goal: Double?
        let g = geometry(e)
        e.move(.textStart, extending: false, in: g, goalX: &goal)
        e.move(.wordRight, extending: false, in: g, goalX: &goal)
        #expect(e.head == 3)
        e.move(.wordRight, extending: true, in: g, goalX: &goal)
        #expect(e.selectedText == " two")
        e.move(.left, extending: false, in: g, goalX: &goal)
        #expect(e.head == 3 && e.selection.length == 0)
        e.move(.down, extending: false, in: g, goalX: &goal)
        #expect(e.head > 9 && e.head <= 12, "about the same column on the next line")
        e.move(.lineEnd, extending: false, in: g, goalX: &goal)
        #expect(e.head == 13)
        e.move(.lineStart, extending: false, in: g, goalX: &goal)
        #expect(e.head == 8)
    }

    @Test func composingInputReplacesItselfUntilAccepted() {
        var e = EditableText(text: "caf")
        e.setMarked("´", selected: NSRange(location: 1, length: 0))
        #expect(e.text == "caf´" && e.marked == NSRange(location: 3, length: 1))
        e.insert("é")
        #expect(e.text == "café" && e.marked == nil && e.head == 4)
    }

    @Test func aDoubleClickSelectsTheWord() {
        var e = EditableText(text: "hello there world")
        e.selectWord(at: 8)
        #expect(e.selectedText == "there")
    }

    @Test func theCaretSitsOnTheLetters() {
        let g = geometry(EditableText(text: "ab\ncd"))
        #expect(g.caret(at: 0).minX == 0)
        #expect(g.caret(at: 2).minX > g.caret(at: 1).minX)
        // The second line starts a line height down.
        #expect(g.caret(at: 3).minY == 50 && g.caret(at: 3).minX == 0)
        // A click on the second line lands there.
        #expect(g.position(at: CGPoint(x: 1000, y: 60)) == 5)
        #expect(g.position(at: CGPoint(x: -5, y: 10)) == 0)
        #expect(g.selectionRects(NSRange(location: 1, length: 3)).count == 2)
    }

    @Test func wrappedLinesKeepTheirPositions() {
        let g = TextGeometry(text: "one two three four", style: style, width: 120)
        #expect(g.lines.count > 1)
        let second = g.lines[1]
        #expect(g.line(of: second.range.location) == 1)
        #expect(g.caret(at: second.range.location).minY == 50)
    }
}
