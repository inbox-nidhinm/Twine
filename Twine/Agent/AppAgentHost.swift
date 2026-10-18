import AppKit
import UniformTypeIdentifiers
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering
import MotionExport
import MotionAgent

/// The AI tools' way into the app: whatever project the one window shows,
/// through the same controller the canvas and the panels use, so a change
/// an AI makes is drawn, saved and undone as the person's own are.
@MainActor
final class AppAgentHost: AgentHost {
    private var editorWindow: EditorWindowController? {
        MainWindow.window.windowController as? EditorWindowController
    }

    private var controller: EditorController? {
        guard let controller = editorWindow?.controller, !controller.isClosed, controller.document != nil else { return nil }
        return controller
    }

    var store: ProjectStore? { controller?.store }
    var projectURL: URL? { controller?.document?.fileURL }

    var isAnimating: Bool {
        get { controller?.editor.mode == .animate }
        set { controller?.setMode(newValue ? .animate : .design) }
    }

    var playhead: Double {
        get { controller?.editor.time ?? 0 }
        set { controller?.seek(to: newValue) }
    }

    var selectedLayers: Set<UUID> {
        get { controller?.editor.selection ?? [] }
        set { controller?.select(Array(newValue)) }
    }

    var selectedActions: Set<UUID> {
        get { controller?.editor.selectedActions ?? [] }
        set {
            controller?.editor.selectedActions = newValue
            if !newValue.isEmpty { controller?.editor.focus = .timeline }
        }
    }

    var newComposition: Composition { AppSettings.shared.newProject }
    var newAction: (duration: Double, easing: Easing) {
        (AppSettings.shared.actionDuration, AppSettings.shared.newActionEasing)
    }

    func perform(_ command: EditorCommand) throws {
        guard let controller else { throw AgentError("No project is open in Twine") }
        try controller.store.perform(command)
        Self.closeUndoGroup()
    }

