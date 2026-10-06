import Foundation
import MotionModel
import MotionEvaluation

/// One point of a path: which subpath, and where in it.
public struct PointRef: Hashable, Sendable, Comparable {
    public var subpath: Int
    public var index: Int

    public init(_ subpath: Int, _ index: Int) {
        self.subpath = subpath
        self.index = index
    }

    public static func < (a: PointRef, b: PointRef) -> Bool {
        a.subpath != b.subpath ? a.subpath < b.subpath : a.index < b.index
    }
}

/// Which of a point's two handles: the one on the way in, or on the way out.
public enum HandleSide: Sendable, Hashable {
    case inHandle, outHandle

    public var other: HandleSide { self == .inHandle ? .outHandle : .inHandle }
}

/// The maths of the pen and of editing points, as Figma does them. Paths are
/// in the layer's own pixel space. Nothing here knows about the screen: the
/// canvas hands in points already carried into the layer's space.
public enum PathEditing {
    // MARK: Reading

    /// The points a shape is edited by, in its own space: a pen path as it
    /// is stored, any other shape as it is drawn at its size, but with each
    /// rounded corner one sharp point carrying its radius. Nil for layers
    /// that are not shapes.
    public static func path(of layer: Layer) -> BezierPath? {
        guard case .shape(let shape) = layer.content else { return nil }
        return shape.geometry.points(size: layer.size)
    }

    /// Whether the layer's points can be edited: shapes, not groups, text or
    /// pictures.
    public static func canEditPoints(_ layer: Layer) -> Bool {
        if case .shape = layer.content { return true }
        return false
    }

    public static func point(_ ref: PointRef, in path: BezierPath) -> PathPoint? {
        guard path.subpaths.indices.contains(ref.subpath),
              path.subpaths[ref.subpath].points.indices.contains(ref.index) else { return nil }
        return path.subpaths[ref.subpath].points[ref.index]
    }

    /// Every point, in order.
    public static func refs(in path: BezierPath) -> [PointRef] {
        path.subpaths.enumerated().flatMap { s, sub in sub.points.indices.map { PointRef(s, $0) } }
    }

    /// Whether `ref` is the first or last point of an open subpath, where the
    /// pen can carry on drawing.
    public static func isOpenEnd(_ ref: PointRef, in path: BezierPath) -> Bool {
        guard path.subpaths.indices.contains(ref.subpath) else { return false }
        let sub = path.subpaths[ref.subpath]
        return !sub.isClosed && sub.points.count > 0 && (ref.index == 0 || ref.index == sub.points.count - 1)
    }

    // MARK: Segments

    /// A segment as its four bezier points: from `ref` to the point after it.
    public struct Segment: Sendable, Equatable {
        public var p0, c1, c2, p1: Vec2

        public func point(at t: Double) -> Vec2 {
            let q = 1 - t
            let a = q * q * q, b = 3 * q * q * t, c = 3 * q * t * t, d = t * t * t
            return Vec2(a * p0.x + b * c1.x + c * c2.x + d * p1.x, a * p0.y + b * c1.y + c * c2.y + d * p1.y)
        }
    }

    /// How many segments a subpath has: one between each pair of points,
    /// and one more back to the start when it is closed.
    public static func segmentCount(_ sub: Subpath) -> Int {
        guard sub.points.count > 1 else { return 0 }
        return sub.isClosed ? sub.points.count : sub.points.count - 1
    }

    public static func segment(_ ref: PointRef, in path: BezierPath) -> Segment {
        let sub = path.subpaths[ref.subpath]
        let a = sub.points[ref.index], b = sub.points[(ref.index + 1) % sub.points.count]
        return Segment(p0: a.position, c1: a.position + a.outHandle, c2: b.position + b.inHandle, p1: b.position)
    }

