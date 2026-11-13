import Foundation
import CoreGraphics
import MotionModel
import MotionEvaluation

/// A flat transform in the pieces a Lottie layer's transform is made of.
/// Lottie scales, then slants, then turns, then moves (its anchor kept at
/// the origin here), so any flat transform is one of these: the turn is the
/// direction the layer's x axis points, the x scale its length, and what is
/// left over is the y scale and a slant of x by y.
struct LottieTransform: Equatable {
    var position: Vec2
    /// Percent, as Lottie has it.
    var scale: Vec2
    /// Degrees, clockwise.
    var rotation: Double
    /// Degrees, Lottie's skew along its own axis at 0°: positive moves the
    /// bottom of the layer left.
    var skew: Double

    /// `previousRotation` keeps the turn from jumping a whole turn between
    /// frames where the angle wraps, and stands in when the layer is
    /// squashed to nothing and has no direction of its own.
    init(_ t: Affine, previousRotation: Double? = nil) {
        position = Vec2(t.tx, t.ty)
        let sx = hypot(t.a, t.b)
        var angle: Double
        if sx > 1e-12 {
            angle = atan2(t.b, t.a) * 180 / .pi
        } else {
            angle = previousRotation ?? 0
        }
        if let previous = previousRotation {
            angle += ((previous - angle) / 360).rounded() * 360
        }
        let r = angle * .pi / 180
        let cs = cos(r), sn = sin(r)
        // The turn undone from the y axis's column: what scale and slant
        // left of it.
        let sy = -sn * t.c + cs * t.d
        let shear = cs * t.c + sn * t.d
        let k = abs(sy) > 1e-12 ? shear / sy : 0
        scale = Vec2(sx * 100, sy * 100)
        rotation = angle
        skew = -atan(k) * 180 / .pi
        if sx <= 1e-12 { scale.x = 0 }
    }

    /// The transform these pieces make, as Lottie builds it.
    var affine: Affine {
        let k = -tan(skew * .pi / 180)
        let slant = Affine(a: 1, b: 0, c: k, d: 1, tx: 0, ty: 0)
        return Affine.scale(Vec2(scale.x / 100, scale.y / 100)).then(slant)
            .then(.rotation(degrees: rotation)).then(.translation(position))
    }
}

enum LottieGeometry {
    /// The flat transform nearest `p` over a box of `size`: `p` itself when
    /// it is flat, otherwise the one through the middle of the box that
    /// best matches its four corners as `p` places them. A tilted or 3D
    /// layer is drawn flat in a Lottie, as near to where it is seen as a
    /// flat layer can be. Nil when any corner is behind the viewer.
    static func flat(_ p: Projective, over size: Size2) -> Affine? {
        if p.isAffine { return p.affine }
        let w = max(size.width, 1), h = max(size.height, 1)
        guard let p0 = p.apply(Vec2(0, 0)), let p1 = p.apply(Vec2(w, 0)),
              let p2 = p.apply(Vec2(w, h)), let p3 = p.apply(Vec2(0, h)) else { return nil }
        // Least squares over a rectangle's corners comes out in closed form.
        let ax = ((p1.x + p2.x) - (p0.x + p3.x)) / (2 * w), bx = ((p1.y + p2.y) - (p0.y + p3.y)) / (2 * w)
        let cx = ((p2.x + p3.x) - (p0.x + p1.x)) / (2 * h), dx = ((p2.y + p3.y) - (p0.y + p1.y)) / (2 * h)
        let mx = (p0.x + p1.x + p2.x + p3.x) / 4, my = (p0.y + p1.y + p2.y + p3.y) / 4
        return Affine(a: ax, b: bx, c: cx, d: dx,
                      tx: mx - ax * w / 2 - cx * h / 2, ty: my - bx * w / 2 - dx * h / 2)
    }

    /// `path` moved by `t`, handles and all.
    static func transformed(_ path: BezierPath, by t: Affine) -> BezierPath {
        BezierPath(subpaths: path.subpaths.map { sub in
            Subpath(points: sub.points.map { point in
                PathPoint(t.apply(point.position), inHandle: t.applyToVector(point.inHandle),
                          outHandle: t.applyToVector(point.outHandle))
            }, isClosed: sub.isClosed)
        })
    }

    static func rectangle(_ box: Box) -> BezierPath {
        BezierPath(subpaths: [Subpath(points: box.corners.map { PathPoint($0) }, isClosed: true)])
    }

    /// A subpath's numbers, six to a point (where, in handle, out handle),
    /// and what shape they are, for a `Series`.
    static func numbers(_ sub: Subpath?) -> (values: [Double], shape: Int) {
        guard let sub else { return ([], 0) }
        var out: [Double] = []
        out.reserveCapacity(sub.points.count * 6)
        for p in sub.points {
            out += [p.position.x, p.position.y, p.inHandle.x, p.inHandle.y, p.outHandle.x, p.outHandle.y]
        }
        return (out, sub.points.count * 2 + (sub.isClosed ? 1 : 0) + 1)
    }

