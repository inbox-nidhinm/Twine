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
}
