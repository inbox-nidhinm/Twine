import CoreGraphics
import MotionModel
import MotionEvaluation

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

extension ResolvedStroke {
    /// What a trimmed stroke draws: the stretches its trim shows, each cut
    /// into its dashes from its own place in the pattern (Core Animation
    /// would start the pattern afresh at every stretch). Nil for a stroke
    /// of the whole path, which is drawn from the shape's own path with
    /// the layer's own dashes.
    public var drawnPath: CGPath? {
        guard let trimmed else { return nil }
        let period = dashPattern.reduce(0, +)
        guard period > 0 else { return trimmed.cgPath }
        let lengths = dashPattern.map { CGFloat($0) }
        let out = CGMutablePath()
        for (i, subpath) in trimmed.subpaths.enumerated() {
            var phase = (dashOffset + (i < dashStarts.count ? dashStarts[i] : 0)).truncatingRemainder(dividingBy: period)
            if phase < 0 { phase += period }
            out.addPath(BezierPath(subpaths: [subpath]).cgPath.copy(dashingWithPhase: phase, lengths: lengths))
        }
        return out
    }
}
