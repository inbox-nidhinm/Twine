import Foundation
import Observation
import MotionModel

/// The live project behind one open document, and the only thing that changes it.
///
/// Undo works by snapshot: the project is a value, so recording the whole state
/// before a change is cheap (unchanged branches of the tree share storage) and
/// restoring it is exact. That sidesteps writing an inverse for every command,
/// which is where hand-written undo usually goes wrong.
@MainActor
@Observable
public final class ProjectStore {
    public private(set) var project: Project

    /// The document's own undo manager, so Edit > Undo, the change count that
    /// drives autosave, and the window's edited state all come for free.
    @ObservationIgnored public let undoManager: UndoManager

    /// The state when a continuous change (a drag, a slider) began.
    @ObservationIgnored private var continuousStart: Project?
    @ObservationIgnored private var continuousName = ""
    /// While a folding change is open, plain commands join it rather than
    /// each becoming an undo step: for controls whose every step is an
    /// ordinary edit, such as dragging across a number field.
    @ObservationIgnored private var foldsCommands = false
    /// The key of the last step while `perform(_:joining:)` may still add
    /// to it: cleared by any other step, undo, redo or continuous change.
    @ObservationIgnored private var joinable: String?

    /// At most this many steps can be undone (the user's choice, 28 September
    /// 2026; After Effects allows 99, Photoshop keeps 50).
    public static let undoSteps = 200
    /// And the history keeps no more than about this much memory: past it,
    /// the oldest steps go first. A net for huge projects; ordinary ones never
    /// reach it.
    public static let undoBudget = 512 * 1024 * 1024
    @ObservationIgnored private let budget: Int
    /// What each step keeps alive, oldest first, for the steps that can be
    /// undone and those that can be redone.
    @ObservationIgnored private var undoCosts: [Int] = []
    @ObservationIgnored private var redoCosts: [Int] = []

    public init(project: Project, undoManager: UndoManager, undoBudget: Int = ProjectStore.undoBudget) {
        self.project = project
        self.undoManager = undoManager
        self.budget = undoBudget
        undoManager.levelsOfUndo = Self.undoSteps
    }

    /// Applies one command as one undo step. A command that changes nothing
    /// records nothing.
    public func perform(_ command: EditorCommand) throws {
        if foldsCommands, continuousStart != nil { return try command.apply(to: &project) }
        let before = project
        try command.apply(to: &project)
        guard project != before else { return }
        record(before: before, name: command.actionName)
    }

    /// Applies a command that joins the last step when that step came from
    /// here with the same `key` and nothing has happened since; otherwise it
    /// starts a step of its own. For typing: the letters typed in one go
    /// undo together, while a change made in between (a new font size from
    /// the inspector) is its own step, in the order they happened, rather
    /// than one step held open the whole time swallowing it.
    public func perform(_ command: EditorCommand, joining key: String) throws {
        guard continuousStart == nil else { return try perform(command) }
        if key == joinable { return try command.apply(to: &project) }
        let before = project
        try command.apply(to: &project)
        guard project != before else { return }
        record(before: before, name: command.actionName)
        joinable = key
    }

    /// Swaps in a project read from disk, such as a version restored from the
    /// Versions browser. What was undoable belonged to the old contents, so
    /// the history goes with them.
    public func load(_ project: Project) {
        joinable = nil
        continuousStart = nil
        foldsCommands = false
        self.project = project
        undoManager.removeAllActions(withTarget: self)
        undoCosts = []
        redoCosts = []
    }

    // MARK: Continuous changes

    /// Starts a change that arrives as many small steps, like dragging a layer
    /// or a slider, and should undo as one.
    ///
    /// With `folding`, `perform` joins the change too until it ends, so a
    /// control that only knows how to make ordinary edits still undoes as
    /// one step.
    public func beginContinuousChange(_ name: String, folding: Bool = false) {
        joinable = nil
        if continuousStart == nil {
            continuousStart = project
            foldsCommands = folding
        }
        continuousName = name
    }

    /// One step of a continuous change. Applied at once so the canvas follows
    /// the pointer, but not recorded until `endContinuousChange`.
    public func updateContinuousChange(_ command: EditorCommand) throws {
        guard continuousStart != nil else { return try perform(command) }
        try command.apply(to: &project)
    }

    /// Records the whole change, from where it began to where it ended, as one
    /// undo step.
    public func endContinuousChange() {
        guard let start = continuousStart else { return }
        continuousStart = nil
        foldsCommands = false
        guard project != start else { return }
        record(before: start, name: continuousName)
    }

    /// Puts everything back to how it was before the continuous change began,
    /// recording nothing. For a drag cancelled with Escape.
    public func cancelContinuousChange() {
        guard let start = continuousStart else { return }
        continuousStart = nil
        foldsCommands = false
        project = start
    }

    // MARK: Undo

    private func record(before: Project, name: String) {
        joinable = nil
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(before, name: name) }
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
        // A new step clears what could be redone, as the undo manager does.
        undoCosts.append(Self.cost(of: before, against: project))
        redoCosts = []
        if undoCosts.count > Self.undoSteps { undoCosts.removeFirst(undoCosts.count - Self.undoSteps) }
        trimToBudget()
    }

    /// Roughly what a snapshot keeps alive that the project does not share:
    /// the lists that changed, copied whole. Snapshots share everything
    /// else, and pictures and videos are files, never copied. Paths and words
    /// inside a layer are not counted, so a huge pasted drawing counts as
    /// less than it is.
    static func cost(of before: Project, against after: Project) -> Int {
        var bytes = 1024
        if before.layers != after.layers { bytes += before.allLayers.count * MemoryLayout<Layer>.stride }
        if before.actions != after.actions { bytes += before.actions.count * MemoryLayout<Action>.stride }
        return bytes
    }

    /// Drops the oldest steps until the history fits the budget, always
    /// keeping the latest. The undo manager removes its oldest steps when its
    /// limit is lowered, so the limit is lowered for a moment and put back.
    private func trimToBudget() {
        var total = undoCosts.reduce(0, +) + redoCosts.reduce(0, +)
        var drop = 0
        while total > budget, drop < undoCosts.count - 1 {
            total -= undoCosts[drop]
            drop += 1
        }
        guard drop > 0 else { return }
        undoManager.levelsOfUndo = undoCosts.count - drop
        undoManager.levelsOfUndo = Self.undoSteps
        undoCosts.removeFirst(drop)
    }

    /// Undo and redo are the same operation in opposite directions: swap in
    /// the other snapshot and register the one being left as its own reverse.
    private func restore(_ snapshot: Project, name: String) {
        joinable = nil
        if undoManager.isUndoing, let cost = undoCosts.popLast() {
            redoCosts.append(cost)
        } else if undoManager.isRedoing, let cost = redoCosts.popLast() {
            undoCosts.append(cost)
        }
        let leaving = project
        project = snapshot
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(leaving, name: name) }
        }
        undoManager.setActionName(name)
    }
}