    /// The same subpath at every frame with one number of points and
    /// either always closed or always open, as Lottie players need: they
    /// keep the first keyframe's count of points (lottie-web draws nothing
    /// otherwise). A closed path among open ones is opened with its closing
    /// stretch drawn as one more point on its first; shorter ones repeat
    /// their last point where it is, handles moved to the last repeat so
    /// the curve is unchanged; a frame without the subpath has every point
    /// at the first point it has anywhere, which draws nothing.
    static func uniform(_ paths: [Subpath?]) -> (paths: [Subpath], closed: Bool) {
        let present = paths.compactMap { $0 }.filter { !$0.points.isEmpty }
        guard let seed = present.first?.points.first?.position else {
            return (paths.map { _ in Subpath(points: [], isClosed: false) }, false)
        }
        let closed = present.allSatisfy(\.isClosed)
        let opened: [[PathPoint]] = paths.map { sub in
            guard let sub, !sub.points.isEmpty else { return [] }
            guard sub.isClosed, !closed, let first = sub.points.first else { return sub.points }
            var points = sub.points
            points[0].inHandle = .zero
            points.append(PathPoint(first.position, inHandle: first.inHandle))
            return points
        }
        let count = opened.map(\.count).max() ?? 0
        let made = opened.map { points -> Subpath in
            guard var last = points.last else {
                return Subpath(points: Array(repeating: PathPoint(seed), count: count), isClosed: closed)
            }
            guard points.count < count else { return Subpath(points: points, isClosed: closed) }
            var out = points
            let out0 = last.outHandle
            out[out.count - 1].outHandle = .zero
            last = PathPoint(last.position)
            out += Array(repeating: last, count: count - points.count)
            out[out.count - 1].outHandle = out0
            return Subpath(points: out, isClosed: closed)
        }
        return (made, closed)
    }

    /// A subpath's numbers back as a Lottie path: `v` the points, `i` and
    /// `o` their handles, as offsets from them, as Twine keeps them too.
    static func lottiePath(_ values: [Double], closed: Bool) -> LottieJSON {
        var v: [LottieJSON] = [], i: [LottieJSON] = [], o: [LottieJSON] = []
        var k = 0
        while k + 5 < values.count {
            v.append(.numbers([values[k], values[k + 1]]))
            i.append(.numbers([values[k + 2], values[k + 3]]))
            o.append(.numbers([values[k + 4], values[k + 5]]))
            k += 6
        }
        return .object([("i", .array(i)), ("o", .array(o)), ("v", .array(v)), ("c", .bool(closed))])
    }

    /// A Core Graphics path (glyph outlines, y down already) as a Twine one.
    /// Quadratic curves become cubic ones, and a contour that closes on its
    /// own first point drops the repeat.
    static func bezierPath(_ path: CGPath) -> BezierPath {
        var subpaths: [Subpath] = []
        var points: [PathPoint] = []
        func finish(closed: Bool) {
            guard !points.isEmpty else { return }
            if closed, points.count > 1, let first = points.first, let last = points.last,
               hypot(first.position.x - last.position.x, first.position.y - last.position.y) < 1e-6 {
                points[0].inHandle = last.inHandle
                points.removeLast()
            }
            subpaths.append(Subpath(points: points, isClosed: closed))
            points = []
        }
        path.applyWithBlock { element in
            let e = element.pointee
            func at(_ i: Int) -> Vec2 { Vec2(Double(e.points[i].x), Double(e.points[i].y)) }
            switch e.type {
            case .moveToPoint:
                finish(closed: false)
                points.append(PathPoint(at(0)))
            case .addLineToPoint:
                points.append(PathPoint(at(0)))
            case .addQuadCurveToPoint:
                guard let last = points.last else { return }
                let q = at(0), end = at(1), from = last.position
                let c1 = Vec2(from.x + (q.x - from.x) * 2 / 3, from.y + (q.y - from.y) * 2 / 3)
                let c2 = Vec2(end.x + (q.x - end.x) * 2 / 3, end.y + (q.y - end.y) * 2 / 3)
                points[points.count - 1].outHandle = Vec2(c1.x - from.x, c1.y - from.y)
                points.append(PathPoint(end, inHandle: Vec2(c2.x - end.x, c2.y - end.y)))
            case .addCurveToPoint:
                guard let last = points.last else { return }
                let c1 = at(0), c2 = at(1), end = at(2), from = last.position
                points[points.count - 1].outHandle = Vec2(c1.x - from.x, c1.y - from.y)
                points.append(PathPoint(end, inHandle: Vec2(c2.x - end.x, c2.y - end.y)))
            case .closeSubpath:
                finish(closed: true)
            @unknown default:
                break
            }
        }
        finish(closed: false)
        return BezierPath(subpaths: subpaths)
    }
}
