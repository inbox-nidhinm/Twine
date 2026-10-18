import AppKit
import MotionModel

/// The projects folder (`~/Documents/Twine Creations` unless another was
/// chosen), where every project lives, loose or in a folder of its own one
/// level down.
///
/// A new project is written here the moment it is made, with a name and no
/// dialog, and saves itself from then on. Nothing ever sits unsaved, and
/// closing a window never asks a question.
enum Creations {
    /// Where projects are kept and the home screen reads: the folder chosen
    /// in the onboarding, or `~/Documents/Twine Creations`.
    static var folder: URL {
        // The test copy is pointed somewhere else, so it never touches the
        // projects in use.
        if let override = ProcessInfo.processInfo.environment["TWINE_CREATIONS"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultFolder
    }

    static var defaultFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Twine Creations", isDirectory: true)
    }

    private static let folderKey = "creationsFolder"

    /// Kept as a plain path: the app is not sandboxed, so a path is all it
    /// needs, and it reads plainly in `defaults`. Projects already made stay
    /// where they are.
    static func setFolder(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: folderKey)
        try? ensureFolder()
    }

    /// Asks for a folder on the window, and hands back whether one was picked.
    static func chooseFolder(for window: NSWindow?, then done: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Where should Twine keep your projects?"
        panel.directoryURL = folder.deletingLastPathComponent()
        let finish = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return done(false) }
            setFolder(url)
            done(true)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    static func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Writes a fresh project package, at the size, rate, length and
    /// background Settings give new projects, and returns where it went.
    @MainActor
    static func makeProject(named base: String = "Untitled", in directory: URL? = nil, project: Project? = nil) throws -> URL {
        try ensureFolder()
        let url = uniqueURL(for: base, in: directory ?? folder)
        try write(project ?? Project(composition: AppSettings.shared.newProject), to: url)
        return url
    }

    /// The first of `Untitled`, `Untitled 2`, `Untitled 3` that is free.
    static func uniqueURL(for base: String, in directory: URL = folder) -> URL {
        let fm = FileManager.default
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let url = directory.appendingPathComponent(name).appendingPathExtension(ProjectFormat.fileExtension)
            if !fm.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// The package layout, written directly. Used for projects that are not
    /// open; an open project saves through its document.
    static func write(_ project: Project, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent(ProjectFormat.mediaFolderName, isDirectory: true),
                               withIntermediateDirectories: true)
        try ProjectFormat.encode(project).write(to: url.appendingPathComponent(ProjectFormat.documentFileName),
                                                options: .atomic)
    }

    static func read(_ url: URL) throws -> Project {
        // Only an ordinary file is read: a link could lead anywhere, and
        // a pipe would hold the home screen waiting.
        guard let file = ProjectDocument.packageFile(ProjectFormat.documentFileName, in: url)
        else { throw ProjectFileError.missingDocument }
        return try ProjectFormat.decode(try Data(contentsOf: file))
    }
}
