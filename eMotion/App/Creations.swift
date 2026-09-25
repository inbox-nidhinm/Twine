import Foundation
import MotionModel

/// `~/Documents/eMotion Creations`, where every project lives.
///
/// A new project is written here the moment it is made, with a name and no
/// dialog, and saves itself from then on. Nothing ever sits unsaved, and
/// closing a window never asks a question.
enum Creations {
    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("eMotion Creations", isDirectory: true)
    }

    static func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Writes a fresh project package and returns where it went.
    static func makeProject(named base: String = "Untitled") throws -> URL {
        try ensureFolder()
        let url = uniqueURL(for: base)
        try write(Project(), to: url)
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
        let data = try Data(contentsOf: url.appendingPathComponent(ProjectFormat.documentFileName))
        return try ProjectFormat.decode(data)
    }
}
