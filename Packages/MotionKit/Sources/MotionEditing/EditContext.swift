import Foundation
import MotionModel
import MotionEvaluation

/// How an edit to a value should land, which depends on the editor's mode.
///
/// - Design mode builds the frame. A static property takes the new value.
///   An animated one moves its whole animation so it passes through the new
///   value at the playhead, keeping its shape, where the value can be offset
///   (positions, sizes, numbers). Values that cannot be offset, such as
///   colours, are keyed at the playhead instead.
/// - Animate mode keys. An animated property gets a keyframe at the playhead,
///   or the one already there is updated. A static property takes the new
///   value, so that turning on the stopwatch is always a deliberate choice.
public struct EditContext: Sendable {
    public enum Mode: Sendable { case design, animate }

    public var time: Double
    public var mode: Mode
    /// How close to the playhead an existing keyframe must be to count as
    /// "the one at the playhead": half a frame.
    public var tolerance: Double

    public init(time: Double, mode: Mode, frameDuration: Double) {
        self.time = time
        self.mode = mode
        self.tolerance = frameDuration / 2
    }

    /// For edits that should never key, such as building a layer.
    public static func design(at time: Double) -> EditContext {
        EditContext(time: time, mode: .design, frameDuration: 1.0 / 60)
    }
}

extension AnimatableProperty where Value: Offsettable {
    public func edited(to new: Value, in context: EditContext) -> AnimatableProperty {
        guard isAnimated else { return AnimatableProperty(new) }
        switch context.mode {
        case .design: return shifted(by: new - value(at: context.time))
        case .animate: return inserting(new, at: context.time, tolerance: context.tolerance)
        }
    }
}

extension AnimatableProperty where Value: Interpolatable {
    /// For values that cannot be offset, such as colours and gradient stops.
    public func set(_ new: Value, in context: EditContext) -> AnimatableProperty {
        guard isAnimated else { return AnimatableProperty(new) }
        return inserting(new, at: context.time, tolerance: context.tolerance)
    }
}

extension Layer {
    /// The layer moved by `delta` in its parent's space: its whole path in
    /// Design mode, a keyframe at the playhead in Animate mode.
    public func moved(by delta: Vec2, in context: EditContext) -> Layer {
        guard transform.position.isAnimated, context.mode == .animate else { return translated(by: delta) }
        var copy = self
        copy.transform.position = transform.position.edited(to: transform.position.value(at: context.time) + delta, in: context)
        return copy
    }
}

/// Keyframe operations across layers.
public enum Keyframing {
    /// Applies `easing` to the segments that start at the chosen keyframes.
    ///
    /// A spring also moves the keyframe that ends its segment to where the
    /// spring naturally settles, carrying the keyframes after it along by the
    /// same amount so their spacing is kept. Dragging that keyframe later
    /// stretches the spring to fit.
    public static func setEasing(_ easing: Easing, for refs: Set<KeyframeRef>, in layer: Layer) -> Layer {
        var edited = layer
        let byProperty = Dictionary(grouping: refs.filter { $0.layerID == layer.id }, by: \.property)
        for (property, keys) in byProperty {
            let ids = Set(keys.map(\.keyframeID))
            LayerProperties.update(property, on: &edited) { p in
                var result = p.withEasing(easing, for: ids)
                guard case .spring(let spring) = easing else { return result }
                let settle = spring.settleDuration
                // Earliest first, so each move sees the positions left by the last.
                for start in result.marks.filter({ ids.contains($0.id) }).sorted(by: { $0.time < $1.time }) {
                    let marks = result.marks
                    guard let index = marks.firstIndex(where: { $0.id == start.id }), index + 1 < marks.count else { continue }
                    let delta = start.time + settle - marks[index + 1].time
                    var times: [UUID: Double] = [:]
                    for later in marks[(index + 1)...] { times[later.id] = later.time + delta }
                    result = result.retimed(times)
                }
                return result
            }
        }
        return edited
    }

