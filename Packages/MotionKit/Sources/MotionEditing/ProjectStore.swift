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

    public init(project: Project, undoManager: UndoManager) {
        self.project = project
        self.undoManager = undoManager
    }

    /// Applies one command as one undo step. A command that changes nothing
    /// records nothing.
    public func perform(_ command: EditorCommand) throws {
        let before = project
        try command.apply(to: &project)
        guard project != before else { return }
        record(before: before, name: command.actionName)
    }

    /// Swaps in a project read from disk, such as a version restored from the
    /// Versions browser. What was undoable belonged to the old contents, so
    /// the history goes with them.
    public func load(_ project: Project) {
        continuousStart = nil
        self.project = project
        undoManager.removeAllActions(withTarget: self)
    }

    // MARK: Continuous changes

    /// Starts a change that arrives as many small steps, like dragging a layer
    /// or a slider, and should undo as one.
    public func beginContinuousChange(_ name: String) {
        if continuousStart == nil { continuousStart = project }
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
        guard project != start else { return }
        record(before: start, name: continuousName)
    }

    /// Puts everything back to how it was before the continuous change began,
    /// recording nothing. For a drag cancelled with Escape.
    public func cancelContinuousChange() {
        guard let start = continuousStart else { return }
        continuousStart = nil
        project = start
    }

    // MARK: Undo

    private func record(before: Project, name: String) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(before, name: name) }
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }

    /// Undo and redo are the same operation in opposite directions: swap in
    /// the other snapshot and register the one being left as its own reverse.
    private func restore(_ snapshot: Project, name: String) {
        let leaving = project
        project = snapshot
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(leaving, name: name) }
        }
        undoManager.setActionName(name)
    }
}
