import Foundation
import MotionModel

/// Every shape kind as a plain bezier path in the layer's own pixel space, so
/// a renderer only ever has to draw paths.
enum ShapePaths {
    /// The handle length that makes a cubic bezier approximate a quarter circle.
    static let kappa = 0.5522847498

    static func rectangle(_ size: Size2, radii: CornerRadii) -> BezierPath {
        let w = max(size.width, 0), h = max(size.height, 0)
        // A radius larger than half the shorter side would fold back on itself.
        let limit = min(w, h) / 2
        let tl = min(max(radii.topLeft, 0), limit), tr = min(max(radii.topRight, 0), limit)
        let br = min(max(radii.bottomRight, 0), limit), bl = min(max(radii.bottomLeft, 0), limit)
        var points: [PathPoint] = []

        func corner(_ p: Vec2, radius r: Double, inDir: Vec2, outDir: Vec2) {
            // `inDir` points back along the incoming edge, `outDir` along the outgoing one.
            guard r > 0 else {
                points.append(PathPoint(p))
                return
            }
            let start = Vec2(p.x + inDir.x * r, p.y + inDir.y * r)
            let end = Vec2(p.x + outDir.x * r, p.y + outDir.y * r)
            let k = r * kappa
            points.append(PathPoint(start, outHandle: Vec2(-inDir.x * k, -inDir.y * k)))
            points.append(PathPoint(end, inHandle: Vec2(-outDir.x * k, -outDir.y * k)))
        }

        corner(Vec2(0, 0), radius: tl, inDir: Vec2(0, 1), outDir: Vec2(1, 0))
        corner(Vec2(w, 0), radius: tr, inDir: Vec2(-1, 0), outDir: Vec2(0, 1))
        corner(Vec2(w, h), radius: br, inDir: Vec2(0, -1), outDir: Vec2(-1, 0))
        corner(Vec2(0, h), radius: bl, inDir: Vec2(1, 0), outDir: Vec2(0, -1))
        return BezierPath(subpaths: [Subpath(points: points, isClosed: true)])
    }

    static func ellipse(_ size: Size2) -> BezierPath {
        let rx = size.width / 2, ry = size.height / 2
        let kx = rx * kappa, ky = ry * kappa
        let c = Vec2(rx, ry)
        let points = [
            PathPoint(Vec2(c.x, 0), inHandle: Vec2(-kx, 0), outHandle: Vec2(kx, 0)),
            PathPoint(Vec2(size.width, c.y), inHandle: Vec2(0, -ky), outHandle: Vec2(0, ky)),
            PathPoint(Vec2(c.x, size.height), inHandle: Vec2(kx, 0), outHandle: Vec2(-kx, 0)),
            PathPoint(Vec2(0, c.y), inHandle: Vec2(0, ky), outHandle: Vec2(0, -ky)),
        ]
        return BezierPath(subpaths: [Subpath(points: points, isClosed: true)])
    }

    /// An ellipse, or a slice or ring of one. The slice runs clockwise from
    /// `arc.start` to `arc.end`, in degrees from three o'clock. A hole makes
    /// the inner edge a smaller copy of the outer one; with no hole, a slice
    /// is a pie wedge to the centre.
    static func ellipse(_ size: Size2, arc: EllipseArc) -> BezierPath {
        let inner = min(max(arc.innerRadius, 0), 0.999)
        if arc.isWhole {
            guard inner > 0 else { return ellipse(size) }
            // A ring: the outer ellipse clockwise, the inner one the other way
            // round, so the middle is left empty.
            let outer = ellipse(size).subpaths[0]
            let w = size.width * inner, h = size.height * inner
            let hole = ellipse(Size2(w, h)).subpaths[0]
            let offset = Vec2((size.width - w) / 2, (size.height - h) / 2)
            let reversed = hole.points.reversed().map { p in
                PathPoint(p.position + offset, inHandle: p.outHandle, outHandle: p.inHandle)
            }
            return BezierPath(subpaths: [outer, Subpath(points: Array(reversed), isClosed: true)])
        }
        let rx = size.width / 2, ry = size.height / 2
        let center = Vec2(rx, ry)
        var sweep = (arc.end - arc.start).truncatingRemainder(dividingBy: 360)
        if sweep < 0 { sweep += 360 }
        var points = arcPoints(center: center, rx: rx, ry: ry, from: arc.start, sweep: sweep)
        if inner > 0 {
            let back = arcPoints(center: center, rx: rx * inner, ry: ry * inner, from: arc.start + sweep, sweep: -sweep)
            points += back
        } else {
            points.append(PathPoint(center))
        }
        return BezierPath(subpaths: [Subpath(points: points, isClosed: true)])
    }

