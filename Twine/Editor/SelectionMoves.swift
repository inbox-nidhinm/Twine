import AppKit
import MotionModel
import MotionEvaluation
import MotionEditing

/// Moving the selection through the layer tree from the keyboard, and
/// flipping it, as Figma has them (26 November 2026).
extension EditorController {
    /// Return: the layers inside the selected groups and frames. False when
    /// none of the selection holds any, so Return can mean something else
    /// (typing into a text, showing a shape's points).
    func selectChildren() -> Bool {
        let inside = selectedLayers.filter(\.isGroup).flatMap { $0.children.filter { !$0.isLocked } }
        guard !inside.isEmpty else { return false }
        editor.selection = Set(inside.map(\.id))
        editor.selectedActions = []
        return true
    }

    /// Shift-Return: the groups and frames holding the selection. At the
    /// top level there is nothing to go out to, and the selection stays.
    func selectParents() {
        let parents = Set(editor.selection.compactMap { project.location(of: $0)?.parentID })
        guard !parents.isEmpty else { return }
        editor.selection = parents
        editor.selectedActions = []
    }

    /// Tab and Shift-Tab: the next layer down the layers panel beside the
    /// selected one, or the one above, going round at the ends and passing
    /// over locked layers.
    func selectSibling(forward: Bool) -> Bool {
        // The panel lists front first, so the first selected in its order.
        guard let current = selectedLayers.last, let location = project.location(of: current.id) else { return false }
        let siblings = location.parentID.flatMap { project.layer(withID: $0)?.children } ?? project.layers
        guard siblings.count > 1 else { return true }
        var index = location.index
        for _ in 1..<siblings.count {
            // Stored back to front: down the panel is towards the back.
            index = (index + (forward ? -1 : 1) + siblings.count) % siblings.count
            if !siblings[index].isLocked {
                editor.selection = [siblings[index].id]
                editor.selectedActions = []
                break
            }
        }
        return true
    }

    /// Mirrors each selected layer where it stands, left to right or top to
    /// bottom: its scale that way changes sign and its turn goes the other
    /// way, about the middle of its box, so it does not move.
    func flipSelection(horizontal: Bool) {
        let layers = topmost(selectedLayers).filter { !isLocked($0.id) }
        guard !layers.isEmpty else { return NSSound.beep() }
        let flipped = layers.map { layer -> Layer in
            var l = layer
            let centre = Vec2(l.size.width / 2, l.size.height / 2)
            func place(_ t: Transform) -> Vec2 {
                Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
                    .apply(centre)
            }
            let before = place(l.transform)
            if horizontal { l.transform.scale.x = -l.transform.scale.x } else { l.transform.scale.y = -l.transform.scale.y }
            l.transform.rotation = -l.transform.rotation
            // Back to where its middle was.
            l.transform.position = l.transform.position + (before - place(l.transform))
            return l
        }
        perform(.batch([layerUpdate(flipped)], name: horizontal ? "Flip Horizontal" : "Flip Vertical"))
    }

    // MARK: Quick keys

    /// A number key: the selected layers' opacity, as one undo step.
    func setOpacity(_ value: Double) {
        let layers = selectedLayers.filter { !isLocked($0.id) }
        guard !layers.isEmpty else { return }
        perform(.batch([layerUpdate(layers.map { layer in
            var l = layer
            l.opacity = min(max(value, 0), 1)
            return l
        })], name: "Opacity"))
    }

    /// Shift-X: each selected shape's top fill and top stroke change
    /// places. With only one of them, it becomes the other. A picture
    /// stays a fill.
    func swapFillAndStroke() {
        var changed = false
        let edited = selectedLayers.filter { !isLocked($0.id) }.compactMap { layer -> Layer? in
            guard var look = layer.look else { return nil }
            let fill = look.topFillIndex, stroke = look.strokes.indices.last
            if let fill, look.fills[fill].paint.isImage { return nil }
            switch (fill, stroke) {
            case let (f?, s?):
                let paint = look.fills[f].paint
                look.fills[f].paint = look.strokes[s].paint
                look.strokes[s].paint = paint
            case let (f?, nil):
                look.strokes.append(Stroke(paint: look.fills[f].paint, width: 2))
                look.fills.remove(at: f)
            case let (nil, s?):
                look.fills.append(Fill(paint: look.strokes[s].paint))
                look.strokes.remove(at: s)
            case (nil, nil):
                return nil
            }
            var l = layer
            l.look = look
            changed = true
            return l
        }
        guard changed else { return NSSound.beep() }
        perform(.batch([layerUpdate(edited)], name: "Swap Fill and Stroke"))
    }

    /// Option-/ and Shift-/: every fill, or every stroke, of the selected
    /// shapes taken away.
    func removePaints(fills: Bool) {
        let ids = selectedLayers.filter { layer in
            guard !isLocked(layer.id), let look = layer.look else { return false }
            return fills ? !look.fills.isEmpty : !look.strokes.isEmpty
        }.map(\.id)
        guard !ids.isEmpty else { return NSSound.beep() }
        editLooks(ids) { look in
            if fills { look.fills = [] } else { look.strokes = [] }
        }
    }

    /// I: a colour picked from anywhere on the screen becomes the selected
    /// shapes' top fill and the selected texts' colour, each keeping its
    /// own opacity.
    func pickFillFromScreen() {
        guard !selectedLayers.isEmpty else { return NSSound.beep() }
        NSColorSampler().show { [weak self] sampled in
            guard let sampled else { return }
            let colour = RGBA(sampled)
            MainActor.assumeIsolated { self?.fillSelection(with: colour) }
        }
    }

    func fillSelection(with colour: RGBA) {
        let edited = selectedLayers.filter { !isLocked($0.id) }.compactMap { layer -> Layer? in
            if layer.isText {
                return layer.editingText { $0.color = RGBA(colour.r, colour.g, colour.b, $0.color.a) }
            }
            guard var look = layer.look else { return nil }
            if let top = look.topFillIndex {
                var alpha = 1.0
                if case .solid(let old) = look.fills[top].paint { alpha = old.a }
                look.fills[top].paint = .solid(RGBA(colour.r, colour.g, colour.b, alpha))
            } else {
                look.fills.append(Fill(paint: .solid(RGBA(colour.r, colour.g, colour.b, 1))))
            }
            var l = layer
            l.look = look
            return l
        }
        guard !edited.isEmpty else { return NSSound.beep() }
        perform(.batch([layerUpdate(edited)], name: "Pick Colour"))
    }

    /// Shift-Command-L: locks the selection, or unlocks it when all of it
    /// is locked already.
    func toggleLockSelection() {
        let ids = editor.selection
        guard !ids.isEmpty else { return }
        let allLocked = ids.allSatisfy { project.layer(withID: $0)?.isLocked == true }
        perform(.setLocked(ids, !allLocked))
    }

    /// Hides the selection, or shows it when all of it is hidden already.
    func toggleHideSelection() {
        let ids = editor.selection
        guard !ids.isEmpty else { return }
        let allHidden = ids.allSatisfy { project.layer(withID: $0)?.isVisible == false }
        perform(.setVisible(ids, allHidden))
    }
}
