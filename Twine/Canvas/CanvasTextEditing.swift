import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation

/// Typing into one text layer on the canvas.
struct TextSession {
    let layerID: UUID
    var text: EditableText
    /// The column kept through a run of up and down arrows.
    var goalX: Double?
    /// Undo and redo inside the session. Afterwards the whole session undoes
    /// as one step.
    var history: [EditableText] = []
    var future: [EditableText] = []
    var lastChange = Date.distantPast
    var lastKind = ""
    /// Whether a mouse drag is selecting letters.
    var selecting = false
}

/// Editing text in place: the canvas takes the keyboard through AppKit's
/// text input system, so accents, press-and-hold and input methods work as
/// they do in any Mac text field, and draws its own caret and selection
/// from the same layout that draws the letters, so they sit exactly on them.
///
/// It begins with a double-click on a text layer, Return with one selected,
/// or the Text tool, and ends with Escape, a click away from the layer, or a
/// change of selection or mode. A text left empty is removed.
extension CanvasNSView: NSTextInputClient, NSMenuItemValidation {
    var isEditingText: Bool { textSession != nil }

    // MARK: Beginning and ending

    /// Starts typing into `id`, with every letter selected, or with the
    /// caret at `point` (in composition space) when given.
    func beginTextEditing(_ id: UUID, selectAll: Bool, at point: Vec2? = nil) {
        guard let controller, !animating, textSession == nil,
              let layer = controller.project.layer(withID: id), case .text(let content) = layer.content else { return }
        controller.select([id])
        var session = TextSession(layerID: id, text: EditableText(text: content.text, selectAll: selectAll))
        textSession = session
        if let point, let local = localPoint(point), let geometry = geometry() {
            session.text.place(geometry.position(at: local))
            textSession = session
        }
        controller.begin("Edit Text")
        controller.editor.editingText = id
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        restartCaret()
        redrawOverlay()
    }

    /// Stops typing. The session is one undo step; a text left empty goes.
    func endTextEditing() {
        guard let session = textSession, let controller else { return }
        inputContext?.discardMarkedText()
        textSession = nil
        caretTimer?.invalidate()
        caretTimer = nil
        controller.end()
        controller.editor.editingText = nil
        if session.text.text.isEmpty, controller.project.layer(withID: session.layerID) != nil {
            _ = controller.perform(.deleteLayers([session.layerID]))
        }
        overlay.updateText(selection: nil, marked: nil, caret: nil)
        window?.invalidateCursorRects(for: self)
        redrawOverlay()
    }

    // MARK: Geometry

    private var editedContent: TextContent? {
        guard let id = textSession?.layerID, case .text(let t)? = controller?.project.layer(withID: id)?.content else { return nil }
        return t
    }

    /// The text as it is set now, in the layer's own space.
    private func geometry() -> TextGeometry? {
        guard let session = textSession, let content = editedContent,
              let resolved = scene?.layer(session.layerID) else { return nil }
        return TextGeometry(text: session.text.text, style: TextStyle(content),
                            width: content.sizing == .fixedWidth ? resolved.size.width : nil)
    }

    /// A composition point in the text box's own space.
    private func localPoint(_ point: Vec2) -> CGPoint? {
        guard let id = textSession?.layerID, let inverse = scene?.worldTransform(of: id)?.inverted else { return nil }
        return inverse.apply(point).cg
    }

    private func toView(_ local: CGPoint) -> CGPoint? {
        guard let id = textSession?.layerID, let world = scene?.worldTransform(of: id) else { return nil }
        return compositionToView(world.apply(Vec2(Double(local.x), Double(local.y))))
    }

