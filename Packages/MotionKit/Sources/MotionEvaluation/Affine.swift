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

    /// Slants by `degrees` each way: `x` moves each row across by its height
    /// (the bottom goes right for a positive angle), `y` moves each column
    /// down by its width.
    public static func skew(degrees: Vec2) -> Affine {
        Affine(a: 1, b: tan(degrees.y * .pi / 180), c: tan(degrees.x * .pi / 180), d: 1, tx: 0, ty: 0)
    }

    /// A layer's own transform: from its local space (origin at its top-left)
    /// into its parent's. Scale, skew and rotation happen about the anchor, in
    /// that order, and the anchor lands on the position. A tilt, which is not
    /// flat, is `Projective.layer`'s.
    public static func layer(position: Vec2, anchor: Vec2, scale: Vec2, rotation: Double, skew: Vec2 = .zero) -> Affine {
        var t = Affine.translation(Vec2(-anchor.x, -anchor.y)).then(.scale(scale))
        if skew != .zero { t = t.then(.skew(degrees: skew)) }
        return t.then(.rotation(degrees: rotation)).then(.translation(position))
    }

    /// `transform`'s flat part: all of it but the tilt.
    public static func layer(_ transform: Transform) -> Affine {
        .layer(position: transform.position, anchor: transform.anchor, scale: transform.scale,
               rotation: transform.rotation, skew: transform.skew)
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

/// A flat transform that can also show perspective: a point's x and y are
/// each divided by `px * x + py * y + w`. With `px` and `py` zero and `w` one
/// it is an `Affine`. A tilted layer is flat and turned in depth, which this
/// draws exactly, as Core Animation does.
public struct Projective: Sendable, Equatable {
    public var a, b, c, d, tx, ty, px, py, w: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double, px: Double, py: Double, w: Double) {
        (self.a, self.b, self.c, self.d, self.tx, self.ty, self.px, self.py, self.w) = (a, b, c, d, tx, ty, px, py, w)
    }

    public init(_ t: Affine) {
        self.init(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty, px: 0, py: 0, w: 1)
    }

    public static let identity = Projective(.identity)

    /// Whether it has no perspective, so `affine` is all of it.
    public var isAffine: Bool { px == 0 && py == 0 && w == 1 }
    public var affine: Affine { Affine(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }

    /// A turn in depth about the origin, seen from `tilt.depth` away: first
    /// around the upright line (`y`), then the level one (`x`).
    public static func tilt(_ tilt: Tilt) -> Projective {
        let x = tilt.x * .pi / 180, y = tilt.y * .pi / 180
        let depth = tilt.depth > 1 ? tilt.depth : .infinity
        // A point (u, v) goes to (u cos y, v cos x + u sin y sin x) at a depth
        // of v sin x - u sin y cos x (negative is away), then is seen from depth.
        return Projective(a: cos(y), b: sin(y) * sin(x), c: 0, d: cos(x), tx: 0, ty: 0,
                          px: sin(y) * cos(x) / depth, py: -sin(x) / depth, w: 1)
    }

    /// A layer's whole transform, tilt and all: `Affine.layer`, turned in
    /// depth about the anchor after its rotation. A hinged tilt turns about
    /// its hinge in the layer's box of `size` instead, along the layer's own
    /// lines, and is seen from over the hinge (`Tilt.hinge`).
    public static func layer(position: Vec2, anchor: Vec2, scale: Vec2, rotation: Double, skew: Vec2, tilt: Tilt,
                             size: Size2 = Size2(0, 0)) -> Projective {
        let flat = Affine.layer(position: .zero, anchor: anchor, scale: scale, rotation: rotation, skew: skew)
        guard tilt.isTilted else { return Projective(flat.then(.translation(position))) }
        guard let hinge = tilt.hinge else {
            return Projective(flat).then(.tilt(tilt)).then(Projective(.translation(position)))
        }
        let pivot = flat.apply(Vec2(hinge.x * size.width, hinge.y * size.height))
        let longest = max(abs(size.width * scale.x), abs(size.height * scale.y))
        let seen = Tilt(x: tilt.x, y: tilt.y, depth: longest * Tilt.hingeDistance)
        // To the hinge, square to the layer's own lines, turned, and back.
        let toHinge = Affine.translation(Vec2(-pivot.x, -pivot.y)).then(.rotation(degrees: -rotation))
        let back = Affine.rotation(degrees: rotation).then(.translation(pivot + position))
        return Projective(flat.then(toHinge)).then(.tilt(seen)).then(Projective(back))
    }

    /// This transform followed by `next`.
    public func then(_ n: Projective) -> Projective {
        // As matrices on column vectors [x y 1]: next times self.
        Projective(a: n.a * a + n.c * b + n.tx * px,
                   b: n.b * a + n.d * b + n.ty * px,
                   c: n.a * c + n.c * d + n.tx * py,
                   d: n.b * c + n.d * d + n.ty * py,
                   tx: n.a * tx + n.c * ty + n.tx * w,
                   ty: n.b * tx + n.d * ty + n.ty * w,
                   px: n.px * a + n.py * b + n.w * px,
                   py: n.px * c + n.py * d + n.w * py,
                   w: n.px * tx + n.py * ty + n.w * w)
    }

    /// Nil where the point is at or behind the viewer, and cannot be seen.
    public func apply(_ p: Vec2) -> Vec2? {
        let q = px * p.x + py * p.y + w
        guard q > 1e-9 else { return nil }
        return Vec2((a * p.x + c * p.y + tx) / q, (b * p.x + d * p.y + ty) / q)
    }

    /// The flat part's determinant, for sizing tolerances.
    public var determinant: Double { a * d - b * c }

    /// Nil when the transform collapses space.
    public var inverted: Projective? {
        // The inverse of [a c tx; b d ty; px py w], by cofactors.
        let det = a * (d * w - ty * py) - c * (b * w - ty * px) + tx * (b * py - d * px)
        guard abs(det) > 1e-12 else { return nil }
        return Projective(a: (d * w - ty * py) / det, b: -(b * w - ty * px) / det,
                          c: -(c * w - tx * py) / det, d: (a * w - tx * px) / det,
                          tx: (c * ty - tx * d) / det, ty: -(a * ty - tx * b) / det,
                          px: (b * py - d * px) / det, py: -(a * py - c * px) / det,
                          w: (a * d - c * b) / det)
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