    /// Points along an elliptical arc, in cubic pieces of at most 90° each.
    private static func arcPoints(center: Vec2, rx: Double, ry: Double, from start: Double, sweep: Double) -> [PathPoint] {
        let pieces = max(1, Int((abs(sweep) / 90).rounded(.up)))
        let step = sweep / Double(pieces) * .pi / 180
        let k = 4.0 / 3.0 * tan(step / 4)
        var points: [PathPoint] = []
        for i in 0...pieces {
            let a = start * .pi / 180 + Double(i) * step
            let p = Vec2(center.x + cos(a) * rx, center.y + sin(a) * ry)
            // The tangent, scaled to the handle length for this piece.
            let tangent = Vec2(-sin(a) * rx * k, cos(a) * ry * k)
            points.append(PathPoint(p, inHandle: i == 0 ? .zero : Vec2(-tangent.x, -tangent.y),
                                    outHandle: i == pieces ? .zero : tangent))
        }
        return points
    }

    static func line(_ size: Size2) -> BezierPath {
        BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, size.height / 2)),
                                               PathPoint(Vec2(size.width, size.height / 2))],
                                      isClosed: false)])
    }

    /// Corners evenly round the box's inscribed ellipse, the first straight
    /// up, each to be rounded by `cornerRadius`.
    static func polygonPoints(_ size: Size2, sides: Int, cornerRadius: Double = 0) -> BezierPath {
        let n = FileSafety.corners(sides)
        return closed(size, count: n, cornerRadius: cornerRadius) { _ in 1 }
    }

    static func polygon(_ size: Size2, sides: Int, cornerRadius: Double = 0) -> BezierPath {
        polygonPoints(size, sides: sides, cornerRadius: cornerRadius).roundingCorners()
    }

    static func starPoints(_ size: Size2, points: Int, innerRadius: Double, cornerRadius: Double = 0) -> BezierPath {
        let n = FileSafety.corners(points)
        return closed(size, count: n * 2, cornerRadius: cornerRadius) { $0.isMultiple(of: 2) ? 1 : max(innerRadius, 0) }
    }

    static func star(_ size: Size2, points: Int, innerRadius: Double, cornerRadius: Double = 0) -> BezierPath {
        starPoints(size, points: points, innerRadius: innerRadius, cornerRadius: cornerRadius).roundingCorners()
    }

    /// A rectangle's four corners, sharp, each carrying its radius: the
    /// points it is edited by.
    static func rectanglePoints(_ size: Size2, radii: CornerRadii) -> BezierPath {
        let w = max(size.width, 0), h = max(size.height, 0)
        return BezierPath(subpaths: [Subpath(points: [
            PathPoint(Vec2(0, 0), cornerRadius: radii.topLeft),
            PathPoint(Vec2(w, 0), cornerRadius: radii.topRight),
            PathPoint(Vec2(w, h), cornerRadius: radii.bottomRight),
            PathPoint(Vec2(0, h), cornerRadius: radii.bottomLeft),
        ], isClosed: true)])
    }

    private static func closed(_ size: Size2, count: Int, cornerRadius: Double, radius: (Int) -> Double) -> BezierPath {
        let rx = size.width / 2, ry = size.height / 2
        let points = (0..<count).map { i -> PathPoint in
            let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(count)
            let r = radius(i)
            return PathPoint(Vec2(rx + cos(angle) * rx * r, ry + sin(angle) * ry * r), cornerRadius: cornerRadius)
        }
        return BezierPath(subpaths: [Subpath(points: points, isClosed: true)])
    }
}
