import AppKit
import SwiftUI
import MotionEditing

/// The window a project edits in. It sits in the responder chain, so the View
/// menu's commands find the editor of whichever window is in front.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let editor: EditorModel
    private let menus = MenuHost()

    init(document: ProjectDocument, store: ProjectStore) {
        editor = document.editor
        let window = makeChromelessWindow(size: NSSize(width: 1440, height: 920), minSize: NSSize(width: 980, height: 660))
        super.init(window: window)

        let root = EditorView(document: document, store: store, editor: editor)
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

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
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
