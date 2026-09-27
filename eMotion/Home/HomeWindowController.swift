import AppKit
import SwiftUI

/// The home screen's window. There is one, shown at launch and whenever the
/// last project closes, and put away whenever a project opens.
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = HomeWindowController()

    let library = Library()
    private let menus = MenuHost()

    private init() {
        let window = makeChromelessWindow(size: NSSize(width: 1180, height: 760), minSize: NSSize(width: 820, height: 560))
        window.title = "Twine"
        super.init(window: window)
        window.contentView = NSHostingView(rootView: HomeView(library: library).environment(menus))
        window.delegate = self
        window.setFrameAutosaveName("Home")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    override func showWindow(_ sender: Any?) {
        library.refresh()
        super.showWindow(sender)
        (window as? ChromelessWindow)?.clearInitialFocus()
        if let window { TrafficLights.retry(in: window) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Renames and new files from the Finder show up when you come back.
        library.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        menus.dismiss()
        library.showVersionHistory = false
    }
}