    /// The segment nearest `point`, if one passes within `tolerance`: the
    /// point it starts from, how far along (0 to 1), and how far away.
    public static func nearestSegment(in path: BezierPath, to point: Vec2,
                                      tolerance: Double) -> (ref: PointRef, t: Double, distance: Double)? {
        var best: (ref: PointRef, t: Double, distance: Double)?
        for (s, sub) in path.subpaths.enumerated() {
            for i in 0..<segmentCount(sub) {
                let ref = PointRef(s, i)
                let seg = segment(ref, in: path)
                // A coarse pass along the curve, then a finer one around the
                // nearest sample.
                var bestT = 0.0, bestD = Double.infinity
                let n = 48
                for k in 0...n {
                    let t = Double(k) / Double(n)
                    let d = distance(seg.point(at: t), point)
                    if d < bestD { bestD = d; bestT = t }
                }
                var step = 1.0 / Double(n)
                for _ in 0..<12 {
                    step /= 2
                    for t in [bestT - step, bestT + step] where t >= 0 && t <= 1 {
                        let d = distance(seg.point(at: t), point)
                        if d < bestD { bestD = d; bestT = t }
                    }
                }
                if bestD <= tolerance, bestD < (best?.distance ?? .infinity) { best = (ref, bestT, bestD) }
            }
        }
        return best
    }

    /// The box the curves themselves fill, not their handles, as Figma
    /// measures a vector.
    public static func bounds(of path: BezierPath) -> Box? { path.bounds }

    // MARK: Changing points

    /// Points moved by `delta`, their handles with them.
    public static func moving(_ refs: Set<PointRef>, in path: BezierPath, by delta: Vec2) -> BezierPath {
        var path = path
        for ref in refs where point(ref, in: path) != nil {
            path.subpaths[ref.subpath].points[ref.index].position = path.subpaths[ref.subpath].points[ref.index].position + delta
        }
        return path
    }

    /// One handle set to `offset` from its point. Unless `independent`, a
    /// smooth point stays smooth: the other handle turns to stay opposite,
    /// keeping its own length, or matching this one's when the two were the
    /// same length. A corner's handles always move on their own.
    public static func settingHandle(_ side: HandleSide, of ref: PointRef, in path: BezierPath, to offset: Vec2,
                                     independent: Bool) -> BezierPath {
        guard var p = point(ref, in: path) else { return path }
        let this = side == .inHandle ? p.inHandle : p.outHandle
        let that = side == .inHandle ? p.outHandle : p.inHandle
        var partner = that
        if !independent, isSmooth(p) {
            let equal = abs(length(this) - length(that)) < 0.5
            let l = length(offset)
            let keep = equal ? l : length(that)
            partner = l > 1e-9 ? Vec2(-offset.x / l * keep, -offset.y / l * keep) : that
        }
        if side == .inHandle { p.inHandle = offset; p.outHandle = partner } else { p.outHandle = offset; p.inHandle = partner }
        var edited = path
        edited.subpaths[ref.subpath].points[ref.index] = p
        return edited
    }

    /// Both handles pulled out as mirror images, as the pen does when you
    /// drag: `out` on the way out, its opposite on the way in.
    public static func pullingHandles(of ref: PointRef, in path: BezierPath, out: Vec2) -> BezierPath {
        guard point(ref, in: path) != nil else { return path }
        var edited = path
        edited.subpaths[ref.subpath].points[ref.index].outHandle = out
        edited.subpaths[ref.subpath].points[ref.index].inHandle = Vec2(-out.x, -out.y)
        return edited
    }

    /// A point with both handles pointing opposite ways (or none at all
    /// being a corner): the curve passes through it without a kink.
    public static func isSmooth(_ p: PathPoint) -> Bool {
        let a = p.inHandle, b = p.outHandle
        let la = length(a), lb = length(b)
        guard la > 1e-6, lb > 1e-6 else { return false }
        let cross = (a.x * b.y - a.y * b.x) / (la * lb)
        let dot = (a.x * b.x + a.y * b.y) / (la * lb)
        return abs(cross) < 0.02 && dot < 0
    }

