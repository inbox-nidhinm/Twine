import AppKit
import MotionModel
import MotionEditing

/// One open `.emotion` project.
///
/// Saving is autosave in place: macOS writes the package back a moment after
/// each change and again on close and quit, keeps older versions for File >
/// Revert To, and never asks before closing. The undo manager is the
/// document's own, which is what drives that: every command the store records
/// counts as a change to save.
@objc(ProjectDocument)
final class ProjectDocument: NSDocument {
    /// Nil only between `init` and the first read.
    private(set) var store: ProjectStore?
    let editor = EditorModel()

    /// The package as it was read. Kept and updated in place on save rather
    /// than rebuilt, so the media inside it, which can run to gigabytes, is
    /// carried across saves untouched instead of being read and rewritten.
    ///
    /// Outside the main actor because `FileWrapper` cannot cross into it. Only
    /// `read` and `fileWrapper(ofType:)` touch it, and both run on the main
    /// thread, which the overrides below make sure of.
    nonisolated(unsafe) private var package: FileWrapper?

    nonisolated override class var autosavesInPlace: Bool { true }

    /// Reads and saves stay on the main thread, where the store lives. That is
    /// what the two overrides below rely on when they step onto the main actor.
    nonisolated override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    nonisolated override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                                     for saveOperation: NSDocument.SaveOperationType) -> Bool { false }

    nonisolated override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard fileWrapper.isDirectory,
              let data = fileWrapper.fileWrappers?[ProjectFormat.documentFileName]?.regularFileContents
        else { throw ProjectFileError.missingDocument }
        let project = try ProjectFormat.decode(data)
        package = fileWrapper
        MainActor.assumeIsolated {
            if let store {
                store.load(project)
            } else if let undo = undoManager {
                store = ProjectStore(project: project, undoManager: undo)
            }
        }
    }

    nonisolated override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let json = try MainActor.assumeIsolated { () throws -> Data in
            guard let store else { throw ProjectFileError.missingDocument }
            return try ProjectFormat.encode(store.project)
        }
        let root = package ?? FileWrapper(directoryWithFileWrappers: [:])

        if let old = root.fileWrappers?[ProjectFormat.documentFileName] { root.removeFileWrapper(old) }
        let document = FileWrapper(regularFileWithContents: json)
        document.preferredFilename = ProjectFormat.documentFileName
        root.addFileWrapper(document)

        if root.fileWrappers?[ProjectFormat.mediaFolderName] == nil {
            let media = FileWrapper(directoryWithFileWrappers: [:])
            media.preferredFilename = ProjectFormat.mediaFolderName
            root.addFileWrapper(media)
        }
        package = root
        return root
    }

    // MARK: Saving soon

    /// macOS autosaves in its own time, which can be fifteen seconds or more
    /// after a change. That is fifteen seconds of work a crash would take, so
    /// each change also schedules a save for a second after the changes stop.
    /// A drag writes once when it ends rather than on every step.
    private var saveSoon: Timer?

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        scheduleSaveSoon()
    }

    private func scheduleSaveSoon() {
        saveSoon?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isDocumentEdited else { return }
                self.autosave(withImplicitCancellability: false) { _ in }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        saveSoon = timer
    }

    override func close() {
        saveSoon?.invalidate()
        super.close()
    }

    override func makeWindowControllers() {
        guard let store else { return }
        addWindowController(EditorWindowController(document: self, store: store))
    }

    /// The project's name, as the home screen and the layers panel show it.
    var name: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? displayName
    }

    /// Renames the package on disk. The document follows its file, so the
    /// window, the recent list and autosave all carry on under the new name.
    func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = fileURL, !trimmed.isEmpty, trimmed != name, !trimmed.contains("/") else { return }
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(trimmed).appendingPathExtension(ProjectFormat.fileExtension)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            NSSound.beep()
            return
        }
        move(to: target) { error in
            if let error { NSApp.presentError(error) }
        }
    }
}
