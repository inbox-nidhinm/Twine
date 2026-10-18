import Foundation
import MotionModel
import MotionEditing

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

    /// Runs a command as one undo step, so the person can undo it as their
    /// own, and the editor shows it at once.
    func perform(_ command: EditorCommand) throws
    /// Undoes (or redoes) the last step, giving its name, nil when there
    /// was none.
    func undo(redo: Bool) -> String?

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
public struct AgentExport: Sendable, Equatable {
    /// `mp4`, `hevc`, `prores`, `prores4444`, `gif`, `webm` or `png`, as
    /// `ExportFormat`'s raw values are mapped by the app.
    public var format: String
    /// Where to write; nil puts it beside the project's other exports.
    public var url: URL?
    public var scale: Double
    public var frameRate: Int?
    /// Part of the timeline, in seconds; nil is all of it.
    public var range: ClosedRange<Double>?
    /// A still's moment; nil is the design.
    public var time: Double?

    public init(format: String, url: URL?, scale: Double, frameRate: Int?, range: ClosedRange<Double>?, time: Double?) {
        self.format = format
        self.url = url
        self.scale = scale
        self.frameRate = frameRate
        self.range = range
        self.time = time
    }
}
