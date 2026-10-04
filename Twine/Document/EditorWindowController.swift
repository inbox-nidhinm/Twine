import AppKit
import Theme
import SwiftUI
import MotionEditing
import MotionExport

/// A project's editor, in the app's one window (`MainWindow`), which it takes
/// from the home screen or from the project before. It sits in the responder
/// chain, so the View menu's commands find the editor.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let editor: EditorModel
    let controller: EditorController
    private let menus = MenuHost()

    init(document: ProjectDocument, store: ProjectStore) {
        editor = document.editor
        controller = EditorController(store: store, editor: document.editor)
        controller.document = document
        let window = MainWindow.take { HomeWindowController.shared.library.refresh() }
        super.init(window: window)
        window.windowController = self

        let root = EditorView(document: document, store: store, editor: editor, controller: controller)
            .environment(menus)
        window.delegate = self
        shouldCascadeWindows = false
        MainWindow.present(NSHostingView(rootView: root), in: window)
        editor.exports.request = { [weak self] in self?.export($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let window { TrafficLights.retry(in: window) }
    }

    /// Gives the window up to the home screen or another project: typing
    /// finishes, playback, menus and any export stop, and the project closes
    /// once it has saved.
    func leave(then: @escaping () -> Void) {
        menus.dismiss()
        controller.finishEditing()
        controller.closeDown()
        controller.stop()
        editor.exports.cancel()
        let document = document as? ProjectDocument
        window?.delegate = nil
        window = nil
        document?.removeWindowController(self)
        if let document { document.closeAfterSaving(then: then) } else { then() }
    }

    // MARK: NSWindowDelegate

    /// Closing the window closes the project and, as it is the only window,
    /// the app.
    func windowWillClose(_ notification: Notification) {
        menus.dismiss()
        controller.finishEditing()
        controller.closeDown()
        editor.exports.cancel()
    }

    // MARK: File menu

    /// Brings up the export panel, or with it up, exports as it is set.
    @objc func exportFile(_ sender: Any?) {
        if editor.showExport { export(nil) } else { controller.openExport() }
    }
    /// A PNG of what the canvas shows, whatever the Export section has chosen.
    @objc func exportFrame(_ sender: Any?) { export(.png) }

    private func export(_ format: ExportFormat?) {
        controller.stop()
        editor.exports.begin(format: format, project: controller.project, time: editor.time,
                             design: editor.mode == .design, name: exportName,
                             media: (document as? ProjectDocument)?.mediaURLs ?? [:], window: window)
    }

    /// Asks for pictures, video or sound to bring in as layers.
    @objc func importMedia(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaImport.types
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard response == .OK, let urls = panel?.urls else { return }
            self?.controller.importMedia(urls)
        }
    }

    /// The project's name without its extension, which Finder shows in
    /// `displayName` when extensions are on.
    private var exportName: String {
        let document = document as? NSDocument
        return document?.fileURL?.deletingPathExtension().lastPathComponent ?? document?.displayName ?? "Untitled"
    }

    // MARK: View menu

    @objc func toggleLayersPanel(_ sender: Any?) { editor.showLayers.toggle() }
    @objc func toggleInspectorPanel(_ sender: Any?) { editor.showInspector.toggle() }
    @objc func switchToDesignMode(_ sender: Any?) { controller.setMode(.design) }
    @objc func switchToAnimateMode(_ sender: Any?) { controller.setMode(.animate) }
    @objc func toggleMode(_ sender: Any?) { controller.toggleMode() }

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
    @objc func copyEasing(_ sender: Any?) { controller.copyEasing() }
    @objc func pasteEasing(_ sender: Any?) { controller.pasteEasing() }
    @objc func groupLayers(_ sender: Any?) { controller.groupSelection() }
    @objc func ungroupLayers(_ sender: Any?) { controller.ungroupSelection() }
    @objc func frameLayers(_ sender: Any?) { controller.frameSelection() }
    @objc func useAsMask(_ sender: Any?) { controller.useSelectionAsMask() }
    @objc func bringForward(_ sender: Any?) { controller.restack(.forward) }
    @objc func sendBackward(_ sender: Any?) { controller.restack(.backward) }
    @objc func bringToFront(_ sender: Any?) { controller.restack(.front) }
    @objc func sendToBack(_ sender: Any?) { controller.restack(.back) }

    // MARK: Playback menu

    @objc func togglePlayback(_ sender: Any?) { controller.togglePlay() }
    @objc func previousFrame(_ sender: Any?) { controller.step(-1) }
    @objc func nextFrame(_ sender: Any?) { controller.step(1) }
    @objc func goToStart(_ sender: Any?) { controller.jumpToStart() }
    @objc func previousEdge(_ sender: Any?) { controller.jumpToEdge(forward: false) }
    @objc func nextEdge(_ sender: Any?) { controller.jumpToEdge(forward: true) }

    /// Raises the stagger card over the top of the timeline.
    @objc func staggerActions(_ sender: Any?) {
        guard let height = window?.contentView?.bounds.height else { return }
        let origin = CGPoint(x: Theme.floatInset + Theme.floatGap,
                             y: height - Theme.floatInset - editor.timelineHeight + Theme.barRow + 4)
        menus.showPopup(at: origin) {
            StaggerCard(controller: controller) { [menus] in menus.dismiss() }
        }
    }
    @objc func goToEnd(_ sender: Any?) { controller.jumpToEnd() }
    @objc func toggleLoop(_ sender: Any?) { editor.loops.toggle() }
    @objc func toggleSnapping(_ sender: Any?) { editor.snaps.toggle() }
    @objc func toggleShortcuts(_ sender: Any?) { editor.showShortcuts.toggle() }

    // MARK: Arrange

    /// The menu item's tag is the edge's place in `Alignment.Edge.allCases`.
    @objc func alignLayers(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, Alignment.Edge.allCases.indices.contains(tag) else { return }
        controller.align(Alignment.Edge.allCases[tag])
    }
    @objc func distributeHorizontally(_ sender: Any?) { controller.distribute(.x) }
    @objc func distributeVertically(_ sender: Any?) { controller.distribute(.y) }

    // MARK: Zoom

    @objc func zoomIn(_ sender: Any?) { controller.canvas?.zoom(by: 2) }
    @objc func zoomOut(_ sender: Any?) { controller.canvas?.zoom(by: 0.5) }
    @objc func zoomToFit(_ sender: Any?) { controller.canvas?.fitToWindow(animated: true) }
    @objc func zoomToActualSize(_ sender: Any?) { controller.canvas?.zoomToActualSize() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasSelection = !controller.selection.isEmpty
        switch item.action {
        case #selector(exportFile(_:)), #selector(exportFrame(_:)):
            return !editor.exports.isExporting
        case #selector(delete(_:)), #selector(copy(_:)), #selector(cut(_:)), #selector(duplicateLayers(_:)),
             #selector(groupLayers(_:)), #selector(frameLayers(_:)), #selector(useAsMask(_:)), #selector(bringForward(_:)), #selector(sendBackward(_:)),
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
            return editor.mode == .animate
        case #selector(previousFrame(_:)), #selector(nextFrame(_:)), #selector(goToStart(_:)), #selector(goToEnd(_:)),
             #selector(previousEdge(_:)), #selector(nextEdge(_:)):
            return editor.mode == .animate
        case #selector(copyEasing(_:)):
            return controller.canCopyEasing
        case #selector(pasteEasing(_:)):
            return controller.canPasteEasing
        case #selector(staggerActions(_:)):
            return editor.mode == .animate && controller.selectedActions.count > 1
        case #selector(toggleLoop(_:)):
            item.state = editor.loops ? .on : .off
        case #selector(toggleSnapping(_:)):
            item.state = editor.snaps ? .on : .off
        case #selector(toggleShortcuts(_:)):
            item.state = editor.showShortcuts ? .on : .off
        case #selector(alignLayers(_:)):
            return controller.canAlign
        case #selector(distributeHorizontally(_:)), #selector(distributeVertically(_:)):
            return controller.canDistribute
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
