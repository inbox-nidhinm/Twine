import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything reads a setting or the projects folder.
        FormerName.carryOver()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Cursors.useAppArrowEverywhere()
        NSApp.mainMenu = MainMenu.build()
        try? Creations.ensureFolder()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AI apps reach Twine through its socket, while Settings allows it.
        AgentService.shared.update()
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

    func applicationWillTerminate(_ notification: Notification) {
        AgentService.shared.stop()
    }

    @objc func showHome(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
    }

    @objc func showOnboarding(_ sender: Any?) {
        OnboardingState.shared.show()
    }

    @objc func showVersionHistory(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
        HomeWindowController.shared.library.showVersionHistory = true
    }
}