    /// A corner made smooth, or anything with handles made a sharp corner:
    /// Figma's bend tool on a click.
    public static func togglingSmooth(_ ref: PointRef, in path: BezierPath) -> BezierPath {
        guard let p = point(ref, in: path) else { return path }
        var edited = path
        if p.inHandle == .zero && p.outHandle == .zero {
            let h = autoHandles(ref, in: path)
            edited.subpaths[ref.subpath].points[ref.index].inHandle = h.inHandle
            edited.subpaths[ref.subpath].points[ref.index].outHandle = h.outHandle
        } else {
            edited.subpaths[ref.subpath].points[ref.index].inHandle = .zero
            edited.subpaths[ref.subpath].points[ref.index].outHandle = .zero
        }
        return edited
    }

    /// Handles that round a point off between its neighbours: along the line
    /// from the one before to the one after, each a third of the way to its
    /// own neighbour. An end of an open path points at its one neighbour.
    public static func autoHandles(_ ref: PointRef, in path: BezierPath) -> (inHandle: Vec2, outHandle: Vec2) {
        let sub = path.subpaths[ref.subpath]
        let n = sub.points.count
        guard n > 1 else { return (.zero, .zero) }
        let p = sub.points[ref.index].position
        let hasPrev = sub.isClosed || ref.index > 0, hasNext = sub.isClosed || ref.index < n - 1
        let prev = hasPrev ? sub.points[(ref.index + n - 1) % n].position : nil
        let next = hasNext ? sub.points[(ref.index + 1) % n].position : nil
        let a = prev ?? Vec2(2 * p.x - next!.x, 2 * p.y - next!.y)
        let b = next ?? Vec2(2 * p.x - prev!.x, 2 * p.y - prev!.y)
        let dir = b - a
        let l = length(dir)
        guard l > 1e-9 else { return (.zero, .zero) }
        let u = Vec2(dir.x / l, dir.y / l)
        let back = distance(p, a) / 3, ahead = distance(p, b) / 3
        return (hasPrev ? Vec2(-u.x * back, -u.y * back) : .zero, hasNext ? Vec2(u.x * ahead, u.y * ahead) : .zero)
    }

    /// Every sharp corner rounded off, or, when every point is round
    /// already, every point made sharp: a change of shape plain to see, for
    /// a new Path action to start from.
    public static func reshapedForNewAction(_ path: BezierPath) -> BezierPath {
        let all = refs(in: path)
        let sharp = all.filter { point($0, in: path).map { $0.inHandle == .zero && $0.outHandle == .zero } ?? false }
        var edited = path
        if sharp.isEmpty {
            for ref in all {
                edited.subpaths[ref.subpath].points[ref.index].inHandle = .zero
                edited.subpaths[ref.subpath].points[ref.index].outHandle = .zero
            }
        } else {
            for ref in sharp {
                let h = autoHandles(ref, in: path)
                edited.subpaths[ref.subpath].points[ref.index].inHandle = h.inHandle
                edited.subpaths[ref.subpath].points[ref.index].outHandle = h.outHandle
            }
        }
        return edited
    }

    /// A point added on a segment at `t` without changing the curve's shape:
    /// the segment is split in two, and the handles either side shortened to
    /// match. Returns the new point's ref.
    public static func inserting(on ref: PointRef, at t: Double, in path: BezierPath) -> (path: BezierPath, point: PointRef) {
        let seg = segment(ref, in: path)
        func lerp(_ a: Vec2, _ b: Vec2) -> Vec2 { Vec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }
        let ab = lerp(seg.p0, seg.c1), bc = lerp(seg.c1, seg.c2), cd = lerp(seg.c2, seg.p1)
        let abc = lerp(ab, bc), bcd = lerp(bc, cd), mid = lerp(abc, bcd)
        var edited = path
        var sub = edited.subpaths[ref.subpath]
        let n = sub.points.count
        let nextIndex = (ref.index + 1) % n
        let curved = sub.points[ref.index].outHandle != .zero || sub.points[nextIndex].inHandle != .zero
        if curved {
            sub.points[ref.index].outHandle = ab - seg.p0
            sub.points[nextIndex].inHandle = cd - seg.p1
        }
        let added = curved ? PathPoint(mid, inHandle: abc - mid, outHandle: bcd - mid) : PathPoint(mid)
        sub.points.insert(added, at: ref.index + 1)
        edited.subpaths[ref.subpath] = sub
        return (edited, PointRef(ref.subpath, ref.index + 1))
    }

