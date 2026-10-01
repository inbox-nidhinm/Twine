import AppKit
import Observation
import MotionModel

/// Everything in `Twine Creations`, for the home screen: the projects,
/// loose or in folders, and the folders. A folder is a real one in the
/// Finder, one level down; anything the Finder does to it shows up here.
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
        /// The folder it is in, nil when loose.
        let folder: URL?

        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    struct Folder: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    private(set) var items: [Item] = []
    private(set) var folders: [Folder] = []
    /// The folder the shelf shows, nil for All Projects.
    var selectedFolder: URL?
    var showVersionHistory = false

    /// What the shelf shows: everything, or one folder's projects.
    var shownItems: [Item] {
        guard let selectedFolder else { return items }
        return items.filter { $0.folder == selectedFolder }
    }

    func count(in folder: Folder) -> Int { items.filter { $0.folder == folder.url }.count }

    /// What each project's files held when last read, by when it was saved.
    @ObservationIgnored private var read: [URL: (modified: Date, composition: Composition?, thumbnail: NSImage?)] = [:]

    func refresh() {
        let fm = FileManager.default
        try? Creations.ensureFolder()
        func contents(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                          options: [.skipsHiddenFiles])) ?? []).map(\.standardizedFileURL)
        }
        func isProject(_ url: URL) -> Bool { ProjectFormat.readableExtensions.contains(url.pathExtension) }
        func isFolder(_ url: URL) -> Bool {
            !isProject(url) && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        let top = contents(Creations.folder)
        let found = top.filter(isFolder).map(Folder.init(url:))
        folders = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // A project is a folder, so it is picked out by its extension rather
        // than by whether it is a directory.
        let projects = top.filter(isProject).map { ($0, nil as URL?) }
            + found.flatMap { folder in contents(folder.url).filter(isProject).map { ($0, folder.url as URL?) } }
        let made = projects.map { url, folder in
            func modification(_ name: String) -> Date {
                (try? url.appendingPathComponent(name).resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
            }
            // The thumbnail counts too: a large project's is written on its
            // own as it closes, after its last save.
            let modified = max(modification(ProjectFormat.documentFileName), modification(ProjectFormat.thumbnailFileName))
            // Read again only when saved since: the whole document is read
            // for its size, which with many projects stuttered each time
            // the window came to the front.
            if let known = read[url], known.modified == modified {
                return Item(url: url, modified: modified, composition: known.composition, thumbnail: known.thumbnail, folder: folder)
            }
            let thumb = NSImage(contentsOf: url.appendingPathComponent(ProjectFormat.thumbnailFileName))
            let composition = (try? Creations.read(url))?.composition
            read[url] = (modified, composition, thumb)
            return Item(url: url, modified: modified, composition: composition, thumbnail: thumb, folder: folder)
        }
        read = read.filter { url, _ in projects.contains { $0.0 == url } }
        // Most recently touched first: the thing you were last working on is
        // the thing you are most likely coming back for.
        items = made.sorted { $0.modified > $1.modified }
        if let selectedFolder, !folders.contains(where: { $0.url == selectedFolder }) { self.selectedFolder = nil }
    }

    // MARK: Folders

    /// A new folder called `name`, returned so the sidebar can show it. A
    /// name already taken, or one that would read as a project, beeps.
    @discardableResult
    func newFolder(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"),
              !ProjectFormat.readableExtensions.contains((trimmed as NSString).pathExtension) else { NSSound.beep(); return nil }
        let url = Creations.folder.appendingPathComponent(trimmed, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return nil }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch {
            NSApp.presentError(error)
            return nil
        }
        refresh()
        return url.standardizedFileURL
    }

    func rename(_ folder: Folder, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name, !trimmed.contains("/"),
              !ProjectFormat.readableExtensions.contains((trimmed as NSString).pathExtension) else { return }
        let target = folder.url.deletingLastPathComponent().appendingPathComponent(trimmed, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else { return NSSound.beep() }
        do {
            try FileManager.default.moveItem(at: folder.url, to: target)
        } catch {
            NSApp.presentError(error)
            return
        }
        if selectedFolder == folder.url { selectedFolder = target.standardizedFileURL }
        refresh()
    }

    func reveal(_ folder: Folder) {
        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
    }

    /// The folder and the projects in it go to the Trash, where they can
    /// still be put back.
    func moveToTrash(_ folder: Folder) {
        do { try FileManager.default.trashItem(at: folder.url, resultingItemURL: nil) } catch { NSApp.presentError(error) }
        refresh()
    }

    /// Moves a project into `folder`, or out to the top when nil. A name
    /// already taken there gets a number.
    func move(_ url: URL, to folder: URL?) {
        let destination = folder ?? Creations.folder.standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL != destination.standardizedFileURL else { return }
        let base = url.deletingPathExtension().lastPathComponent
        var target = destination.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent("\(base) \(n)").appendingPathExtension(url.pathExtension)
            n += 1
        }
        if let open = openDocument(at: url) {
            open.move(to: target) { error in if let error { NSApp.presentError(error) } }
        } else {
            do { try FileManager.default.moveItem(at: url, to: target) } catch { NSApp.presentError(error) }
        }
        refresh()
    }

    /// Whether a dragged URL is a project this library can move.
    func isProject(_ url: URL) -> Bool {
        ProjectFormat.readableExtensions.contains(url.pathExtension)
            && items.contains { $0.url == url.standardizedFileURL }
    }

    // MARK: Projects

    func open(_ item: Item) {
        NSDocumentController.shared.openDocument(withContentsOf: item.url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    /// Into the folder showing, if one is.
    func newProject() {
        (NSDocumentController.shared as? DocumentController)?.createAndOpenProject(in: selectedFolder)
    }

    /// An open project renames through its document, so its window follows.
    func rename(_ item: Item, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name, !trimmed.contains("/") else { return }
        if let open = openDocument(at: item.url) {
            open.rename(to: trimmed)
        } else {
            let target = item.url.deletingLastPathComponent()
                .appendingPathComponent(trimmed).appendingPathExtension(item.url.pathExtension)
            guard !FileManager.default.fileExists(atPath: target.path) else { return NSSound.beep() }
            do { try FileManager.default.moveItem(at: item.url, to: target) } catch { NSApp.presentError(error) }
        }
        refresh()
    }

    /// Beside the original, in its folder if it has one.
    func duplicate(_ item: Item) {
        let target = Creations.uniqueURL(for: "\(item.name) copy", in: item.folder ?? Creations.folder)
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
