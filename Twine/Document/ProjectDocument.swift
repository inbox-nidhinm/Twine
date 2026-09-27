import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering
import ImageIO
import UniformTypeIdentifiers

/// One open project (a `.twine` package).
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
        // A sound or video that lost its Play bar gets one back, so it shows
        // in the timeline; the file changes only when next saved.
        let project = MediaPlays.withPlayBars(try ProjectFormat.decode(data))
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
        let (json, thumbnail) = try MainActor.assumeIsolated { () throws -> (Data, Data?) in
            guard let store else { throw ProjectFileError.missingDocument }
            return (try ProjectFormat.encode(store.project), Thumbnail.png(of: store.project, media: mediaURLs))
        }
        let root = package ?? FileWrapper(directoryWithFileWrappers: [:])

        if let thumbnail {
            if let old = root.fileWrappers?[ProjectFormat.thumbnailFileName] { root.removeFileWrapper(old) }
            let file = FileWrapper(regularFileWithContents: thumbnail)
            file.preferredFilename = ProjectFormat.thumbnailFileName
            root.addFileWrapper(file)
        }

        if let old = root.fileWrappers?[ProjectFormat.documentFileName] { root.removeFileWrapper(old) }
        let document = FileWrapper(regularFileWithContents: json)
        document.preferredFilename = ProjectFormat.documentFileName
        root.addFileWrapper(document)

        if root.fileWrappers?[ProjectFormat.mediaFolderName] == nil {
            let media = FileWrapper(directoryWithFileWrappers: [:])
            media.preferredFilename = ProjectFormat.mediaFolderName
            root.addFileWrapper(media)
        }
        // Files imported since the last save join the package now. Each is
        // read from its staged copy as it is written, never held in memory.
        let staged = MainActor.assumeIsolated { () -> [(String, URL)] in
            (store?.project.media ?? []).compactMap { asset in stagedMedia[asset.fileName].map { (asset.fileName, $0) } }
        }
        if let folder = root.fileWrappers?[ProjectFormat.mediaFolderName] {
            for (name, url) in staged where folder.fileWrappers?[name] == nil {
                if let file = try? FileWrapper(url: url, options: []) {
                    file.preferredFilename = name
                    folder.addFileWrapper(file)
                }
            }
        }
        package = root
        return root
    }

    // MARK: Media

    /// Files imported this session, by their name in the package, copied
    /// aside the moment they are imported so the original can move or go.
    private var stagedMedia: [String: URL] = [:]
    private lazy var stagingFolder: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Twine-media", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    /// Where to read an imported file: its staged copy if it came in this
    /// session, otherwise its place in the saved package. Nil if it is in
    /// neither, and the layer shows grey.
    func mediaURL(for id: UUID) -> URL? {
        guard let asset = store?.project.media.first(where: { $0.id == id }) else { return nil }
        if let staged = stagedMedia[asset.fileName] { return staged }
        guard let fileURL else { return nil }
        let saved = fileURL.appendingPathComponent(ProjectFormat.mediaFolderName).appendingPathComponent(asset.fileName)
        return FileManager.default.fileExists(atPath: saved.path) ? saved : nil
    }

    /// Every file the project uses, for an export to read on its own thread.
    var mediaURLs: [UUID: URL] {
        Dictionary((store?.project.media ?? []).compactMap { a in mediaURL(for: a.id).map { (a.id, $0) } },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Copies `source` aside under `fileName`, on a worker thread.
    func stage(_ source: URL, as fileName: String) async throws {
        let folder = stagingFolder
        let target = folder.appendingPathComponent(fileName)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        }.value
        stagedMedia[fileName] = target
    }

    /// Writes `data` aside under `fileName`, as `stage` copies a file: for
    /// pictures that come inside another file, such as an SVG's.
    func stage(_ data: Data, as fileName: String) async throws {
        let folder = stagingFolder
        let target = folder.appendingPathComponent(fileName)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }.value
        stagedMedia[fileName] = target
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

    /// Saves anything not yet saved, then closes: for when the window turns
    /// to something else rather than closing, which would have saved itself.
    func closeAfterSaving(then: @escaping () -> Void) {
        guard hasUnautosavedChanges || isDocumentEdited else {
            close()
            return then()
        }
        autosave(withImplicitCancellability: false) { [weak self] _ in
            self?.close()
            then()
        }
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
            .appendingPathComponent(trimmed).appendingPathExtension(url.pathExtension)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            NSSound.beep()
            return
        }
        move(to: target) { error in
            if let error { NSApp.presentError(error) }
        }
    }
}

/// The home screen's picture of a project: its first frame, through the same
/// renderer as the canvas and export.
enum Thumbnail {
    /// The longer side, in pixels. Cards are 148pt wide, so this is sharp at 2x.
    static let longSide = 320.0

    private static var renderer: OffscreenRenderer?

    static func png(of project: Project, media: [UUID: URL] = [:]) -> Data? {
        let size = project.composition.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = longSide / max(size.width, size.height)
        let width = max(Int((size.width * scale).rounded()), 1), height = max(Int((size.height * scale).rounded()), 1)
        if renderer?.pixelWidth != width || renderer?.pixelHeight != height {
            renderer = OffscreenRenderer(pixelWidth: width, pixelHeight: height)
        }
        renderer?.media = MediaLibrary(locate: { media[$0] })
        guard let image = renderer?.image(of: evaluate(project, at: 0)) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