    /// A change that arrives outside a click or a key press leaves the
    /// undo manager's group for this turn of the event loop open until an
    /// event comes, and until it closes the document does not count as
    /// edited, so nothing saves. An event of the app's own closes it.
    private static func closeUndoGroup() {
        guard let nudge = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) else { return }
        NSApp.postEvent(nudge, atStart: false)
    }

    func undo(redo: Bool) -> String? {
        guard let undo = controller?.store.undoManager else { return nil }
        if redo {
            guard undo.canRedo else { return nil }
            let name = undo.redoActionName
            undo.redo()
            Self.closeUndoGroup()
            return name
        }
        guard undo.canUndo else { return nil }
        let name = undo.undoActionName
        undo.undo()
        Self.closeUndoGroup()
        return name
    }

    // MARK: Projects

    func projects() -> [AgentProject] {
        let library = HomeWindowController.shared.library
        library.refresh()
        return library.items.map {
            AgentProject(name: $0.name, url: $0.url, folder: $0.folder?.lastPathComponent, modified: $0.modified)
        }
    }

    func openProject(at url: URL) async throws {
        // Compared with links followed, as /tmp is /private/tmp.
        func same(_ a: URL?) -> Bool { a?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
        if same(projectURL) { return }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
        // The editor is built a turn after the document opens.
        for _ in 0..<50 where !same(controller?.document?.fileURL) {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard controller != nil else { throw AgentError("Twine opened the project but its editor did not appear") }
    }

    func newProject(named name: String?, project: Project) async throws {
        let base = name?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        let url = try Creations.makeProject(named: base?.isEmpty == false ? base! : "Untitled", project: project)
        try await openProject(at: url)
    }

    // MARK: Pictures

    /// Kept for the open project's videos, so drawing a frame never moves
    /// the canvas's own decoders.
    private var videos: MediaLibrary?
    private var videosFor: URL?

    func render(at time: Double?, maxSide: Int) async throws -> Data {
        guard let controller, let document = controller.document else { throw AgentError("No project is open in Twine") }
        let project = controller.project
        let size = project.composition.size
        let scale = Double(maxSide) / max(size.width, size.height)
        let width = max(Int((size.width * scale).rounded()), 1), height = max(Int((size.height * scale).rounded()), 1)
        guard let renderer = OffscreenRenderer(pixelWidth: width, pixelHeight: height) else {
            throw AgentError("Twine could not draw (no Metal device)")
        }
        if videosFor != document.fileURL || videos == nil {
            videos = MediaLibrary { [weak document] id in TemplateSampleFiles.url(for: id) ?? document?.mediaURL(for: id) }
            videosFor = document.fileURL
        }
        renderer.media = AgentMedia(pictures: controller.media, videos: videos!)
        let scene = time.map { evaluate(project, at: $0) } ?? evaluateDesign(project)
        guard let image = renderer.image(of: scene) else { throw AgentError("Twine could not draw that frame") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AgentError("Twine could not make the picture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AgentError("Twine could not make the picture") }
        return data as Data
    }

    // MARK: Files

    func importFiles(_ urls: [URL], center: Vec2?) async throws -> [UUID] {
        guard let controller else { throw AgentError("No project is open in Twine") }
        var added: [UUID] = []
        let drawings = urls.filter { $0.pathExtension.lowercased() == "svg" }
        for (i, url) in drawings.enumerated() {
            let at = center.map { Vec2($0.x + Double(i) * 20, $0.y + Double(i) * 20) }
            if let id = await controller.importSVG(url, at: at)?.value { added.append(id) }
        }
        let files = urls.filter { $0.pathExtension.lowercased() != "svg" }
        if !files.isEmpty { added += await controller.importFiles(files, at: center) }
        guard !added.isEmpty else { throw AgentError("Twine could not bring those files in (pictures, videos, sounds and SVGs open)") }
        return added
    }

    func fillTemplate(_ frameID: UUID, from slot: Int, with urls: [URL]) async throws {
        guard let controller else { throw AgentError("No project is open in Twine") }
        await controller.setTemplateMedia(frameID, from: slot, urls: urls).value
    }

    func export(_ request: AgentExport) async throws -> URL {
        guard let controller, let document = controller.document else { throw AgentError("No project is open in Twine") }
        let ffmpeg = WebMConversion.tool("ffmpeg")
        if request.format.needsFFmpeg, ffmpeg == nil { throw AgentError("WebM needs ffmpeg installed on this Mac") }
        var settings = ExportSettings(format: request.format, scale: request.scale, quality: .high, includesAudio: true,
                                      frameRate: request.frameRate.map { FrameRate(frames: $0) })
        if !settings.format.isMovie { settings.frameRate = nil }
        var project = controller.project
        if !request.format.isMovie, request.time == nil { project.actions = [] }
        let exported = settings.exported(project.composition)
        let frames = request.format.isMovie
            ? request.range.map { ExportTiming.frames(from: $0.lowerBound, to: $0.upperBound, in: exported) } : nil

        let name = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Twine"
        let url = request.url ?? Self.free("\(name).\(request.format.fileExtension)",
                                           in: AppSettings.shared.exportFolder
                                               ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var media = document.mediaURLs
        for id in TemplateSampleFiles.ids { media[id] = TemplateSampleFiles.url(for: id) }
        let time = request.time ?? 0
        let work = controller.editor.beginWork("Exporting \(url.lastPathComponent)", after: 0.4)
        defer { controller.editor.finishWork(work, done: "Exported \(url.lastPathComponent)") }
        try await withCheckedThrowingContinuation { [project, settings, media] (done: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(with: Result {
                    try Exporter.export(project, settings: settings, at: time, frames: frames, to: url, media: media, ffmpeg: ffmpeg)
                })
            }
        }
        return url
    }

    /// `file` in `folder`, numbered past any already there.
    private static func free(_ file: String, in folder: URL) -> URL {
        let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        var n = 1
        while true {
            let url = folder.appendingPathComponent(n == 1 ? base : "\(base) \(n)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }
}

/// The editor's pictures with videos of the tools' own.
private final class AgentMedia: MediaProvider {
    let pictures: MediaLibrary
    let videos: MediaLibrary

    init(pictures: MediaLibrary, videos: MediaLibrary) {
        self.pictures = pictures
        self.videos = videos
    }

    func image(_ mediaID: UUID) -> CGImage? { pictures.image(mediaID) }
    func videoFrame(_ mediaID: UUID, at time: Double) -> CGImage? { videos.videoFrame(mediaID, at: time) }
}
