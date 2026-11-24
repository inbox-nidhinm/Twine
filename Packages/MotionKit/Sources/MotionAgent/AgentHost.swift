import Foundation
import MotionModel
import MotionEditing
import MotionExport

/// What the tools need from the app: the open project and the editor
/// around it, and the things only the app can do (open projects, draw
/// pictures, read files, export). The tests stand in a host of their own
/// on a `ProjectStore`.
@MainActor
public protocol AgentHost: AnyObject {
    /// The open project's store, nil while the home screen shows.
    var store: ProjectStore? { get }
    /// The open project's file.
    var projectURL: URL? { get }
    /// Design shows the layout; Animate the moment at the playhead.
    var isAnimating: Bool { get set }
    var playhead: Double { get set }
    var selectedLayers: Set<UUID> { get set }
    var selectedActions: Set<UUID> { get set }
    /// What a new project starts as, from Settings.
    var newComposition: Composition { get }
    /// The length and easing a new action takes, from Settings.
    var newAction: (duration: Double, easing: Easing) { get }

    /// Runs a command as one undo step, so the person can undo it as their
    /// own, and the editor shows it at once.
    func perform(_ command: EditorCommand) throws
    /// Undoes (or redoes) the last step, giving its name, nil when there
    /// was none. Throws when it cannot be done just now (the person is in
    /// the middle of a drag).
    func undo(redo: Bool) throws -> String?

    /// The projects in the projects folder.
    func projects() -> [AgentProject]
    func openProject(at url: URL) async throws
    /// Makes a project in the projects folder and opens it.
    func newProject(named name: String?, project: Project) async throws

    /// The project drawn as a PNG at most `maxSide` pixels a side: the
    /// design when `time` is nil, else that moment.
    func render(at time: Double?, maxSide: Int) async throws -> Data
    /// Brings files in as new layers (pictures, videos, sounds, SVGs),
    /// centred on `center` or in the middle, returning the new layers.
    func importFiles(_ urls: [URL], center: Vec2?) async throws -> [UUID]
    /// Fills a template's slots from `slot` on with pictures or videos.
    func fillTemplate(_ frameID: UUID, from slot: Int, with urls: [URL]) async throws
    /// Writes the project to a file, returning where it went.
    func export(_ request: AgentExport) async throws -> URL
}

public struct AgentProject: Sendable, Equatable {
    public let name: String
    public let url: URL
    /// The folder inside the projects folder, nil when loose.
    public let folder: String?
    public let modified: Date

    public init(name: String, url: URL, folder: String?, modified: Date) {
        self.name = name
        self.url = url
        self.folder = folder
        self.modified = modified
    }
}

/// An export as the tool asks for it.
///
/// `destination` turns the path asked for into the file to write: an AI app
/// told "export it to my Renders folder" gives the folder, and writing a file
/// in that folder's place would delete it and everything in it.
public struct AgentExport: Sendable, Equatable {
    public var format: ExportFormat
    /// Where to write; nil puts it beside the project's other exports.
    public var url: URL?
    public var scale: Double
    public var frameRate: Int?
    /// Part of the timeline, in seconds; nil is all of it.
    public var range: ClosedRange<Double>?
    /// A still's moment; nil is the design.
    public var time: Double?

    /// The file an export asked for at `url` is written to. A folder takes
    /// the export inside it, as `name` with the format's ending, numbered
    /// past any file already there; a project or an app is refused, being
    /// folders that are not for putting files in. A file keeps its name,
    /// given the format's ending when it has another, so an export can
    /// replace an earlier export but never a file of some other kind.
    public static func destination(for url: URL, ending: String, name: String) throws -> URL {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
            return url.pathExtension.lowercased() == ending.lowercased() ? url : url.appendingPathExtension(ending)
        }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        if isPackage || ["twine", "app"].contains(url.pathExtension.lowercased()) {
            throw AgentError("\(url.lastPathComponent) is not a folder to export into. Give a file path, or an ordinary folder.")
        }
        return free("\(name).\(ending)", in: url)
    }

    /// `file` in `folder`, numbered past any already there.
    public static func free(_ file: String, in folder: URL) -> URL {
        let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        var n = 1
        while true {
            let url = folder.appendingPathComponent(n == 1 ? base : "\(base) \(n)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    public init(format: ExportFormat, url: URL?, scale: Double, frameRate: Int?, range: ClosedRange<Double>?, time: Double?) {
        self.format = format
        self.url = url
        self.scale = scale
        self.frameRate = frameRate
        self.range = range
        self.time = time
    }
}
