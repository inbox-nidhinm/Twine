import Foundation
import MotionModel

/// The stretches of a path a trim shows, cut out by length along the path
/// (all its subpaths end to end, as Core Animation measures a trim), each
/// as an open subpath. A stroke is drawn from these rather than with Core
/// Animation's own start and end, since a trim from both ends shows two
/// stretches, and dashes that travel the way the trim draws need each
/// stretch to run from where it starts growing.
public enum PathTrim {
    /// `path` as `trim` shows it, with where along the dash pattern each
    /// subpath starts (`starts`, one per subpath). `growing` turns each
    /// stretch to run from where it starts towards its growing tip, with the
    /// pattern laid from there; otherwise every stretch runs the path's own
    /// way with the pattern laid from the path's start, so dashes stay where
    /// they were as the trim moves. A trim that shows the whole path its own
    /// way is the path itself, closed subpaths and all.
    public static func trimmed(_ path: BezierPath, _ trim: TrimRange,
                               growing: Bool) -> (path: BezierPath, starts: [Double]) {
        let pieces = trim.pieces
        if pieces.count == 1, pieces[0].start <= 1e-9, pieces[0].end >= 1 - 1e-9 {
            let whole = growing && !pieces[0].forward ? reversed(path) : path
            return (whole, Array(repeating: 0, count: whole.subpaths.count))
        }
        let segments = Self.segments(of: path)
        let total = segments.reduce(0) { $0 + $1.length }
        guard total > 0 else { return (BezierPath(), []) }
        var subpaths: [Subpath] = []
        var starts: [Double] = []
        for piece in pieces where piece.end - piece.start > 1e-9 {
            var cut = stretch(segments, from: piece.start * total, to: piece.end * total)
            if growing {
                if !piece.forward { cut = cut.reversed().map { (reversed($0.subpath), $0.length, $0.at) } }
                // Laid from the stretch's own start, run on across subpaths.
                var along = 0.0
                for c in cut { starts.append(along); along += c.length }
            } else {
                starts += cut.map(\.at)
            }
            subpaths += cut.map(\.subpath)
        }
        return (BezierPath(subpaths: subpaths), starts)
    }

    /// The path run the other way: its subpaths in the opposite order, each
    /// from its last point to its first.
    public static func reversed(_ path: BezierPath) -> BezierPath {
        BezierPath(subpaths: path.subpaths.reversed().map(reversed))
    }

    private static func reversed(_ subpath: Subpath) -> Subpath {
        Subpath(points: subpath.points.reversed().map(\.reversed),
                isClosed: subpath.isClosed)
    }

    // MARK: Measuring

    /// One cubic of the path, with its length and the length reached at
    /// each of `samples` even steps of its parameter.
    private struct Segment {
        let p0, p1, p2, p3: Vec2
        let subpath: Int
        let lengths: [Double]
        /// A line with no handles, measured exactly: its parameter runs
        /// evenly along it.
        let straight: Bool
        var length: Double { lengths.last ?? 0 }
    }

    private static let samples = 16

    private static func segments(of path: BezierPath) -> [Segment] {
        var out: [Segment] = []
        for (index, subpath) in path.subpaths.enumerated() {
            let points = subpath.points
            guard points.count > 1 else { continue }
            var pairs = zip(points, points.dropFirst()).map { ($0, $1) }
            if subpath.isClosed, let last = points.last, let first = points.first { pairs.append((last, first)) }
            for (a, b) in pairs {
                let p0 = a.position, p3 = b.position
                if a.outHandle == .zero && b.inHandle == .zero {
                    // Handles on the line's thirds, so the parameter runs evenly.
                    let third = Vec2((p3.x - p0.x) / 3, (p3.y - p0.y) / 3)
                    out.append(Segment(p0: p0, p1: p0 + third, p2: p3 - third, p3: p3, subpath: index,
                                       lengths: [0, hypot(p3.x - p0.x, p3.y - p0.y)], straight: true))
                    continue
                }
                let p1 = a.position + a.outHandle, p2 = b.position + b.inHandle
                var lengths = [0.0]
                var previous = p0
                for k in 1...samples {
                    let point = cubic(p0, p1, p2, p3, Double(k) / Double(samples))
                    lengths.append(lengths[k - 1] + hypot(point.x - previous.x, point.y - previous.y))
                    previous = point
                }
                out.append(Segment(p0: p0, p1: p1, p2: p2, p3: p3, subpath: index, lengths: lengths, straight: false))
            }
        }
        return out
    }

    /// The parameter at `distance` along a segment.
    private static func parameter(_ s: Segment, at distance: Double) -> Double {
        guard s.length > 0 else { return 0 }
        let d = min(max(distance, 0), s.length)
        if s.straight { return d / s.length }
        var k = 1
        while k < samples, s.lengths[k] < d { k += 1 }
        let lo = s.lengths[k - 1], hi = s.lengths[k]
        let f = hi > lo ? (d - lo) / (hi - lo) : 0
        return (Double(k - 1) + f) / Double(samples)
    }

    // MARK: Cutting

    /// The path from `from` to `to` pixels along it, a subpath for each
    /// subpath it crosses, with its length and how far along the path it
    /// starts.
    private static func stretch(_ segments: [Segment], from: Double,
                                to: Double) -> [(subpath: Subpath, length: Double, at: Double)] {
        var runs: [(subpath: Int, curves: [[Vec2]], length: Double, at: Double)] = []
        var at = 0.0
        for s in segments {
            defer { at += s.length }
            let start = max(from, at), end = min(to, at + s.length)
            guard end > start else { continue }
            let t0 = parameter(s, at: start - at), t1 = parameter(s, at: end - at)
            let curve = part(s, t0, t1)
            if let last = runs.last, last.subpath == s.subpath {
                runs[runs.count - 1].curves.append(curve)
                runs[runs.count - 1].length += end - start
            } else {
                runs.append((s.subpath, [curve], end - start, start))
            }
        }
        return runs.map { run in
            var points = [PathPoint(run.curves[0][0], outHandle: run.curves[0][1] - run.curves[0][0])]
            for (i, c) in run.curves.enumerated() {
                let next = i + 1 < run.curves.count ? run.curves[i + 1] : nil
                points.append(PathPoint(c[3], inHandle: c[2] - c[3], outHandle: next.map { $0[1] - $0[0] } ?? .zero))
            }
            return (Subpath(points: points, isClosed: false), run.length, run.at)
        }
    }

    /// A segment's curve between two of its parameters, as four points.
    private static func part(_ s: Segment, _ t0: Double, _ t1: Double) -> [Vec2] {
        // Up to t1, then the stretch of that from t0.
        let left = split(s.p0, s.p1, s.p2, s.p3, at: t1).left
        let u = t1 > 0 ? t0 / t1 : 0
        let curve = split(left[0], left[1], left[2], left[3], at: u).right
        // A line's piece stays a line, with no handles.
        return s.straight ? [curve[0], curve[0], curve[3], curve[3]] : curve
    }

    private static func split(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, at t: Double) -> (left: [Vec2], right: [Vec2]) {
        func mix(_ a: Vec2, _ b: Vec2) -> Vec2 { Vec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }
        let a = mix(p0, p1), b = mix(p1, p2), c = mix(p2, p3)
        let d = mix(a, b), e = mix(b, c)
        let m = mix(d, e)
        return ([p0, a, d, m], [m, e, c, p3])
    }

    private static func cubic(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, _ t: Double) -> Vec2 {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return Vec2(a * p0.x + b * p1.x + c * p2.x + d * p3.x, a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }
}
