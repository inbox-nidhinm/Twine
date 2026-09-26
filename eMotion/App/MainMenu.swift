import AppKit

/// The menu bar, built in code. Items name a selector and no target, so each
/// one goes to whichever window, window controller or document is in front,
/// and greys itself out when nothing there can answer.
enum MainMenu {
    static func build() -> NSMenu {
        let bar = NSMenu()
        bar.addItem(submenu(appMenu()))
        bar.addItem(submenu(fileMenu()))
        bar.addItem(submenu(editMenu()))
        bar.addItem(submenu(viewMenu()))
        bar.addItem(submenu(playbackMenu()))
        let window = windowMenu()
        bar.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        bar.addItem(submenu(help))
        NSApp.helpMenu = help
        return bar
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "eMotion")
        menu.addItem(item("About eMotion", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(item("Version History", #selector(AppDelegate.showVersionHistory(_:))))
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item("Hide eMotion", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit eMotion", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Project", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(item("Home", #selector(AppDelegate.showHome(_:)), "h", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert To…", #selector(NSDocument.browseVersions(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Export…", #selector(EditorWindowController.exportFile(_:)), "e"))
        menu.addItem(item("Export Current Frame…", #selector(EditorWindowController.exportFrame(_:)), "e",
                          [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Show in Finder", #selector(NSDocument.showInFinder(_:))))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("Duplicate", #selector(EditorWindowController.duplicateLayers(_:)), "d"))
        menu.addItem(item("Rename Layer", #selector(EditorWindowController.renameLayer(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Stagger Actions…", #selector(EditorWindowController.staggerActions(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Group", #selector(EditorWindowController.groupLayers(_:)), "g"))
        menu.addItem(item("Ungroup", #selector(EditorWindowController.ungroupLayers(_:)), "g", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Bring Forward", #selector(EditorWindowController.bringForward(_:)), "]"))
        menu.addItem(item("Send Backward", #selector(EditorWindowController.sendBackward(_:)), "["))
        menu.addItem(item("Bring to Front", #selector(EditorWindowController.bringToFront(_:)), "]", [.command, .option]))
        menu.addItem(item("Send to Back", #selector(EditorWindowController.sendToBack(_:)), "[", [.command, .option]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        // M works on the canvas and the timeline without being a menu key,
        // so an M typed into a field stays an M. The menu names it.
        menu.addItem(item("Design", #selector(EditorWindowController.switchToDesignMode(_:))))
        menu.addItem(item("Animate", #selector(EditorWindowController.switchToAnimateMode(_:))))
        menu.addItem(item("Switch Mode    M", #selector(EditorWindowController.toggleMode(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Layers", #selector(EditorWindowController.toggleLayersPanel(_:)), "1"))
        menu.addItem(item("Hide Inspector", #selector(EditorWindowController.toggleInspectorPanel(_:)), "2"))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-"))
        menu.addItem(item("Zoom to Fit", #selector(EditorWindowController.zoomToFit(_:)), "0"))
        menu.addItem(item("Actual Size", #selector(EditorWindowController.zoomToActualSize(_:)), "0", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    /// Space, comma, full stop, Home and End work on the canvas and the timeline
    /// without being menu keys, so a space typed into a field stays a space.
    /// The menu names them so they can be found.
    private static func playbackMenu() -> NSMenu {
        let menu = NSMenu(title: "Playback")
        menu.addItem(item("Play or Pause    Space", #selector(EditorWindowController.togglePlayback(_:))))
        menu.addItem(item("Previous Frame    ,", #selector(EditorWindowController.previousFrame(_:))))
        menu.addItem(item("Next Frame    .", #selector(EditorWindowController.nextFrame(_:))))
        menu.addItem(item("Previous Action Edge    ⌥,", #selector(EditorWindowController.previousEdge(_:))))
        menu.addItem(item("Next Action Edge    ⌥.", #selector(EditorWindowController.nextEdge(_:))))
        menu.addItem(item("Go to Start    Home", #selector(EditorWindowController.goToStart(_:))))
        menu.addItem(item("Go to End    End", #selector(EditorWindowController.goToEnd(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Loop", #selector(EditorWindowController.toggleLoop(_:))))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        NSMenu(title: "Help")
    }
}

private extension NSDocument {
    /// File > Show in Finder, for the project in front.
    @objc func showInFinder(_ sender: Any?) {
        guard let url = fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
