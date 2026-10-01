import AppKit

/// Makes File > New write a real project into `Twine Creations` straight
/// away, instead of opening an untitled document that asks where to save it
/// on close.
final class DocumentController: NSDocumentController {
    /// From the home screen (no project open), into the folder it shows.
    override func newDocument(_ sender: Any?) {
        createAndOpenProject(in: documents.isEmpty ? HomeWindowController.shared.library.selectedFolder : nil)
    }

    /// A new project in `folder`, or loose in the creations folder.
    @MainActor
    func createAndOpenProject(in folder: URL? = nil) {
        do {
            let url = try Creations.makeProject(in: folder)
            openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Every way in (the home screen, the Finder, Open Recent, the open
    /// panel) comes here. A large project takes a moment to build the
    /// editor for, so a card says it is opening; the work waits a turn for
    /// the card to reach the screen.
    override func openDocument(withContentsOf url: URL, display: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard display, document(for: url) == nil,
              let window = NSApp.windows.first(where: { $0 is ChromelessWindow && $0.isVisible }) else {
            return super.openDocument(withContentsOf: url, display: display, completionHandler: completionHandler)
        }
        OpeningCard.show(named: url.deletingPathExtension().lastPathComponent, over: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            super.openDocument(withContentsOf: url, display: display) { document, wasOpen, error in
                completionHandler(document, wasOpen, error)
                // A turn on, once the editor has been laid out and drawn.
                DispatchQueue.main.async { OpeningCard.hide() }
            }
        }
    }

    /// The open panel starts in the creations folder.
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        openPanel.directoryURL = Creations.folder
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
}