    public static func delete(_ refs: Set<KeyframeRef>, in layer: Layer) -> Layer {
        var edited = layer
        for (property, keys) in Dictionary(grouping: refs.filter { $0.layerID == layer.id }, by: \.property) {
            LayerProperties.update(property, on: &edited) { $0.removing(Set(keys.map(\.keyframeID))) }
        }
        return edited
    }

    /// Moves the chosen keyframes to new times.
    public static func retime(_ times: [KeyframeRef: Double], in layer: Layer) -> Layer {
        var edited = layer
        for (property, entries) in Dictionary(grouping: times.filter { $0.key.layerID == layer.id }, by: \.key.property) {
            let moves = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.keyframeID, $0.value) })
            LayerProperties.update(property, on: &edited) { $0.retimed(moves) }
        }
        return edited
    }

    /// Stopwatch: on adds a keyframe with the current value at `time`; off
    /// clears every keyframe and holds the value the property had at `time`.
    public static func toggleStopwatch(_ property: PropertyID, on layer: Layer, at time: Double) -> Layer {
        var edited = layer
        LayerProperties.update(property, on: &edited) { p in
            p.isAnimated ? p.unkeyed(at: time) : p.keyed(at: time, tolerance: 0)
        }
        return edited
    }

    /// Adds a keyframe at `time` holding the value there, or removes the one
    /// already within `tolerance` of it.
    public static func toggleKeyframe(_ property: PropertyID, on layer: Layer, at time: Double, tolerance: Double) -> Layer {
        var edited = layer
        LayerProperties.update(property, on: &edited) { p in
            if let existing = p.marks.first(where: { abs($0.time - time) <= tolerance }) {
                return p.removing([existing.id])
            }
            return p.keyed(at: time, tolerance: tolerance)
        }
        return edited
    }

    /// The marks of every keyframe the layer has, for the collapsed row.
    public static func allMarks(of layer: Layer) -> [(PropertyID, KeyframeMark)] {
        LayerProperties.all(of: layer).flatMap { id in
            (LayerProperties.get(id, of: layer)?.marks ?? []).map { (id, $0) }
        }
    }
}

// MARK: - Clipboard

/// Keyframes copied from the timeline: per property, the keyframes encoded
/// in their own value type, with times as they were.
public struct KeyframeClipboard: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var property: PropertyID
        public var keyframes: Data
    }

    public var entries: [Entry]
    public var earliest: Double

    public static func copy(_ refs: Set<KeyframeRef>, from project: Project) -> KeyframeClipboard? {
        var entries: [Entry] = []
        var earliest = Double.infinity
        for (key, group) in Dictionary(grouping: refs, by: { KeyframeGroup(layerID: $0.layerID, property: $0.property) }) {
            guard let layer = project.layer(withID: key.layerID),
                  let property = LayerProperties.get(key.property, of: layer) else { continue }
            let ids = Set(group.map(\.keyframeID))
            guard let data = try? property.encodedKeyframes(ids) else { continue }
            earliest = min(earliest, property.marks.filter { ids.contains($0.id) }.map(\.time).min() ?? .infinity)
            entries.append(Entry(property: key.property, keyframes: data))
        }
        guard !entries.isEmpty, earliest.isFinite else { return nil }
        return KeyframeClipboard(entries: entries, earliest: earliest)
    }

    /// Pastes onto `layer` with the earliest keyframe at `time`. Each entry
    /// goes to the same property if the layer has it, otherwise to the first
    /// property of the same kind, so a fill's keyframes paste onto another
    /// layer's fill.
    public func paste(onto layer: Layer, at time: Double) -> Layer {
        var edited = layer
        let available = LayerProperties.all(of: layer)
        for entry in entries {
            guard let target = available.first(where: { $0 == entry.property }) ?? available.first(where: { $0.kind == entry.property.kind })
            else { continue }
            LayerProperties.update(target, on: &edited) { p in p.pasting(entry.keyframes, earliest: earliest, at: time) ?? p }
        }
        return edited
    }

    private struct KeyframeGroup: Hashable {
        var layerID: UUID
        var property: PropertyID
    }
}
