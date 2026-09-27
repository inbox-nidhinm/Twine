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
    /// The layer under the pointer, on the canvas or in the layers panel,
    /// which both light up.
    var hoveredLayer: UUID?
    /// The keyboard shortcuts card is up (⌘/).
    var showShortcuts = false
    /// A short note over the canvas, such as fonts a paste could not find.
    /// Goes by itself after a few seconds.
    var notice: String?
    @ObservationIgnored private var noticeTimer: Timer?

    func showNotice(_ text: String) {
        notice = text
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.notice = nil }
        }
    }
    /// The export panel covers the window.
    var showExport = false
    /// The export panel's preview player, while the panel is up, for Space.
    var exportPlayer: ExportPreviewPlayer?
    /// The layer whose name is being edited in the layers panel.
    var renaming: UUID?
    /// Set to a text layer to put the keyboard in its text box in the
    /// inspector, as the Text tool and a double-click on text do.
    var editingText: UUID?
    /// The playhead, in seconds.
    var time: Double = 0
    var isPlaying = false
    var loops = true
    /// Whether dragging, resizing and drawing snap to the composition and
    /// to other layers. Remembered for every window and every launch.
    var snaps: Bool = UserDefaults.standard.object(forKey: EditorModel.snapsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(snaps, forKey: Self.snapsKey) }
    }
    private static let snapsKey = "snapping"
    /// Whether times read as frame numbers rather than seconds.
    var showsFrames = false

    /// Where the last click landed, so Delete, Copy and Paste act on
    /// actions after a click in the timeline and on layers otherwise.
    var focus: Focus = .canvas
    /// Actions picked in the timeline. Their layers are selected with them.
    var selectedActions: Set<UUID> = []
    /// Actions the timeline should scroll to, such as ones just added. The
    /// count changes with every request, so the same actions can be asked
    /// for twice and the timeline never has to clear it.
    var revealActions: (ids: Set<UUID>, request: Int) = ([], 0)
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
    let exports = ExportSession()
}

/// How the timeline maps time to points. Shared by the ruler and the tracks
/// so they cannot disagree.
@MainActor
@Observable
final class TimelineViewport {
    var pointsPerSecond: Double = 100
    var hasFitted = false

    /// How far 0s sits in from the left edge when scrolled all the way back,
    /// in points: room for the playhead's pill.
    static let lead: Double = 24

    /// The time at the left edge of the tracks. Never earlier than 0s less
    /// the lead, at any zoom, so 0s is a hard stop.
    var start: Double {
        get { max(origin, earliest) }
        set { origin = max(newValue, earliest) }
    }

    private var origin: Double = 0
    private var earliest: Double { -Self.lead / pointsPerSecond }

    func x(for time: Double) -> Double { (time - start) * pointsPerSecond }
    func time(at x: Double) -> Double { x / pointsPerSecond + start }
}

enum Tool: String, CaseIterable {
    case select, frame, rectangle, ellipse, line, polygon, star, pen, text

    var title: String {
        switch self {
        case .select: return "Select"
        case .frame: return "Frame"
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
        case .frame: return .frame
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
        case .frame: return "F"
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
    /// Draws a box by dragging: a shape or a frame.
    var draws: Bool { isShape || self == .frame }

    /// The tool a letter picks, for the canvas's keyboard.
    static func forKey(_ key: String) -> Tool? {
        allCases.first { $0.key.lowercased() == key.lowercased() }
    }
}
