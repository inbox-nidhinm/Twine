import Foundation
import Observation
import MotionModel

/// What the user has chosen on the Settings page, kept in defaults for every
/// window and every launch. Settings is on the home screen, and the app has
/// one window, so nothing open needs telling when one changes: an editor
/// reads them as it works. The projects folder is `Creations`'s own.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    /// What File > New and New Project start with.
    var newProject: Composition {
        didSet { save(newProject, as: Keys.newProject) }
    }
    /// How far an arrow key moves the selection on the canvas, and with Shift.
    var nudge: Double { didSet { defaults.set(nudge, forKey: Keys.nudge) } }
    var shiftNudge: Double { didSet { defaults.set(shiftNudge, forKey: Keys.shiftNudge) } }
    /// The easing and length a new action takes. Presets keep their own.
    var actionEasing: EasingPreset {
        didSet { defaults.set(actionEasing.rawValue, forKey: Keys.actionEasing) }
    }
    var actionDuration: Double { didSet { defaults.set(actionDuration, forKey: Keys.actionDuration) } }
    /// Whether times read as frame numbers rather than seconds; the
    /// timeline's menu changes it too.
    var showsFrames: Bool { didSet { defaults.set(showsFrames, forKey: Keys.showsFrames) } }
    /// Whether playing in the editor and the export preview is heard.
    var playsSound: Bool { didSet { defaults.set(playsSound, forKey: Keys.playsSound) } }
    /// Where exports go without asking; nil asks each time.
    var exportFolder: URL? {
        didSet { defaults.set(exportFolder?.standardizedFileURL.path, forKey: Keys.exportFolder) }
    }
    /// Whether a finished export is shown in the Finder.
    var revealsExports: Bool { didSet { defaults.set(revealsExports, forKey: Keys.revealsExports) } }
    /// Whether AI apps (Claude and others speaking MCP) may read and change
    /// the open project, through `AgentService`'s private socket.
    var allowsAgents: Bool {
        didSet {
            defaults.set(allowsAgents, forKey: Keys.allowsAgents)
            AgentService.shared.update()
        }
    }

    /// The values a fresh install starts from, which a project made before
    /// Settings existed had too.
    static let standardNudge = 1.0
    static let standardShiftNudge = 10.0

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let newProject = "newProject"
        static let nudge = "nudge"
        static let shiftNudge = "shiftNudge"
        static let actionEasing = "actionEasing"
        static let actionDuration = "actionDuration"
        static let showsFrames = "showsFrames"
        static let playsSound = "playsSound"
        static let exportFolder = "exportFolder"
        static let revealsExports = "revealsExports"
        static let allowsAgents = "allowsAgents"
    }

    private init() {
        let d = UserDefaults.standard
        newProject = d.data(forKey: Keys.newProject).flatMap { try? JSONDecoder().decode(Composition.self, from: $0) }
            ?? Composition()
        nudge = d.object(forKey: Keys.nudge) as? Double ?? Self.standardNudge
        shiftNudge = d.object(forKey: Keys.shiftNudge) as? Double ?? Self.standardShiftNudge
        actionEasing = d.string(forKey: Keys.actionEasing).flatMap(EasingPreset.init(rawValue:)) ?? .smooth
        actionDuration = d.object(forKey: Keys.actionDuration) as? Double ?? 0.5
        showsFrames = d.bool(forKey: Keys.showsFrames)
        playsSound = d.object(forKey: Keys.playsSound) as? Bool ?? true
        exportFolder = d.string(forKey: Keys.exportFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
        revealsExports = d.bool(forKey: Keys.revealsExports)
        allowsAgents = d.object(forKey: Keys.allowsAgents) as? Bool ?? true
    }

    /// The easing a new action takes, at the strength every preset is used at.
    var newActionEasing: Easing { .preset(actionEasing, intensity: Easing.standardIntensity) }

    private func save<T: Encodable>(_ value: T, as key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
