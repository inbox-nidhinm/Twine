import Foundation
import MotionModel

/// The timeline's edits to actions, worked out as plain values so they can
/// be tested without a window. Every time they produce lands on a frame.
public enum ActionEditing {
    // MARK: Row order

    /// A layer's actions in their rows, top to bottom. Rows follow
    /// `rowOrder`; new actions are slotted in by start time, and the user can
    /// rearrange them. Start, then id, only settle ties.
    public static func rows(on layerID: UUID, in project: Project) -> [Action] {
        project.actions(on: layerID).sorted(by: rowOrder)
    }

    /// Every action in its timeline row, top to bottom: one list for the
    /// whole project, in the order the actions were added unless rows have
    /// been dragged. A new action takes the next row at the bottom.
    public static func timeline(in project: Project) -> [Action] {
        project.actions.sorted(by: rowOrder)
    }

    /// The order of rows.
    public static func rowOrder(_ a: Action, _ b: Action) -> Bool {
        if a.rowOrder != b.rowOrder { return a.rowOrder < b.rowOrder }
        if a.start != b.start { return a.start < b.start }
        return a.id.uuidString < b.id.uuidString
    }

    /// The timeline with `actionID` moved to row `index`, renumbered from 0.
    /// Only rows whose order changed come back.
    public static func moving(_ actionID: UUID, toRow index: Int, in project: Project) -> [Action] {
        var rows = timeline(in: project)
        guard let from = rows.firstIndex(where: { $0.id == actionID }) else { return [] }
        let action = rows.remove(at: from)
        rows.insert(action, at: min(max(index, 0), rows.count))
        return renumber(rows).filter { a in project.actions.first { $0.id == a.id }?.rowOrder != a.rowOrder }
    }

    private static func renumber(_ rows: [Action]) -> [Action] {
        rows.enumerated().map { index, action in
            var a = action
            a.rowOrder = index
            return a
        }
    }

    // MARK: Timing

    /// The actions moved later by `delta` seconds, together, landing on
    /// frames and never before the start of the composition.
    public static func moved(_ actions: [Action], by delta: Double, rate: FrameRate) -> [Action] {
        guard let earliest = actions.map(\.start).min() else { return [] }
        let d = max(rate.snapped(delta), -rate.snapped(earliest))
        return actions.map { action in
            var a = action
            a.start = rate.snapped(action.start + d)
            return a
        }
    }

    /// The action with one end dragged to `time`. The other end stays put,
    /// or with `symmetric` moves the opposite way, and the action never gets
    /// shorter than a frame or starts before zero.
    ///
    /// A Play bar trims its media: its start edge moves where in the file it
    /// begins, so the picture and sound stay where they were in time, and
    /// neither edge goes past the ends of the file (`mediaLength`, when known).
    public static func trimmed(_ action: Action, startEdge: Bool, to time: Double, symmetric: Bool,
                               rate: FrameRate, mediaLength: Double? = nil) -> Action {
        let frame = rate.frameDuration
        var a = action
        let t = rate.snapped(time)
        var play: PlayAction?
        if case .play(let p) = action.spec { play = p }
        // The furthest back the start can go, and forward the end, in the file.
        let earliest = play.map { action.start - $0.trimStart } ?? -Double.infinity
        let latest = play.flatMap { p in mediaLength.map { action.start - p.trimStart + $0 } } ?? .infinity
        if startEdge {
            var start = t, end = action.end
            if symmetric { end = min(rate.snapped(action.end - (t - action.start)), latest) }
            start = max(0, earliest, min(start, end - frame))
            a.start = start
            a.duration = max(rate.snapped(end - start), frame)
        } else {
            var start = action.start, end = min(t, latest)
            if symmetric { start = max(0, earliest, rate.snapped(action.start - (t - action.end))) }
            end = max(end, start + frame)
            a.start = start
            a.duration = rate.snapped(end - start)
        }
        if var p = play {
            p.trimStart = max(0, p.trimStart + (a.start - action.start))
            a.spec = .play(p)
        }
        return a
    }

    /// The actions, in the order given, starting `gap` seconds apart from the
    /// first one's start.
    public static func staggered(_ actions: [Action], gap: Double, rate: FrameRate) -> [Action] {
        guard let first = actions.first else { return [] }
        return actions.enumerated().map { index, action in
            var a = action
            a.start = max(0, rate.snapped(first.start + gap * Double(index)))
            return a
        }
    }

    // MARK: Copies

    /// Copies of the actions, each with an id of its own, placed straight
    /// after the originals: shifted by the span they cover together, so a
    /// sequence carries on.
    public static func duplicates(of actions: [Action], rate: FrameRate) -> [Action] {
        guard let start = actions.map(\.start).min(), let end = actions.map(\.end).max() else { return [] }
        let shift = max(end - start, rate.frameDuration)
        return actions.map { copy(of: $0, target: $0.targetLayerID, start: rate.snapped($0.start + shift)) }
    }

    /// Copies of clipboard actions landing with the earliest at `time`,
    /// keeping their spacing. With `targets`, every action goes to each
    /// target layer that can take it; without, each goes back to its own
    /// layer if that still exists.
    public static func pasted(_ actions: [Action], onto targets: [Layer], at time: Double,
                              in project: Project, rate: FrameRate) -> [Action] {
        guard let earliest = actions.map(\.start).min() else { return [] }
        func place(_ a: Action, on target: UUID) -> Action {
            copy(of: a, target: target, start: rate.snapped(max(0, time + a.start - earliest)))
        }
        if targets.isEmpty {
            return actions.filter { project.layer(withID: $0.targetLayerID) != nil }.map { place($0, on: $0.targetLayerID) }
        }
        return targets.flatMap { layer in
            let allowed = Set(ActionFactory.kinds(for: layer))
            return actions.filter { allowed.contains($0.spec.kind) }.map { place($0, on: layer.id) }
        }
    }

    private static func copy(of a: Action, target: UUID, start: Double) -> Action {
        Action(target: target, start: start, duration: a.duration, easing: a.easing, name: a.name,
               isEnabled: a.isEnabled, rowOrder: a.rowOrder, spec: a.spec)
    }

    /// New actions given the rows at the bottom of the timeline, in the
    /// order they come.
    public static func appendingRows(_ actions: [Action], in project: Project) -> [Action] {
        let first = ActionFactory.nextRowOrder(in: project)
        return actions.enumerated().map { index, action in
            var a = action
            a.rowOrder = first + index
            return a
        }
    }

    // MARK: Edges

    /// Every start and end in the project, for jumping the playhead from one
    /// to the next.
    public static func edges(in project: Project) -> [Double] {
        Array(Set(project.actions.flatMap { [$0.start, $0.end] })).sorted()
    }

    public static func edge(after time: Double, in project: Project) -> Double? {
        edges(in: project).first { $0 > time + 1e-9 }
    }

    public static func edge(before time: Double, in project: Project) -> Double? {
        edges(in: project).last { $0 < time - 1e-9 }
    }
}

/// Actions on the pasteboard.
public struct ActionClipboard: Codable, Sendable {
    public var actions: [Action]

    public init(actions: [Action]) {
        self.actions = actions
    }
}
