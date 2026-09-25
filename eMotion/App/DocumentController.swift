import AppKit

/// Makes File > New write a real project into `eMotion Creations` straight
/// away, instead of opening an untitled document that asks where to save it
/// on close.
final class DocumentController: NSDocumentController {
    override func newDocument(_ sender: Any?) {
        createAndOpenProject()
    }

    func createAndOpenProject() {
        do {
            let url = try Creations.makeProject()
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