    /// Points taken out, the path joined across each gap. A subpath left
    /// with fewer than two points goes; a closed one with two becomes open.
    public static func deleting(_ refs: Set<PointRef>, from path: BezierPath) -> BezierPath {
        var subpaths: [Subpath] = []
        for (s, sub) in path.subpaths.enumerated() {
            var kept = sub
            kept.points = sub.points.enumerated().filter { !refs.contains(PointRef(s, $0.offset)) }.map(\.element)
            if kept.points.count < 2 { continue }
            if kept.points.count == 2 { kept.isClosed = false }
            subpaths.append(kept)
        }
        return BezierPath(subpaths: subpaths)
    }

    // MARK: The pen

    /// A point added to the end of the last subpath, or a new subpath when
    /// the last one is closed or there is none.
    public static func appending(_ point: PathPoint, to path: BezierPath) -> (path: BezierPath, point: PointRef) {
        var edited = path
        if let last = edited.subpaths.indices.last, !edited.subpaths[last].isClosed {
            edited.subpaths[last].points.append(point)
            return (edited, PointRef(last, edited.subpaths[last].points.count - 1))
        }
        edited.subpaths.append(Subpath(points: [point], isClosed: false))
        return (edited, PointRef(edited.subpaths.count - 1, 0))
    }

    /// An open subpath turned round and moved last, so the pen carries on
    /// from `ref`'s end by appending. Returns where that end now is.
    public static func continuing(from ref: PointRef, in path: BezierPath) -> (path: BezierPath, end: PointRef) {
        guard isOpenEnd(ref, in: path) else { return (path, ref) }
        var edited = path
        var sub = edited.subpaths.remove(at: ref.subpath)
        if ref.index == 0 && sub.points.count > 1 {
            sub.points = sub.points.reversed().map(\.reversed)
        }
        edited.subpaths.append(sub)
        return (edited, PointRef(edited.subpaths.count - 1, sub.points.count - 1))
    }

    /// The last subpath closed. When the pen closes onto another open
    /// subpath's end instead, the two are joined first.
    public static func closing(_ path: BezierPath, onto ref: PointRef) -> BezierPath {
        guard let last = path.subpaths.indices.last else { return path }
        var edited = path
        if ref.subpath == last {
            edited.subpaths[last].isClosed = true
            return edited
        }
        guard isOpenEnd(ref, in: path) else { return path }
        // Joining onto another open subpath: it follows on from the pen's
        // end, turned so the end the pen reached comes first.
        var other = edited.subpaths[ref.subpath]
        if ref.index != 0 {
            other.points = other.points.reversed().map(\.reversed)
        }
        edited.subpaths[last].points += other.points
        edited.subpaths.remove(at: ref.subpath)
        return edited
    }

    // MARK: The layer

    /// The layer drawn with `path` instead, its box refitted to the curves:
    /// the path moved so its bounds start at the box's top-left, the anchor
    /// kept at the same fraction of the box, and the position moved so
    /// nothing shifts on screen. `shift` is how far the points moved in the
    /// layer's own space, which the layer's Path actions must follow.
    public static func reshaped(_ layer: Layer, to path: BezierPath) -> (layer: Layer, shift: Vec2) {
        let box = bounds(of: path) ?? Box(minX: 0, minY: 0, maxX: 0, maxY: 0)
        let origin = Vec2(box.minX, box.minY)
        let size = Size2(box.width, box.height)
        let t = layer.transform
        let fraction = Vec2(layer.size.width > 0 ? t.anchor.x / layer.size.width : 0.5,
                            layer.size.height > 0 ? t.anchor.y / layer.size.height : 0.5)
        let anchor = Vec2(fraction.x * size.width, fraction.y * size.height)
        let old = Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
        var edited = layer
        edited.transform.anchor = anchor
        edited.transform.position = old.apply(origin + anchor)
        edited.size = size
        if case .shape(var shape) = layer.content {
            shape.geometry = .path(translated(path, by: Vec2(-origin.x, -origin.y)))
            edited.content = .shape(shape)
        }
        return (edited, Vec2(-origin.x, -origin.y))
    }

