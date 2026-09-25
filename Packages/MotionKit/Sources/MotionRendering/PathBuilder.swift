import CoreGraphics
import MotionModel

extension BezierPath {
    /// The path as Core Graphics draws it. A segment whose handles are both
    /// zero is a straight line; anything else is a cubic curve.
    public var cgPath: CGPath {
        let path = CGMutablePath()
        for subpath in subpaths {
            guard let first = subpath.points.first else { continue }
            path.move(to: first.position.cg)
            var previous = first
            for point in subpath.points.dropFirst() {
                segment(from: previous, to: point, in: path)
                previous = point
            }
            if subpath.isClosed {
                segment(from: previous, to: first, in: path)
                path.closeSubpath()
            }
        }
        return path
    }

    private func segment(from a: PathPoint, to b: PathPoint, in path: CGMutablePath) {
        if a.outHandle == .zero && b.inHandle == .zero {
            path.addLine(to: b.position.cg)
        } else {
            path.addCurve(to: b.position.cg,
                          control1: CGPoint(x: a.position.x + a.outHandle.x, y: a.position.y + a.outHandle.y),
                          control2: CGPoint(x: b.position.x + b.inHandle.x, y: b.position.y + b.inHandle.y))
        }
    }
}

extension Vec2 {
    public var cg: CGPoint { CGPoint(x: x, y: y) }
}

extension Size2 {
    public var cg: CGSize { CGSize(width: width, height: height) }
}

extension RGBA {
    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
    }
}