    /// Whether a composition point is on the text being edited, with a few
    /// points to spare.
    func isOnEditedText(_ point: Vec2) -> Bool {
        guard let local = localPoint(point), let id = textSession?.layerID, let size = scene?.layer(id)?.size else { return false }
        let spare = 6 / max(zoom, 0.01)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height).insetBy(dx: -spare, dy: -spare).contains(local)
    }

    // MARK: Drawing

    /// Redraws the selection, half-typed underline and caret, in view points.
    func updateTextOverlay() {
        guard let session = textSession, let geometry = geometry() else {
            overlay.updateText(selection: nil, marked: nil, caret: nil)
            return
        }
        func quad(_ r: CGRect) -> [CGPoint]? {
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                           CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)].compactMap(toView)
            return corners.count == 4 ? corners : nil
        }
        let selected = CGMutablePath()
        for r in geometry.selectionRects(session.text.selection) {
            if let q = quad(r) { selected.addLines(between: q); selected.closeSubpath() }
        }
        let marked = CGMutablePath()
        if let range = session.text.marked {
            for r in geometry.selectionRects(range) {
                if let a = toView(CGPoint(x: r.minX, y: r.maxY - r.height * 0.12)),
                   let b = toView(CGPoint(x: r.maxX, y: r.maxY - r.height * 0.12)) {
                    marked.move(to: a)
                    marked.addLine(to: b)
                }
            }
        }
        var caret: CGPath?
        if session.text.selection.length == 0 {
            let r = geometry.caret(at: session.text.head)
            if let top = toView(CGPoint(x: r.minX, y: r.minY)), let bottom = toView(CGPoint(x: r.minX, y: r.maxY)) {
                // Two points wide, whatever the zoom or the layer's turn.
                let dx = bottom.x - top.x, dy = bottom.y - top.y
                let length = max(hypot(dx, dy), 0.001)
                let n = CGPoint(x: -dy / length, y: dx / length)
                let path = CGMutablePath()
                path.addLines(between: [CGPoint(x: top.x - n.x, y: top.y - n.y), CGPoint(x: top.x + n.x, y: top.y + n.y),
                                        CGPoint(x: bottom.x + n.x, y: bottom.y + n.y), CGPoint(x: bottom.x - n.x, y: bottom.y - n.y)])
                path.closeSubpath()
                caret = path
            }
        }
        overlay.updateText(selection: selected.isEmpty ? nil : selected, marked: marked.isEmpty ? nil : marked, caret: caret)
    }

    /// Shows the caret at once and starts it blinking again, as it does after
    /// every keystroke in a Mac text field.
    func restartCaret() {
        caretTimer?.invalidate()
        overlay.showCaret(true)
        var visible = true
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                visible.toggle()
                self?.overlay.showCaret(visible && self?.window?.firstResponder === self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        caretTimer = timer
    }

    // MARK: Changing the text

    /// Makes a change, keeping a step to undo inside the session whenever
    /// the kind of change differs from the last, a second has passed, or a
    /// word has ended, then writes the words to the layer.
    private func change(_ kind: String, _ edit: (inout EditableText) -> Void) {
        guard var session = textSession else { return }
        let before = session.text
        edit(&session.text)
        guard session.text != before else { return }
        let now = Date()
        let wordEnded = session.text.text.hasSuffix(" ") || session.text.text.hasSuffix("\n")
        if kind != session.lastKind || now.timeIntervalSince(session.lastChange) > 1 || wordEnded {
            session.history.append(before)
            if session.history.count > 200 { session.history.removeFirst() }
        }
        session.future = []
        session.lastKind = kind
        session.lastChange = now
        session.goalX = nil
        textSession = session
        write(before: before.text)
    }

    /// Puts the session's words into the layer, as part of the session's one
    /// undo step. A name never changed by hand follows the words.
    private func write(before old: String) {
        guard let session = textSession, let controller, let layer = controller.project.layer(withID: session.layerID),
              case .text(var content) = layer.content else { return }
        guard content.text != session.text.text else { return updateTextOverlay() }
        var l = layer
        l.name = EditorController.textName(renaming: l.name, from: old, to: session.text.text)
        content.text = session.text.text
        l.content = .text(content)
        controller.update([l])
        inputContext?.invalidateCharacterCoordinates()
        window?.invalidateCursorRects(for: self)
        restartCaret()
    }

    /// Moves the caret or selection without changing the words.
    private func moveCaret(_ move: EditableText.Move, extending: Bool) {
        guard var session = textSession, let geometry = geometry() else { return }
        session.text.move(move, extending: extending, in: geometry, goalX: &session.goalX)
        session.lastKind = "move"
        textSession = session
        restartCaret()
        updateTextOverlay()
    }

    private func adjust(_ edit: (inout EditableText) -> Void) {
        guard var session = textSession else { return }
        edit(&session.text)
        session.goalX = nil
        textSession = session
        restartCaret()
        updateTextOverlay()
    }

    // MARK: Mouse

    /// A click while typing: on the text it moves the caret (Shift extends
    /// the selection, a double-click takes a word, a triple-click all of it);
    /// anywhere else it ends the typing and returns false, so the click goes
    /// on to do what it would have.
    func textMouseDown(_ event: NSEvent, at point: Vec2) -> Bool {
        guard textSession != nil else { return false }
        guard isOnEditedText(point), let local = localPoint(point), let geometry = geometry() else {
            endTextEditing()
            return false
        }
        let position = geometry.position(at: local)
        adjust { text in
            text.unmark()
            switch event.clickCount {
            case 2: text.selectWord(at: position)
            case 3...: text.selectAll()
            default: text.place(position, extending: event.modifierFlags.contains(.shift))
            }
        }
        textSession?.selecting = event.clickCount == 1
        return true
    }

    func textMouseDragged(at point: Vec2) -> Bool {
        guard textSession?.selecting == true, let local = localPoint(point), let geometry = geometry() else {
            return textSession != nil
        }
        adjust { $0.place(geometry.position(at: local), extending: true) }
        return true
    }

    func textMouseUp() -> Bool {
        guard textSession != nil else { return false }
        textSession?.selecting = false
        return true
    }

    // MARK: Keyboard

    /// Escape ends the typing; everything else goes to AppKit's text input,
    /// which comes back as `insertText` or a command.
    func textKeyDown(_ event: NSEvent) -> Bool {
        guard textSession != nil else { return false }
        if event.keyCode == 53 && !hasMarkedText() {
            endTextEditing()
            return true
        }
        interpretKeyEvents([event])
        return true
    }

    /// The editing commands AppKit's key bindings send.
    func textCommand(_ selector: Selector) -> Bool {
        guard textSession != nil else { return false }
        switch selector {
        case #selector(deleteBackward(_:)): change("delete") { $0.deleteBackward() }
        case #selector(deleteForward(_:)): change("delete") { $0.deleteForward() }
        case #selector(deleteWordBackward(_:)): change("delete") { $0.deleteWordBackward() }
        case #selector(deleteToBeginningOfLine(_:)):
            if let g = geometry() {
                change("delete") { t in
                    let start = g.lineBounds(of: t.head).start
                    if t.selection.length == 0 { t.place(start, extending: true) }
                    t.deleteBackward()
                }
            }
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
            change("type") { $0.insert("\n") }
        case #selector(insertTab(_:)): change("type") { $0.insert("\t") }
        case #selector(moveLeft(_:)): moveCaret(.left, extending: false)
        case #selector(moveRight(_:)): moveCaret(.right, extending: false)
        case #selector(moveUp(_:)): moveCaret(.up, extending: false)
        case #selector(moveDown(_:)): moveCaret(.down, extending: false)
        case #selector(moveLeftAndModifySelection(_:)): moveCaret(.left, extending: true)
        case #selector(moveRightAndModifySelection(_:)): moveCaret(.right, extending: true)
        case #selector(moveUpAndModifySelection(_:)): moveCaret(.up, extending: true)
        case #selector(moveDownAndModifySelection(_:)): moveCaret(.down, extending: true)
        case #selector(moveWordLeft(_:)): moveCaret(.wordLeft, extending: false)
        case #selector(moveWordRight(_:)): moveCaret(.wordRight, extending: false)
        case #selector(moveWordLeftAndModifySelection(_:)): moveCaret(.wordLeft, extending: true)
        case #selector(moveWordRightAndModifySelection(_:)): moveCaret(.wordRight, extending: true)
        case #selector(moveToBeginningOfLine(_:)), #selector(moveToLeftEndOfLine(_:)): moveCaret(.lineStart, extending: false)
        case #selector(moveToEndOfLine(_:)), #selector(moveToRightEndOfLine(_:)): moveCaret(.lineEnd, extending: false)
        case #selector(moveToBeginningOfLineAndModifySelection(_:)), #selector(moveToLeftEndOfLineAndModifySelection(_:)):
            moveCaret(.lineStart, extending: true)
        case #selector(moveToEndOfLineAndModifySelection(_:)), #selector(moveToRightEndOfLineAndModifySelection(_:)):
            moveCaret(.lineEnd, extending: true)
        case #selector(moveToBeginningOfDocument(_:)): moveCaret(.textStart, extending: false)
        case #selector(moveToEndOfDocument(_:)): moveCaret(.textEnd, extending: false)
        case #selector(moveToBeginningOfDocumentAndModifySelection(_:)): moveCaret(.textStart, extending: true)
        case #selector(moveToEndOfDocumentAndModifySelection(_:)): moveCaret(.textEnd, extending: true)
        case #selector(cancelOperation(_:)): endTextEditing()
        default: break
        }
        return true
    }

    // MARK: Menu commands while typing

    @objc func textCopy(_ sender: Any?) {
        guard let session = textSession, session.text.selection.length > 0 else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.text.selectedText, forType: .string)
    }

    @objc func textCut(_ sender: Any?) {
        textCopy(sender)
        change("cut") { $0.deleteBackward() }
    }

    @objc func textPaste(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string) else { return NSSound.beep() }
        change("paste") { $0.insert(string) }
    }

    @objc func textSelectAll(_ sender: Any?) { adjust { $0.selectAll() } }

    @objc func textUndo(_ sender: Any?) {
        guard var session = textSession, let previous = session.history.popLast() else { return NSSound.beep() }
        let old = session.text.text
        session.future.append(session.text)
        session.text = previous
        session.lastKind = "undo"
        textSession = session
        write(before: old)
    }

    @objc func textRedo(_ sender: Any?) {
        guard var session = textSession, let next = session.future.popLast() else { return NSSound.beep() }
        let old = session.text.text
        session.history.append(session.text)
        session.text = next
        session.lastKind = "undo"
        textSession = session
        write(before: old)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let session = textSession else { return false }
        switch item.action {
        case #selector(NSText.copy(_:)), #selector(NSText.cut(_:)): return session.text.selection.length > 0
        case #selector(NSText.paste(_:)): return NSPasteboard.general.string(forType: .string) != nil
        case #selector(CanvasNSView.undo(_:)):
            item.title = "Undo Typing"
            return !session.history.isEmpty
        case #selector(CanvasNSView.redo(_:)):
            item.title = "Redo Typing"
            return !session.future.isEmpty
        default: return true
        }
    }

    // MARK: NSTextInputClient

    private func string(of value: Any) -> String {
        (value as? NSAttributedString)?.string ?? (value as? String) ?? ""
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let s = self.string(of: string)
        change(s == " " ? "space" : "type") { t in
            if replacementRange.location != NSNotFound { t.select(replacementRange) }
            t.insert(s)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let s = self.string(of: string)
        change("compose") { t in
            if replacementRange.location != NSNotFound, t.marked == nil { t.select(replacementRange) }
            t.setMarked(s, selected: selectedRange)
        }
        updateTextOverlay()
    }

    func unmarkText() { adjust { $0.unmark() } }

    func selectedRange() -> NSRange { textSession?.text.selection ?? NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange { textSession?.text.marked ?? NSRange(location: NSNotFound, length: 0) }

    func hasMarkedText() -> Bool { textSession?.text.marked != nil }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let text = textSession?.text.text else { return nil }
        let ns = text as NSString
        let lo = min(max(range.location, 0), ns.length)
        let r = NSRange(location: lo, length: min(range.length, ns.length - lo))
        actualRange?.pointee = r
        return NSAttributedString(string: ns.substring(with: r))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// Where the characters are on screen, for placing an input method's
    /// candidate window beside them.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let geometry = geometry(), let window else { return .zero }
        let r = geometry.caret(at: range.location)
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY)].compactMap(toView)
        guard corners.count == 2 else { return .zero }
        let box = NSRect(x: min(corners[0].x, corners[1].x), y: min(corners[0].y, corners[1].y),
                         width: 1, height: abs(corners[1].y - corners[0].y))
        return window.convertToScreen(convert(box, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let window, let geometry = geometry() else { return NSNotFound }
        let inView = convert(window.convertPoint(fromScreen: point), from: nil)
        guard let local = localPoint(viewToComposition(inView)) else { return NSNotFound }
        return geometry.position(at: local)
    }
}

extension EditorController {
    /// A text layer's name after its words change: it follows the words while
    /// it is still the words (or the name a new text layer is given), and
    /// keeps a name given by hand.
    static func textName(renaming name: String, from old: String, to new: String) -> String {
        name == textName(for: old) || name.wholeMatch(of: /Text \d+/) != nil || name == "Text" ? textName(for: new) : name
    }

    /// The first line of the words, as a layer name.
    static func textName(for text: String) -> String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Text" : String(trimmed.prefix(40))
    }
}
