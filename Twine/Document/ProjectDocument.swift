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
        // in the timeline, and an older Typewriter types rather than fades;
        // the file changes only when next saved.
        let project = Presets.withTypewriters(MediaPlays.withPlayBars(try ProjectFormat.decode(data)))
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
            let pictures = editorController?.media ?? MediaLibrary(locate: { [mediaURLs] in mediaURLs[$0] })
            return (try ProjectFormat.encode(store.project), Thumbnail.png(of: store.project, pictures: pictures,
                                                                             media: mediaURLs))
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
        // Files imported this session are cloned into the written package
        // once it is written (`write(to:ofType:for:originalContentsURL:)`),
        // rather than carried in the wrapper, which copied every byte on the
        // main thread: three seconds of frozen app for an 844 MB video. One
        // cloned by an earlier save is taken into the wrapper from the saved
        // package, as a file read from there is, so it is linked across as
        // the rest of the media is, never copied again.
        let saved = MainActor.assumeIsolated { () -> [String] in
            (store?.project.media ?? []).map(\.fileName)
        }
        if let folder = root.fileWrappers?[ProjectFormat.mediaFolderName],
           let savedFolder = fileURL?.appendingPathComponent(ProjectFormat.mediaFolderName) {
            for name in saved where folder.fileWrappers?[name] == nil {
                let file = savedFolder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: file.path),
                      let wrapper = try? FileWrapper(url: file, options: []) else { continue }
                wrapper.preferredFilename = name
                folder.addFileWrapper(wrapper)
            }
        }
        package = root
        return root
    }

    /// Writes the package, then clones into it every file the project uses
    /// that it does not yet hold: those imported since it was last saved,
    /// from their staged copies, and any the wrapper did not carry, from the
    /// package as it was. On the Mac's own drive a clone takes no time and
    /// no space. A file found in neither place is left out, with a notice.
    nonisolated override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                                    originalContentsURL: URL?) throws {
        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: originalContentsURL)
        let wanted = MainActor.assumeIsolated { () -> [(name: String, staged: URL?, shown: String)] in
            (store?.project.media ?? []).map { ($0.fileName, stagedMedia[$0.fileName], $0.originalName) }
        }
        let fm = FileManager.default
        let folder = url.appendingPathComponent(ProjectFormat.mediaFolderName)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let before = originalContentsURL?.appendingPathComponent(ProjectFormat.mediaFolderName)
        var lost: [String] = []
        for (name, staged, shown) in wanted {
            let target = folder.appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else { continue }
            let sources = [staged, before?.appendingPathComponent(name)].compactMap { $0 }
            guard let source = sources.first(where: { fm.fileExists(atPath: $0.path) }) else {
                if staged != nil { lost.append(shown) }
                continue
            }
            try fm.copyItem(at: source, to: target)
        }
        if !lost.isEmpty {
            MainActor.assumeIsolated {
                editorController?.editor.showNotice("Couldn't keep \(lost.joined(separator: ", ")) in the project.")
            }
        }
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
        guard !isClosed else { throw CancellationError() }
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
        guard !isClosed else { throw CancellationError() }
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
        guard !isClosed else { return }
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Undo and redo count as changes too, so a delete undone or
                // redone lets go of what it no longer needs here.
                self.editorController?.releaseUnusedMedia()
                guard self.isDocumentEdited else { return }
                self.autosave(withImplicitCancellability: false) { _ in }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        saveSoon = timer
    }

    /// Set once closed, when nothing may be staged or saved any more.
    private(set) var isClosed = false

    override func close() {
        saveSoon?.invalidate()
        isClosed = true
        super.close()
        // The copies made aside are in the package now, or were never
        // wanted; left in the temporary folder, they piled up by the
        // gigabyte, one folder a session.
        if !stagedMedia.isEmpty { try? FileManager.default.removeItem(at: stagingFolder) }
    }

    /// The editor showing this document, whose pictures the thumbnail
    /// borrows and whose unused media is let go.
    private var editorController: EditorController? {
        windowControllers.lazy.compactMap { ($0 as? EditorWindowController)?.controller }.first
    }

    /// Saves anything not yet saved, then closes: for when the window turns
    /// to something else rather than closing, which would have saved itself.
    ///
    /// A save that fails keeps the project open and asks, on the window,
    /// whether to try again or close without saving: closing anyway lost
    /// the changes without a word.
    func closeAfterSaving(then: @escaping () -> Void) {
        guard hasUnautosavedChanges || isDocumentEdited else {
            close()
            return then()
        }
        autosave(withImplicitCancellability: false) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return then() }
                guard let error else {
                    self.close()
                    return then()
                }
                self.askAfterFailedSave(error, then: then)
            }
        }
    }

    private func askAfterFailedSave(_ error: Error, then: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(name)\u{201D} couldn't be saved."
        let nsError = error as NSError
        alert.informativeText = [nsError.localizedDescription, nsError.localizedFailureReason]
            .compactMap { $0 }.joined(separator: " ")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Close Without Saving")
        alert.beginSheetModal(for: MainWindow.window) { [weak self] response in
            guard let self else { return then() }
            if response == .alertFirstButtonReturn {
                self.closeAfterSaving(then: then)
            } else {
                self.close()
                then()
            }
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
    /// Video decoders of the thumbnail's own: sharing the canvas's would send
    /// its decoder back to the start on every save, and reading from there
    /// again costs the next frame on the canvas a noticeable pause.
    static let videos = MediaLibrary(locate: { located[$0] })
    private static var located: [UUID: URL] = [:]

    /// Pictures come from `pictures` (the editor's, already read, so a save
    /// never reads them all again), videos from the thumbnail's own.
    static func png(of project: Project, pictures: MediaLibrary, media: [UUID: URL] = [:]) -> Data? {
        let size = project.composition.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = longSide / max(size.width, size.height)
        let width = max(Int((size.width * scale).rounded()), 1), height = max(Int((size.height * scale).rounded()), 1)
        if renderer?.pixelWidth != width || renderer?.pixelHeight != height {
            renderer = OffscreenRenderer(pixelWidth: width, pixelHeight: height)
        }
        located = media
        // Only this project's videos stay open: kept across projects, the
        // readers of every video thumbnailed in a session piled up.
        videos.keep(only: Set(project.media.map(\.id)))
        renderer?.media = ThumbnailMedia(pictures: pictures, videos: videos)
        defer { renderer?.media = nil }
        guard let image = renderer?.image(of: evaluate(project, at: 0)) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// The editor's pictures with the thumbnail's own video decoders.
private final class ThumbnailMedia: MediaProvider {
    let pictures: MediaLibrary
    let videos: MediaLibrary

    init(pictures: MediaLibrary, videos: MediaLibrary) {
        self.pictures = pictures
        self.videos = videos
    }

    func image(_ mediaID: UUID) -> CGImage? { pictures.image(mediaID) }
    func videoFrame(_ mediaID: UUID, at time: Double) -> CGImage? { videos.videoFrame(mediaID, at: time) }
}
