import Foundation
import MotionModel
import MotionEvaluation

/// Smart guides: pulling what is being moved, resized or drawn onto the
/// composition's edges and centre, other layers' edges and centres, and even
/// spacing, and the lines that show what it snapped to. All in composition
/// space, with every box upright.
public enum Snapping {
    public enum Axis: Sendable { case x, y }

    /// A line showing two things lined up. For `.x` it is upright, at
    /// `x == value`, running from `from` to `to` down the page; for `.y` it
    /// is level, at `y == value`, running across.
    public struct Guide: Equatable, Sendable {
        public var axis: Axis
        public var value: Double
        public var from: Double
        public var to: Double
    }

    /// A space shown as equal to another. For `.x` it runs across from
    /// `start` to `end` at height `cross`; for `.y` it runs down at `cross`.
    public struct Gap: Equatable, Sendable {
        public var axis: Axis
        public var start: Double
        public var end: Double
        public var cross: Double
        public var length: Double { end - start }
    }

    public struct Result: Equatable, Sendable {
        /// How far to shift what is being dragged so it lands snapped.
        public var offset: Vec2
        public var guides: [Guide]
        public var gaps: [Gap]

        public static let unsnapped = Result(offset: .zero, guides: [], gaps: [])
    }

    /// A box being moved: its edges and centre snap to the frame's and the
    /// targets', and it snaps to spacing equal to its neighbours'. `axes`
    /// limits it, for a drag held to one axis.
    public static func move(_ box: Box, targets: [Box], frame: Box, threshold: Double,
                            axes: Set<Axis> = [.x, .y]) -> Result {
        var result = Result.unsnapped
        for axis in [Axis.x, .y] where axes.contains(axis) {
            let span = Span(box, axis)
            var candidates = lines(span.values, box: box, targets: targets, frame: frame, axis: axis)
            candidates += spacing(box, targets: targets, axis: axis)
            guard let best = nearest(candidates, threshold: threshold) else { continue }
            apply(best, candidates, axis: axis, box: box, to: &result)
        }
        return result
    }

    /// A point being dragged, such as the corner of a shape being drawn or a
    /// resize handle, on the axes it moves along. `box` is what it shapes,
    /// for how long the guides run.
    public static func point(_ p: Vec2, box: Box, targets: [Box], frame: Box, threshold: Double,
                             axes: Set<Axis> = [.x, .y]) -> Result {
        var result = Result.unsnapped
        for axis in [Axis.x, .y] where axes.contains(axis) {
            let value = axis == .x ? p.x : p.y
            let candidates = lines([value], box: box, targets: targets, frame: frame, axis: axis)
            guard let best = nearest(candidates, threshold: threshold) else { continue }
            apply(best, candidates, axis: axis, box: box, to: &result)
        }
        return result
    }

    // MARK: Candidates

    /// One way to snap along an axis: moving by `offset` would line `value`
    /// up with something, which shows as a guide or a pair of gaps.
    private struct Candidate {
        var offset: Double
        var guide: (value: Double, other: Box?)?
        var gaps: [Gap] = []
    }

    /// Where a box sits along one axis: low edge, middle, high edge, and its
    /// extent across.
    private struct Span {
        var low, mid, high, crossLow, crossHigh: Double
        init(_ b: Box, _ axis: Axis) {
            if axis == .x {
                (low, mid, high, crossLow, crossHigh) = (b.minX, b.center.x, b.maxX, b.minY, b.maxY)
            } else {
                (low, mid, high, crossLow, crossHigh) = (b.minY, b.center.y, b.maxY, b.minX, b.maxX)
            }
        }
        var values: [Double] { [low, mid, high] }
    }

    /// Edges and centres: each of `values` against each target's and the
    /// frame's edges and centre.
    private static func lines(_ values: [Double], box: Box, targets: [Box], frame: Box, axis: Axis) -> [Candidate] {
        var out: [Candidate] = []
        for (target, isFrame) in targets.map({ ($0, false) }) + [(frame, true)] {
            let t = Span(target, axis)
            for tv in t.values {
                for v in values {
                    out.append(Candidate(offset: tv - v, guide: (tv, isFrame ? frame : target)))
                }
            }
        }
        return out
    }

