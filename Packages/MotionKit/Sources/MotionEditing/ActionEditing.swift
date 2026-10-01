import Foundation
import MotionModel
import MotionEvaluation

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
        // Sorted by small keys and gathered after, rather than moving whole
        // actions about: the timeline asks for this on every step of a drag.
        let actions = project.actions
        let keys = actions.indices.map { RowKey(order: actions[$0].rowOrder, start: actions[$0].start, id: actions[$0].id, index: $0) }
        return keys.sorted().map { actions[$0.index] }
    }

    private struct RowKey: Comparable {
        let order: Int
        let start: Double
        let id: UUID
        let index: Int

        static func < (a: RowKey, b: RowKey) -> Bool {
            if a.order != b.order { return a.order < b.order }
            if a.start != b.start { return a.start < b.start }
            return a.id.precedes(b.id)
        }
    }

    /// The order of rows.
    public static func rowOrder(_ a: Action, _ b: Action) -> Bool {
        if a.rowOrder != b.rowOrder { return a.rowOrder < b.rowOrder }
        if a.start != b.start { return a.start < b.start }
        return a.id.precedes(b.id)
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

    /// Several actions trimmed together from the same end by the same time,
    /// as dragging one of them trims them all: each edge moves `delta`, and
    /// each action keeps to its own limits (a frame at least, never before
    /// zero, its file's ends). Instant ones have no length and are left out.
    public static func trimmed(_ actions: [Action], startEdge: Bool, by delta: Double, symmetric: Bool,
                               rate: FrameRate, mediaLength: (Action) -> Double? = { _ in nil }) -> [Action] {
        actions.filter { !$0.isInstant }.map { a in
            trimmed(a, startEdge: startEdge, to: (startEdge ? a.start : a.end) + delta, symmetric: symmetric,
                    rate: rate, mediaLength: mediaLength(a))
        }
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
    ///
    /// On a layer other than its own, an action with its `origin` (where
    /// its own layer stood as it began) makes the same motion from where the
    /// new layer stands: a Move To travels as far the same way, a Scale To
    /// grows by as much, a starting value moves along with it (`carried`).
    /// Back on its own layer it is copied exactly.
    public static func pasted(_ actions: [Action], onto targets: [Layer], at time: Double, in project: Project,
                              rate: FrameRate, origins: [UUID: ActionOrigin] = [:]) -> [Action] {
        pastedPairs(actions, onto: targets, at: time, in: project, rate: rate, origins: origins).map(\.copy)
    }

    /// The same copies, each with the id of the action it copies, so a copy
    /// can join its original's scene.
    public static func pastedPairs(_ actions: [Action], onto targets: [Layer], at time: Double, in project: Project,
                                   rate: FrameRate, origins: [UUID: ActionOrigin] = [:]) -> [(original: UUID, copy: Action)] {
        guard let earliest = actions.map(\.start).min() else { return [] }
        func place(_ a: Action, on target: UUID) -> Action {
            copy(of: a, target: target, start: rate.snapped(max(0, time + a.start - earliest)))
        }
        if targets.isEmpty {
            return actions.filter { project.layer(withID: $0.targetLayerID) != nil }.map { ($0.id, place($0, on: $0.targetLayerID)) }
        }
        var pairs: [(original: UUID, copy: Action)] = []
        var placed: [Action] = []
        for layer in targets {
            let allowed = Set(ActionFactory.kinds(for: layer, in: project))
            let presets = Presets.available(for: [layer], in: project)
            for action in actions.sorted(by: { $0.start < $1.start }) where fits(action, on: layer, allowed: allowed, presets: presets) {
                var made = place(action, on: layer.id)
                if layer.id != action.targetLayerID, let origin = origins[action.id] {
                    // Where the new layer stands as the copy begins, after
                    // what is already on it and what went on before it.
                    let tracks = ActionTracks(project.actions + placed + [made])
                    made = carried(made, from: origin, to: ActionOrigin(tracks.inheritedState(for: made, of: layer)))
                }
                placed.append(made)
                pairs.append((action.id, made))
            }
        }
        return pairs
    }

    /// Whether an action suits the layer it would be pasted onto: one of
    /// the kinds it can take, or a preset it is offered (either way round),
    /// one moving letters only on text.
    private static func fits(_ action: Action, on layer: Layer, allowed: Set<ActionKind>, presets: [Preset]) -> Bool {
        guard case .preset(let p) = action.spec else { return allowed.contains(action.spec.kind) }
        return (p.unit == nil || layer.isText) && presets.contains { $0.kind == p.preset || $0.kind.reversed == p.preset }
    }

    /// `action` moved from a layer that stood at `from` to one standing at
    /// `to`: its To value and its starting value shifted by the difference
    /// in place, turn, skew and tilt, and scaled by the ratio of scale and
    /// size, so it makes the same motion. By values already are relative
    /// and stay; a curved Move's handles are relative to its ends.
    public static func carried(_ action: Action, from: ActionOrigin, to: ActionOrigin) -> Action {
        func ratio(_ a: Double, _ b: Double) -> Double { abs(a) > 1e-9 ? b / a : 1 }
        let shift = Vec2(to.position.x - from.position.x, to.position.y - from.position.y)
        let grow = Vec2(ratio(from.scale.x, to.scale.x), ratio(from.scale.y, to.scale.y))
        let widen = Size2(ratio(from.size.width, to.size.width), ratio(from.size.height, to.size.height))
        let turn = to.rotation - from.rotation
        let slant = Vec2(to.skew.x - from.skew.x, to.skew.y - from.skew.y)
        var a = action
        switch action.spec {
        case .move(var m):
            if m.mode == .to { m.end = m.end + shift }
            m.initial = m.initial.map { $0 + shift }
            a.spec = .move(m)
        case .scale(var s):
            if s.mode == .to { s.end = Vec2(s.end.x * grow.x, s.end.y * grow.y) }
            s.initial = s.initial.map { Vec2($0.x * grow.x, $0.y * grow.y) }
            a.spec = .scale(s)
        case .rotate(var r):
            if r.mode == .to { r.end += turn }
            r.initial = r.initial.map { $0 + turn }
            a.spec = .rotate(r)
        case .resize(var r):
            r.end = Size2(r.end.width * widen.width, r.end.height * widen.height)
            r.initial = r.initial.map { Size2($0.width * widen.width, $0.height * widen.height) }
            a.spec = .resize(r)
        case .skew(var s):
            if s.mode == .to { s.end = s.end + slant }
            s.initial = s.initial.map { $0 + slant }
            a.spec = .skew(s)
        case .tilt(var t):
            func tilted(_ v: Tilt) -> Tilt {
                Tilt(x: v.x + to.tilt.x - from.tilt.x, y: v.y + to.tilt.y - from.tilt.y, depth: v.depth)
            }
            if t.mode == .to { t.end = tilted(t.end) }
            t.initial = t.initial.map(tilted)
            a.spec = .tilt(t)
        default:
            break
        }
        return a
    }

    private static func copy(of a: Action, target: UUID, start: Double) -> Action {
        var made = Action(target: target, start: start, duration: a.duration, easing: a.easing, name: a.name,
                          isEnabled: a.isEnabled, rowOrder: a.rowOrder, spec: a.spec)
        made.motionBlur = a.motionBlur
        return made
    }

    /// New actions placed each just below the last row of the layer it is
    /// on (at the bottom when that layer has none), so a layer's actions
    /// stay together, with every row renumbered from 0: the new actions
    /// with their row orders, and the actions already in the project whose
    /// row order changed.
    public static func placingWithTheirLayers(_ actions: [Action], in project: Project) -> (actions: [Action], moved: [Action]) {
        var rows = timeline(in: project)
        for action in actions {
            if let last = rows.lastIndex(where: { $0.targetLayerID == action.targetLayerID }) {
                rows.insert(action, at: last + 1)
            } else {
                rows.append(action)
            }
        }
        let newIDs = Set(actions.map(\.id))
        let numbered = renumber(rows)
        let old = Dictionary(project.actions.map { ($0.id, $0.rowOrder) }, uniquingKeysWith: { a, _ in a })
        return (numbered.filter { newIDs.contains($0.id) },
                numbered.filter { !newIDs.contains($0.id) && old[$0.id] != $0.rowOrder })
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

    /// Copies placed each on the row just below its original, as a
    /// duplicate in the timeline is, with every row renumbered from 0: the
    /// copies with their new row orders, and the actions already in the
    /// project whose row order changed. `copies` pairs with `originals` by
    /// position.
    public static func placingBelow(_ copies: [Action], originals: [Action],
                                    in project: Project) -> (copies: [Action], moved: [Action]) {
        var below: [UUID: Action] = [:]
        for (original, copy) in zip(originals, copies) { below[original.id] = copy }
        var rows: [Action] = []
        for row in timeline(in: project) {
            rows.append(row)
            if let copy = below[row.id] { rows.append(copy) }
        }
        let copyIDs = Set(copies.map(\.id))
        let numbered = renumber(rows)
        let old = Dictionary(project.actions.map { ($0.id, $0.rowOrder) }, uniquingKeysWith: { a, _ in a })
        return (numbered.filter { copyIDs.contains($0.id) },
                numbered.filter { !copyIDs.contains($0.id) && old[$0.id] != $0.rowOrder })
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

/// Actions on the pasteboard, with where each one's layer stood as it
/// began, so a paste onto another layer can make the same motion.
public struct ActionClipboard: Codable, Sendable {
    public var actions: [Action]
    /// By action id; nil in a copy made before origins were kept.
    public var origins: [UUID: ActionOrigin]?
    /// The scenes copied whole, so a paste makes them again (`Scenes.copying`).
    public var scenes: [TimelineScene]?

    public init(actions: [Action], origins: [UUID: ActionOrigin]? = nil, scenes: [TimelineScene]? = nil) {
        self.actions = actions
        self.origins = origins
        self.scenes = scenes
    }
}

/// Where a layer stands, as far as moving actions go: its place, scale,
/// turn, size, skew and tilt.
public struct ActionOrigin: Codable, Sendable, Equatable {
    public var position: Vec2
    public var scale: Vec2
    public var rotation: Double
    public var size: Size2
    public var skew: Vec2
    public var tilt: Tilt

    public init(position: Vec2, scale: Vec2, rotation: Double, size: Size2, skew: Vec2 = .zero, tilt: Tilt = .none) {
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.size = size
        self.skew = skew
        self.tilt = tilt
    }

    public init(_ state: LayerState) {
        self.init(position: state.position, scale: state.scale, rotation: state.rotation, size: state.size,
                  skew: state.warp.skew, tilt: state.warp.tilt)
    }
}
