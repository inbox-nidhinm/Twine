import SwiftUI
import MotionModel
import Theme

/// Puts the AppKit canvas into the SwiftUI window, and hands it what it draws.
struct CanvasView: NSViewRepresentable {
    let controller: EditorController
    let editor: EditorModel
    let insets: EdgeInsets

    @Environment(MenuHost.self) private var menus

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        let menus = self.menus
        view.menus = menus
        view.dismissTransients = {
            guard menus.isOpen else { return false }
            menus.dismiss()
            return true
        }
        view.insets = NSEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
        // Read here rather than handed in, so a new playhead time updates the
        // canvas alone instead of the whole window's views.
        // Read so a row hovered in the layers panel lights up its layer here.
        _ = editor.hoveredLayer
        // And so the gradient being edited shows its line and handles.
        _ = editor.gradient
        view.show(controller.project, time: editor.time, selection: controller.selection, tool: editor.tool,
                  playing: editor.isPlaying, animating: editor.mode == .animate)
    }
}
