import Foundation
import MotionModel

/// A 2D affine transform, laid out like `CGAffineTransform` but kept free of
/// Core Graphics so evaluation stays renderer-neutral:
///
///     x' = a·x + c·y + tx
///     y' = b·x + d·y + ty
///
/// In composition space (y down) a positive rotation turns clockwise.
public struct Affine: Sendable, Equatable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = Affine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ v: Vec2) -> Affine { Affine(a: 1, b: 0, c: 0, d: 1, tx: v.x, ty: v.y) }
    public static func scale(_ v: Vec2) -> Affine { Affine(a: v.x, b: 0, c: 0, d: v.y, tx: 0, ty: 0) }
    public static func rotation(degrees: Double) -> Affine {
        let r = degrees * .pi / 180
        return Affine(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), tx: 0, ty: 0)
    }

    /// A layer's own transform: from its local space (origin at its top-left)
    /// into its parent's. Scale and rotation happen about the anchor, and the
    /// anchor lands on the position.
    public static func layer(position: Vec2, anchor: Vec2, scale: Vec2, rotation: Double) -> Affine {
        Affine.translation(Vec2(-anchor.x, -anchor.y))
            .then(.scale(scale))
            .then(.rotation(degrees: rotation))
            .then(.translation(position))
    }

    /// This transform followed by `next`.
    public func then(_ next: Affine) -> Affine {
        Affine(a: a * next.a + b * next.c,
               b: a * next.b + b * next.d,
               c: c * next.a + d * next.c,
               d: c * next.b + d * next.d,
               tx: tx * next.a + ty * next.c + next.tx,
               ty: tx * next.b + ty * next.d + next.ty)
    }

    public func apply(_ p: Vec2) -> Vec2 {
        Vec2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }

    /// Applies only the linear part, for moving a vector rather than a point.
    public func applyToVector(_ v: Vec2) -> Vec2 {
        Vec2(a * v.x + c * v.y, b * v.x + d * v.y)
    }

    public var determinant: Double { a * d - b * c }

    /// Nil when the transform collapses space, such as a scale of zero.
    public var inverted: Affine? {
        let det = determinant
        guard abs(det) > 1e-12 else { return nil }
        return Affine(a: d / det, b: -b / det, c: -c / det, d: a / det,
                      tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

/// An axis-aligned rectangle in pixels.
public struct Box: Sendable, Equatable {
    public var minX, minY, maxX, maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(origin: Vec2, size: Size2) {
        self.init(minX: origin.x, minY: origin.y, maxX: origin.x + size.width, maxY: origin.y + size.height)
    }

    /// The smallest box around a set of points.
    public init?(around points: [Vec2]) {
        guard let first = points.first else { return nil }
        var box = Box(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points.dropFirst() { box = box.including(p) }
        self = box
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }
    public var corners: [Vec2] { [Vec2(minX, minY), Vec2(maxX, minY), Vec2(maxX, maxY), Vec2(minX, maxY)] }

    public func including(_ p: Vec2) -> Box {
        Box(minX: min(minX, p.x), minY: min(minY, p.y), maxX: max(maxX, p.x), maxY: max(maxY, p.y))
    }

    public func union(_ other: Box) -> Box {
        Box(minX: min(minX, other.minX), minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }

    public func contains(_ p: Vec2) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }

    public func intersects(_ other: Box) -> Bool {
        minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
    }
}
