import Foundation
import Observation
import Theme
import MotionEditing

/// The editor's own state for one window: what is shown and what is in hand.
/// None of this is saved in the project.
@MainActor
@Observable
final class EditorModel {
    enum Mode: String, CaseIterable {
        /// Tools on the bottom bar, no timeline: building the frame.
        case design
        /// The timeline in place of the tools: making it move.
        case animate

        var title: String {
            switch self {
            case .design: return "Design"
            case .animate: return "Animate"
            }
        }
    }

    var mode: Mode = .design
    var showLayers = true
    var showInspector = true
    var tool: Tool = .select
    /// The shape that the shape slot shows, which is the one used last.
    var lastShape: Tool = .rectangle
    var selection: Set<UUID> = []
    /// The layer whose name is being edited in the layers panel.
    var renaming: UUID?
    /// The playhead, in seconds.
    var time: Double = 0
    var isPlaying = false
    var loops = true
    /// Whether times read as frame numbers rather than seconds.
    var showsFrames = false

    /// Where the last click landed, so Delete, Copy and Paste act on
    /// actions after a click in the timeline and on layers otherwise.
    var focus: Focus = .canvas
    /// Actions picked in the timeline. Their layers are selected with them.
    var selectedActions: Set<UUID> = []
    /// The timeline lists only the selected layers' actions.
    var timelineOnlySelected = false
    /// The timeline card's height, which its top edge drags. Remembered for
    /// every window and every launch.
    var timelineHeight: CGFloat = EditorModel.savedTimelineHeight

    static let timelineHeightRange: ClosedRange<CGFloat> = 160...640
    private static let timelineHeightKey = "timelineHeight"

    static var savedTimelineHeight: CGFloat {
        let saved = UserDefaults.standard.double(forKey: timelineHeightKey)
        return saved > 0 ? min(max(saved, timelineHeightRange.lowerBound), timelineHeightRange.upperBound) : 260
    }

    func saveTimelineHeight() {
        UserDefaults.standard.set(Double(timelineHeight), forKey: Self.timelineHeightKey)
    }

    enum Focus { case canvas, timeline }

    let viewport = TimelineViewport()
}

/// How the timeline maps time to points. Shared by the ruler and the tracks
/// so they cannot disagree.
@MainActor
@Observable
final class TimelineViewport {
    var pointsPerSecond: Double = 100
    /// The time at the left edge of the tracks.
    var start: Double = 0
    var hasFitted = false

    func x(for time: Double) -> Double { (time - start) * pointsPerSecond }
    func time(at x: Double) -> Double { x / pointsPerSecond + start }
}

enum Tool: String, CaseIterable {
    case select, rectangle, ellipse, line, polygon, star, pen, text

    var title: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .polygon: return "Polygon"
        case .star: return "Star"
        case .pen: return "Pen"
        case .text: return "Text"
        }
    }

    var icon: Icon {
        switch self {
        case .select: return .select
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .polygon: return .polygon
        case .star: return .star
        case .pen: return .pen
        case .text: return .text
        }
    }

    /// The letter that picks the tool from the keyboard.
    var key: String {
        switch self {
        case .select: return "V"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .line: return "L"
        case .polygon: return "Y"
        case .star: return "S"
        case .pen: return "P"
        case .text: return "T"
        }
    }

    static let shapes: [Tool] = [.rectangle, .ellipse, .line, .polygon, .star]
    var isShape: Bool { Self.shapes.contains(self) }

    /// The pen arrives in milestone 8 and text in milestone 6. Until then
    /// their buttons show as disabled rather than doing nothing when picked.
    var isAvailable: Bool { self != .pen && self != .text }

    /// The tool a letter picks, for the canvas's keyboard.
    static func forKey(_ key: String) -> Tool? {
        allCases.first { $0.key.lowercased() == key.lowercased() && $0.isAvailable }
    }
}