    /// The same, with the layer's Path actions moved to match, so their
    /// shapes stay where they were drawn. A path is drawn stretched from its
    /// points' bounds onto the layer's box, which a resize leaves different;
    /// the actions' points are carried through that stretch as well.
    public static func reshaped(_ layer: Layer, to path: BezierPath, actions: [Action]) -> (layer: Layer, actions: [Action]) {
        let (edited, shift) = reshaped(layer, to: path)
        var stored: BezierPath?
        if case .shape(let shape) = layer.content, case .path(let p) = shape.geometry { stored = p }
        let fit = stored.map { p in { (q: BezierPath) in q.fitted(from: p.bounds, to: layer.size) } }
        guard shift != .zero || stored.map({ $0.fitted(from: $0.bounds, to: layer.size) != $0 }) == true else { return (edited, []) }
        let moved = actions.compactMap { action -> Action? in
            guard action.targetLayerID == layer.id, case .path(var p) = action.spec else { return nil }
            p.end = translated(fit?(p.end) ?? p.end, by: shift)
            p.initial = p.initial.map { translated(fit?($0) ?? $0, by: shift) }
            var a = action
            a.spec = .path(p)
            return a
        }
        return (edited, moved)
    }

    /// A new pen path of one point at `point` in its parent's space, styled
    /// as a line until it is closed.
    public static func newPath(at point: Vec2, name: String) -> Layer {
        var layer = LayerFactory.shape(.line, in: Box(origin: point, size: Size2(0, 0)), name: name)
        if case .shape(var shape) = layer.content {
            shape.geometry = .path(BezierPath(subpaths: [Subpath(points: [PathPoint(.zero)], isClosed: false)]))
            layer.content = .shape(shape)
        }
        layer.transform.position = point
        layer.transform.anchor = .zero
        return layer
    }

    /// A shape still wearing the new-line look (one default stroke, no fill)
    /// takes the new-shape look once its path is closed: the default fill
    /// and no stroke. A shape the user has styled keeps its style.
    public static func styledForClosing(_ layer: Layer) -> Layer {
        guard case .shape(var shape) = layer.content, shape.fills.isEmpty, shape.strokes.count == 1,
              isUntouchedLineStroke(shape.strokes[0])
        else { return layer }
        shape.strokes = []
        shape.fills = [Fill(paint: .color(LayerFactory.defaultFill))]
        var edited = layer
        edited.content = .shape(shape)
        return edited
    }

    /// The stroke a new path starts with, whatever its id.
    private static func isUntouchedLineStroke(_ stroke: Stroke) -> Bool {
        var same = LayerFactory.lineStroke
        same = Stroke(id: stroke.id, isEnabled: same.isEnabled, paint: same.paint, width: same.width, alignment: same.alignment,
                      cap: same.cap, join: same.join, dashPattern: same.dashPattern, dashOffset: same.dashOffset)
        return stroke == same
    }

    public static func translated(_ path: BezierPath, by delta: Vec2) -> BezierPath {
        guard delta != .zero else { return path }
        return BezierPath(subpaths: path.subpaths.map { sub in
            Subpath(points: sub.points.map { PathPoint($0.position + delta, inHandle: $0.inHandle, outHandle: $0.outHandle, cornerRadius: $0.cornerRadius) },
                    isClosed: sub.isClosed)
        })
    }

    // MARK: Small maths

    static func length(_ v: Vec2) -> Double { hypot(v.x, v.y) }
    static func distance(_ a: Vec2, _ b: Vec2) -> Double { hypot(a.x - b.x, a.y - b.y) }
}
