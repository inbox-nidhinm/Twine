import AppKit
import SwiftUI
import MotionEditing

/// The window a project edits in. It sits in the responder chain, so the View
/// menu's commands find the editor of whichever window is in front.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let editor: EditorModel
    let controller: EditorController
    private let menus = MenuHost()

    init(document: ProjectDocument, store: ProjectStore) {
        editor = document.editor
        controller = EditorController(store: store, editor: document.editor)
        let window = makeChromelessWindow(size: NSSize(width: 1440, height: 920), minSize: NSSize(width: 980, height: 660))
        super.init(window: window)

        let root = EditorView(document: document, store: store, editor: editor, controller: controller)
            .environment(menus)
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        (window as? ChromelessWindow)?.clearInitialFocus()
        if let window { TrafficLights.retry(in: window) }
        // The home screen gives way to the project, as it does in Flip.
        HomeWindowController.shared.close()
    }

    // MARK: NSWindowDelegate

    /// When the last project closes, the home screen comes back rather than
    /// the app quitting under you. Done before the window goes, so there is
    /// never a moment with no window at all.
    func windowWillClose(_ notification: Notification) {
        menus.dismiss()
        let others = NSApp.windows.filter { $0 !== window && $0.windowController is EditorWindowController && $0.isVisible }
        if others.isEmpty { HomeWindowController.shared.showWindow(nil) }
    }

    // MARK: View menu

    @objc func toggleLayersPanel(_ sender: Any?) { editor.showLayers.toggle() }
    @objc func toggleInspectorPanel(_ sender: Any?) { editor.showInspector.toggle() }
    @objc func switchToDesignMode(_ sender: Any?) { editor.mode = .design }
    @objc func switchToAnimateMode(_ sender: Any?) { editor.mode = .animate }

    // MARK: Edit menu

    @objc func delete(_ sender: Any?) { controller.deleteSelection() }
    @objc override func selectAll(_ sender: Any?) { controller.selectAll() }
    @objc func copy(_ sender: Any?) { controller.copySelection() }
    @objc func cut(_ sender: Any?) { controller.cutSelection() }
    @objc func paste(_ sender: Any?) { controller.paste() }
    @objc func duplicateLayers(_ sender: Any?) { controller.duplicateSelection() }
    @objc func renameLayer(_ sender: Any?) {
        guard controller.selection.count == 1 else { return }
        editor.showLayers = true
        editor.renaming = controller.selection.first
    }
    @objc func groupLayers(_ sender: Any?) { controller.groupSelection() }
    @objc func ungroupLayers(_ sender: Any?) { controller.ungroupSelection() }
    @objc func bringForward(_ sender: Any?) { controller.restack(.forward) }
    @objc func sendBackward(_ sender: Any?) { controller.restack(.backward) }
    @objc func bringToFront(_ sender: Any?) { controller.restack(.front) }
    @objc func sendToBack(_ sender: Any?) { controller.restack(.back) }

    // MARK: Playback menu

    @objc func togglePlayback(_ sender: Any?) { controller.togglePlay() }
    @objc func previousFrame(_ sender: Any?) { controller.step(-1) }
    @objc func nextFrame(_ sender: Any?) { controller.step(1) }
    @objc func goToStart(_ sender: Any?) { controller.jumpToStart() }
    @objc func goToEnd(_ sender: Any?) { controller.jumpToEnd() }
    @objc func toggleLoop(_ sender: Any?) { editor.loops.toggle() }

    // MARK: Zoom

    @objc func zoomIn(_ sender: Any?) { controller.canvas?.zoom(by: 2) }
    @objc func zoomOut(_ sender: Any?) { controller.canvas?.zoom(by: 0.5) }
    @objc func zoomToFit(_ sender: Any?) { controller.canvas?.fitToWindow(animated: true) }
    @objc func zoomToActualSize(_ sender: Any?) { controller.canvas?.zoomToActualSize() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasSelection = !controller.selection.isEmpty
        switch item.action {
        case #selector(delete(_:)), #selector(copy(_:)), #selector(cut(_:)), #selector(duplicateLayers(_:)),
             #selector(groupLayers(_:)), #selector(bringForward(_:)), #selector(sendBackward(_:)),
             #selector(bringToFront(_:)), #selector(sendToBack(_:)):
            return hasSelection
        case #selector(renameLayer(_:)):
            return controller.selection.count == 1
        case #selector(ungroupLayers(_:)):
            return controller.selectedLayers.contains(where: \.isGroup)
        case #selector(paste(_:)):
            return controller.canPaste
        case #selector(togglePlayback(_:)):
            item.title = (editor.isPlaying ? "Pause" : "Play") + "    Space"
        case #selector(toggleLoop(_:)):
            item.state = editor.loops ? .on : .off
        case #selector(selectAll(_:)):
            return !controller.project.layers.isEmpty
        case #selector(toggleLayersPanel(_:)):
            item.title = editor.showLayers ? "Hide Layers" : "Show Layers"
        case #selector(toggleInspectorPanel(_:)):
            item.title = editor.showInspector ? "Hide Inspector" : "Show Inspector"
        case #selector(switchToDesignMode(_:)):
            item.state = editor.mode == .design ? .on : .off
        case #selector(switchToAnimateMode(_:)):
            item.state = editor.mode == .animate ? .on : .off
        default:
            break
        }
        return true
    }
}
