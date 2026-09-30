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

    /// The open panel starts in the creations folder.
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        openPanel.directoryURL = Creations.folder
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
}
