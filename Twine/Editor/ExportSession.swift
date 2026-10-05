import AppKit
import Observation
import UniformTypeIdentifiers
import MotionModel
import MotionExport

/// One window's exports: the settings the Export section edits, and the
/// export in flight, if any. Frames are drawn on a background thread from a
/// copy of the project taken when the export starts, so editing carries on
/// while it runs and cannot change what is being written.
@MainActor
@Observable
final class ExportSession {
    /// Saved whenever they change, and read by each new window, so the next
    /// export starts from the last one's choices.
    var settings: ExportSettings = ExportSession.savedSettings {
        didSet { Self.save(settings) }
    }

    /// The part of the scene a movie holds, from and to in seconds; nil is
    /// all of it. Kept for this window only, not saved, since it belongs to
    /// this scene rather than to every export.
    var range: ClosedRange<Double>?

    /// From 0 to 1 while an export runs, nil otherwise.
    private(set) var progress: Double?
    /// The file just written, offered for a few seconds to show in Finder.
    private(set) var finished: URL?
    /// The last file the export panel wrote, kept while the panel is up for
    /// Export Again and Show in Finder.
    private(set) var completed: URL?
    /// The progress the last export reached, kept after it ends so the panel's
    /// counter can leave showing where it got to.
    private(set) var lastProgress: Double = 0

    var isExporting: Bool { progress != nil }

    private var job: ExportJob?
    private var finishedToken = 0
    /// Where a failure is reported.
    private weak var window: NSWindow?

    /// Set by the window, which knows the document's name: asks for an
    /// export, in `format` or in the chosen one when nil.
    var request: (ExportFormat?) -> Void = { _ in }

    /// Asks where to save, then exports. `design` exports a still of the
    /// layout as designed rather than the frame at `time`, which is what the
    /// canvas shows in Design mode. Quality is always High, as the user
    /// asked; the setting stays in the file format for later.
    func begin(format: ExportFormat? = nil, project: Project, time: Double, design: Bool, name: String,
               media: [UUID: URL] = [:], window: NSWindow?) {
        guard !isExporting else { return }
        self.window = window
        var settings = settings
        if let format { settings.format = format }
        settings.quality = .high
        var project = project
        if design && !settings.format.isMovie { project.actions = [] }
        // The range's frames count at the rate the movie is made at.
        let exported = settings.exported(project.composition)
        let frames = settings.format.isMovie
            ? range.map { ExportTiming.frames(from: $0.lowerBound, to: $0.upperBound, in: exported) }
            : nil

        let file = "\(name).\(settings.format.fileExtension)"
        // Straight into the folder Settings names, under a free name, when
        // it is still there.
        if let folder = AppSettings.shared.exportFolder,
           (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return run(project, settings: settings, time: time, frames: frames,
                       to: Self.free(file, in: folder), media: media)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: settings.format.fileExtension) ?? .data]
        panel.nameFieldStringValue = file
        panel.canCreateDirectories = true
        let start: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            self?.run(project, settings: settings, time: time, frames: frames, to: url, media: media)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: start) } else { start(panel.runModal()) }
    }

    /// `file` in `folder`, numbered (Name 2, Name 3) past any already there.
    private static func free(_ file: String, in folder: URL) -> URL {
        let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        var n = 1
        while true {
            let url = folder.appendingPathComponent(n == 1 ? base : "\(base) \(n)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    func cancel() { job?.cancel() }

    func dismissFinished() { finished = nil }

    /// The panel closing forgets its last file.
    func forgetCompleted() {
        completed = nil
        finished = nil
    }

    private func run(_ project: Project, settings: ExportSettings, time: Double, frames: Range<Int>?, to url: URL,
                     media: [UUID: URL]) {
        let job = ExportJob()
        self.job = job
        finished = nil
        completed = nil
        progress = 0
        let ffmpeg = WebMConversion.tool("ffmpeg")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Progress crosses to the main thread at most a hundred times.
            var shown = 0
            let result = Result {
                try Exporter.export(project, settings: settings, at: time, frames: frames, to: url, media: media,
                                    ffmpeg: ffmpeg, job: job) { value in
                    let step = Int(value * 100)
                    guard step > shown else { return }
                    shown = step
                    Task { @MainActor [weak self] in
                        if self?.job === job { self?.progress = value }
                    }
                }
            }
            Task { @MainActor [weak self] in self?.end(job, result: result, url: url) }
        }
    }

    private func end(_ ended: ExportJob, result: Result<Void, Error>, url: URL) {
        guard job === ended else { return }
        job = nil
        lastProgress = progress ?? 0
        progress = nil
        switch result {
        case .success:
            lastProgress = 1
            completed = url
            if AppSettings.shared.revealsExports { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            finished = url
            finishedToken += 1
            let token = finishedToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                if self?.finishedToken == token { self?.finished = nil }
            }
        case .failure(ExportError.cancelled):
            break
        case .failure(let error):
            if let window {
                window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            } else {
                NSApp.presentError(error)
            }
        }
    }

    // MARK: Remembered settings

    private static let settingsKey = "exportSettings"

    private static var savedSettings: ExportSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(ExportSettings.self, from: data) else { return ExportSettings() }
        return settings
    }

    private static func save(_ settings: ExportSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}

extension ExportFormat {
    /// What the Format menu reads when shut, where the full name would not fit.
    var shortTitle: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .hevcAlpha: "HEVC with alpha"
        case .proRes422: "ProRes 422"
        case .proRes4444: "ProRes 4444"
        case .gif: "GIF"
        case .webm: "WebM"
        case .png: "PNG frame"
        }
    }
}