    /// Even spacing along an axis, among the targets beside the box (those
    /// overlapping it across the axis): centred between its nearest
    /// neighbours either side, or one gap on from a neighbour, where the
    /// gap is one the neighbours already keep between themselves.
    private static func spacing(_ box: Box, targets: [Box], axis: Axis) -> [Candidate] {
        let me = Span(box, axis)
        let row = targets.map { Span($0, axis) }.filter { $0.crossHigh > me.crossLow && $0.crossLow < me.crossHigh }
        guard !row.isEmpty else { return [] }
        let size = me.high - me.low
        let before = row.filter { $0.high <= me.mid }.max { $0.high < $1.high }
        let after = row.filter { $0.low >= me.mid }.min { $0.low < $1.low }
        var out: [Candidate] = []

        func gap(_ a: Double, _ b: Double, across first: Span, _ second: Span) -> Gap {
            let lo = max(first.crossLow, second.crossLow), hi = min(first.crossHigh, second.crossHigh)
            return Gap(axis: axis, start: a, end: b, cross: (lo + hi) / 2)
        }

        if let before, let after, after.low - before.high > size {
            let low = (before.high + after.low - size) / 2
            let moved = Span(shifted(box, axis, by: low - me.low), axis)
            out.append(Candidate(offset: low - me.low, guide: nil,
                                 gaps: [gap(before.high, low, across: before, moved),
                                        gap(low + size, after.low, across: moved, after)]))
        }

        // Gaps the row already keeps between neighbours.
        let sorted = row.sorted { $0.low < $1.low }
        var pairs: [(Span, Span)] = []
        for (i, a) in sorted.enumerated() {
            if let b = sorted[(i + 1)...].first(where: { $0.low >= a.high }) { pairs.append((a, b)) }
        }
        for (a, b) in pairs {
            let g = b.low - a.high
            guard g > 0 else { continue }
            let shown = gap(a.high, b.low, across: a, b)
            if let before {
                let low = before.high + g
                let moved = Span(shifted(box, axis, by: low - me.low), axis)
                out.append(Candidate(offset: low - me.low, guide: nil,
                                     gaps: [shown, gap(before.high, low, across: before, moved)]))
            }
            if let after {
                let low = after.low - g - size
                let moved = Span(shifted(box, axis, by: low - me.low), axis)
                out.append(Candidate(offset: low - me.low, guide: nil,
                                     gaps: [shown, gap(low + size, after.low, across: moved, after)]))
            }
        }
        return out
    }

    private static func shifted(_ box: Box, _ axis: Axis, by d: Double) -> Box {
        axis == .x ? Box(minX: box.minX + d, minY: box.minY, maxX: box.maxX + d, maxY: box.maxY)
                   : Box(minX: box.minX, minY: box.minY + d, maxX: box.maxX, maxY: box.maxY + d)
    }

    private static func nearest(_ candidates: [Candidate], threshold: Double) -> Candidate? {
        candidates.filter { abs($0.offset) <= threshold }.min { abs($0.offset) < abs($1.offset) }
    }

    /// Takes the winning offset, and shows every guide and gap that it
    /// satisfies, so two things lined up at once both show.
    private static func apply(_ best: Candidate, _ candidates: [Candidate], axis: Axis, box: Box, to result: inout Result) {
        let offset = best.offset
        if axis == .x { result.offset.x = offset } else { result.offset.y = offset }
        let moved = Span(shifted(box, axis, by: offset), axis)
        let start = result.guides.count
        for c in candidates where abs(c.offset - offset) < 1e-6 {
            if let (value, other) = c.guide {
                var from = moved.crossLow, to = moved.crossHigh
                if let other {
                    let o = Span(other, axis)
                    from = min(from, o.crossLow)
                    to = max(to, o.crossHigh)
                }
                // One line per place, running past everything lined up on it.
                if let i = result.guides[start...].firstIndex(where: { abs($0.value - value) < 1e-6 }) {
                    result.guides[i].from = min(result.guides[i].from, from)
                    result.guides[i].to = max(result.guides[i].to, to)
                } else {
                    result.guides.append(Guide(axis: axis, value: value, from: from, to: to))
                }
            }
            for g in c.gaps where !result.gaps.contains(g) { result.gaps.append(g) }
        }
    }
}

/// Lining layers up and spacing them evenly. Works on upright boxes in
/// composition space and gives back how far each should move.
public enum Alignment {
    public enum Edge: String, CaseIterable, Sendable {
        case left, centerX, right, top, centerY, bottom
    }

    /// Each box moved so the edge lines up with the same edge of `reference`:
    /// the composition for one layer, the box around them all for several.
    public static func align(_ boxes: [UUID: Box], _ edge: Edge, to reference: Box) -> [UUID: Vec2] {
        boxes.mapValues { b in
            switch edge {
            case .left: Vec2(reference.minX - b.minX, 0)
            case .centerX: Vec2(reference.center.x - b.center.x, 0)
            case .right: Vec2(reference.maxX - b.maxX, 0)
            case .top: Vec2(0, reference.minY - b.minY)
            case .centerY: Vec2(0, reference.center.y - b.center.y)
            case .bottom: Vec2(0, reference.maxY - b.maxY)
            }
        }
    }

    /// Equal spaces between three or more boxes along an axis: the first and
    /// last stay put and the others move between them, in the order they
    /// already stand.
    public static func distribute(_ boxes: [UUID: Box], along axis: Snapping.Axis) -> [UUID: Vec2] {
        guard boxes.count >= 3 else { return [:] }
        func low(_ b: Box) -> Double { axis == .x ? b.minX : b.minY }
        func size(_ b: Box) -> Double { axis == .x ? b.width : b.height }
        let order = boxes.sorted { (low($0.value), $0.key.uuidString) < (low($1.value), $1.key.uuidString) }
        guard let first = order.first?.value, let last = order.last?.value else { return [:] }
        let span = low(last) + size(last) - low(first)
        let gap = (span - order.map { size($0.value) }.reduce(0, +)) / Double(order.count - 1)
        var out: [UUID: Vec2] = [:]
        var cursor = low(first)
        for (id, b) in order {
            let d = cursor - low(b)
            out[id] = axis == .x ? Vec2(d, 0) : Vec2(0, d)
            cursor += size(b) + gap
        }
        return out
    }
}
