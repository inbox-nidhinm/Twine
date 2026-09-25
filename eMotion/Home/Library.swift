import AppKit
import Observation
import MotionModel

/// Everything in `eMotion Creations`, for the home screen.
@MainActor
@Observable
final class Library {
    struct Item: Identifiable, Equatable {
        let url: URL
        let modified: Date
        /// Read from the file, so a card can show the frame's shape and ground
        /// before there is a thumbnail. Nil if the file could not be read.
        let composition: Composition?
        let thumbnail: NSImage?

        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    private(set) var items: [Item] = []
    var showVersionHistory = false

    func refresh() {
        let fm = FileManager.default
        try? Creations.ensureFolder()
        let urls = (try? fm.contentsOfDirectory(at: Creations.folder,
                                                includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        // A project is a folder, so it is picked out by its extension rather
        // than by whether it is a directory.
        let found = urls.filter { $0.pathExtension == ProjectFormat.fileExtension }.map { url in
            let document = url.appendingPathComponent(ProjectFormat.documentFileName)
            let modified = (try? document.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let thumb = NSImage(contentsOf: url.appendingPathComponent(ProjectFormat.thumbnailFileName))
            return Item(url: url, modified: modified, composition: (try? Creations.read(url))?.composition,
                        thumbnail: thumb)
        }
        // Most recently touched first: the thing you were last working on is
        // the thing you are most likely coming back for.
        items = found.sorted { $0.modified > $1.modified }
    }

    func open(_ item: Item) {
        NSDocumentController.shared.openDocument(withContentsOf: item.url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    func newProject() {
        (NSDocumentController.shared as? DocumentController)?.createAndOpenProject()
    }

    /// An open project renames through its document, so its window follows.
    func rename(_ item: Item, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name, !trimmed.contains("/") else { return }
        if let open = openDocument(at: item.url) {
            open.rename(to: trimmed)
        } else {
            let target = item.url.deletingLastPathComponent()
                .appendingPathComponent(trimmed).appendingPathExtension(ProjectFormat.fileExtension)
            guard !FileManager.default.fileExists(atPath: target.path) else { return NSSound.beep() }
            do { try FileManager.default.moveItem(at: item.url, to: target) } catch { NSApp.presentError(error) }
        }
        refresh()
    }

    func duplicate(_ item: Item) {
        let target = Creations.uniqueURL(for: "\(item.name) copy")
        do { try FileManager.default.copyItem(at: item.url, to: target) } catch { NSApp.presentError(error) }
        refresh()
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// To the Trash, where it can still be put back. An open project closes first.
    func moveToTrash(_ item: Item) {
        openDocument(at: item.url)?.close()
        do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) } catch { NSApp.presentError(error) }
        refresh()
    }

    private func openDocument(at url: URL) -> ProjectDocument? {
        NSDocumentController.shared.documents
            .first { $0.fileURL?.standardizedFileURL == url.standardizedFileURL } as? ProjectDocument
    }
}
