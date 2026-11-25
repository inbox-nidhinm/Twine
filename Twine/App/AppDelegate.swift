import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Home is greyed out while the home screen is what is showing.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(showHome(_:)) { return !NSDocumentController.shared.documents.isEmpty }
        return true
    }

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

    /// Quitting stops an export that is running, so it asks first: minutes
    /// of a long export used to go with one Command-Q, without a word.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.exportStopAgreed, Self.isExporting, MainWindow.window.isVisible else { return .terminateNow }
        Self.askToStopExport(or: "Stop and Quit") { stop in
            NSApp.reply(toApplicationShouldTerminate: stop)
        }
        return .terminateLater
    }

    /// Set once the person has agreed to stop the export, so closing the
    /// window and the quit that follows it ask only once.
    static var exportStopAgreed = false

    static var isExporting: Bool {
        NSDocumentController.shared.documents.contains { ($0 as? ProjectDocument)?.editor.exports.isExporting == true }
    }

    /// Asks, on the window, whether to stop the running export. `done`
    /// hears true when the person chose to stop it.
    static func askToStopExport(or stop: String, done: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "An export is still running."
        alert.informativeText = "Stopping now leaves no file."
        alert.addButton(withTitle: "Keep Exporting")
        alert.addButton(withTitle: stop)
        alert.beginSheetModal(for: MainWindow.window) { response in
            let stops = response == .alertSecondButtonReturn
            if stops { exportStopAgreed = true }
            done(stops)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentService.shared.stop()
    }

    @objc func showHome(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
    }

    /// Settings live on the home screen, so that is where this goes.
    @objc func showSettings(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
        HomeWindowController.shared.library.showsSettings = true
    }

    @objc func showOnboarding(_ sender: Any?) {
        OnboardingState.shared.show()
    }

    @objc func showVersionHistory(_ sender: Any?) {
        HomeWindowController.shared.showWindow(nil)
        HomeWindowController.shared.library.showVersionHistory = true
    }
}
