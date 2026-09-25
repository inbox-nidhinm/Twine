import SwiftUI
import MotionModel
import Theme

/// Puts the AppKit canvas into the SwiftUI window, and hands it what it draws.
struct CanvasView: NSViewRepresentable {
    let controller: EditorController
    let project: Project
    let time: Double
    let selection: [UUID]
    let tool: Tool
    let insets: EdgeInsets

    @Environment(MenuHost.self) private var menus

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        let menus = self.menus
        view.dismissTransients = {
            guard menus.isOpen else { return false }
            menus.dismiss()
            return true
        }
        view.insets = NSEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
        view.show(project, time: time, selection: selection, tool: tool)
    }
}
