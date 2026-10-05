import AppKit
import SwiftUI

/// The home screen, in the app's one window (`MainWindow`): shown at launch,
/// and whenever Home is chosen, which saves and closes the project that was
/// in the window.
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = HomeWindowController()

    let library = Library()
    private let menus = MenuHost()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    /// Turns the window into the home screen, closing any project in it. The
    /// list refreshes again once that project has saved, for its thumbnail.
    override func showWindow(_ sender: Any?) {
        if window !== MainWindow.window || MainWindow.window.windowController !== self {
            let window = MainWindow.take { [weak self] in self?.library.refresh() }
            self.window = window
            window.windowController = self
            window.delegate = self
            window.title = "Twine"
            // `present` keeps the window from sizing itself to the home screen.
            MainWindow.present(NSHostingView(rootView: HomeView(library: library).environment(menus)), in: window)
        }
        library.refresh()
        super.showWindow(sender)
    }

    /// Raises the ⌘K search card, or with it up, puts it away.
    @objc func showSearch(_ sender: Any?) {
        guard library.search == nil else {
            library.search = nil
            window?.makeFirstResponder(nil)
            return
        }
        guard !OnboardingState.shared.isShowing else { return }
        menus.dismiss()
        library.info = nil
        library.showVersionHistory = false
        library.search = library.searchSource()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Renames and new files from the Finder show up when you come back.
        library.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        guard window?.windowController === self else { return }
        menus.dismiss()
        library.showVersionHistory = false
        library.search = nil
    }
}
