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

    static func line(_ size: Size2) -> BezierPath {
        BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, size.height / 2)),
                                               PathPoint(Vec2(size.width, size.height / 2))],
                                      isClosed: false)])
    }

    /// Corners evenly round the box's inscribed ellipse, the first straight up.
    static func polygon(_ size: Size2, sides: Int) -> BezierPath {
        let n = max(sides, 3)
        return closed(size, count: n) { _ in 1 }
    }

    static func star(_ size: Size2, points: Int, innerRadius: Double) -> BezierPath {
        let n = max(points, 3)
        return closed(size, count: n * 2) { $0.isMultiple(of: 2) ? 1 : max(innerRadius, 0) }
    }

    private static func closed(_ size: Size2, count: Int, radius: (Int) -> Double) -> BezierPath {
        let rx = size.width / 2, ry = size.height / 2
        let points = (0..<count).map { i -> PathPoint in
            let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(count)
            let r = radius(i)
            return PathPoint(Vec2(rx + cos(angle) * rx * r, ry + sin(angle) * ry * r))
        }
        return BezierPath(subpaths: [Subpath(points: points, isClosed: true)])
    }
}
