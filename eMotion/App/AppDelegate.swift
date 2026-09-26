import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Cursors.useAppArrowEverywhere()
        NSApp.mainMenu = MainMenu.build()
        try? Creations.ensureFolder()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A project double-clicked in the Finder arrives around now. Waiting a
        // turn lets it open first, so the home screen only shows if nothing did.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                HomeWindowController.shared.showWindow(nil)
            }
        }
    }

    /// No untitled document at launch or when the Dock icon is clicked. The
    /// home screen is where a new project starts.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { HomeWindowController.shared.showWindow(nil) }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func showHome(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
    }

    @objc func showVersionHistory(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
        HomeWindowController.shared.library.showVersionHistory = true
    }
}
