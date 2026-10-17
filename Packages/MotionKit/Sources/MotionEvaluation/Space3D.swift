import Foundation
import MotionModel

// One 3D space shared by many layers, seen through one camera: what a ring
// of cards, a globe or a tunnel needs, where each layer's own tilt (seen
// through its own camera, `Tilt.depth`) cannot put two layers in the same
// scene. A flat layer placed anywhere in the space is still flat, so the
// camera turns it into a `Projective`, exactly, and the renderer needs
// nothing new but the order to draw in (`depth`).
//
// Axes are Twine's: x right, y down, and z towards the viewer, as a tilt's
// depth is (negative is away). Turns match `Projective.tilt`: about x the
// top goes away, about y the right side goes away, and about z clockwise.

/// A point or direction in the shared space, in pixels.
public struct Vec3: Sendable, Equatable {
    public var x, y, z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        (self.x, self.y, self.z) = (x, y, z)
    }

    public static let zero = Vec3(0, 0, 0)

    public static func + (l: Vec3, r: Vec3) -> Vec3 { Vec3(l.x + r.x, l.y + r.y, l.z + r.z) }
    public static func - (l: Vec3, r: Vec3) -> Vec3 { Vec3(l.x - r.x, l.y - r.y, l.z - r.z) }
    public static func * (l: Vec3, r: Double) -> Vec3 { Vec3(l.x * r, l.y * r, l.z * r) }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public func cross(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
}

/// Where a flat layer sits in the shared space: its own point (u, v, w)
/// goes to `origin + u * u + v * v + w * w` (the three axes as columns).
/// Layers are flat, so only `u` and `v` reach the screen; `w` carries the
/// turns along when poses are combined.
public struct Pose3D: Sendable, Equatable {
    public var u, v, w: Vec3
    public var origin: Vec3

    public init(u: Vec3, v: Vec3, w: Vec3, origin: Vec3) {
        (self.u, self.v, self.w, self.origin) = (u, v, w, origin)
    }

    public static let identity = Pose3D(u: Vec3(1, 0, 0), v: Vec3(0, 1, 0), w: Vec3(0, 0, 1), origin: .zero)

    public func apply(_ p: Vec3) -> Vec3 { origin + u * p.x + v * p.y + w * p.z }
    /// A direction: turned and stretched, not moved.
    public func turn(_ d: Vec3) -> Vec3 { u * d.x + v * d.y + w * d.z }

    /// This pose followed by `next`.
    public func then(_ next: Pose3D) -> Pose3D {
        Pose3D(u: next.turn(u), v: next.turn(v), w: next.turn(w), origin: next.apply(origin))
    }

    public static func translation(_ t: Vec3) -> Pose3D {
        Pose3D(u: Vec3(1, 0, 0), v: Vec3(0, 1, 0), w: Vec3(0, 0, 1), origin: t)
    }

    public static func scale(_ x: Double, _ y: Double, _ z: Double = 1) -> Pose3D {
        Pose3D(u: Vec3(x, 0, 0), v: Vec3(0, y, 0), w: Vec3(0, 0, z), origin: .zero)
    }

    /// About the level line: the top goes away, as `Tilt.x` does.
    public static func turnX(degrees: Double) -> Pose3D {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return Pose3D(u: Vec3(1, 0, 0), v: Vec3(0, c, s), w: Vec3(0, -s, c), origin: .zero)
    }

    /// About the upright line: the right side goes away, as `Tilt.y` does.
    public static func turnY(degrees: Double) -> Pose3D {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return Pose3D(u: Vec3(c, 0, -s), v: Vec3(0, 1, 0), w: Vec3(s, 0, c), origin: .zero)
    }

    /// In the picture's plane, clockwise, as `rotation` is.
    public static func turnZ(degrees: Double) -> Pose3D {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return Pose3D(u: Vec3(c, s, 0), v: Vec3(-s, c, 0), w: Vec3(0, 0, 1), origin: .zero)
    }

    /// A layer of `size` placed as a card is: its `anchor` (pixels from its
    /// top-left) put at `position`, `z` towards the viewer, scaled, then
    /// turned about the anchor on z (its rotation), then on y and x (its
    /// tilt, in `Projective.tilt`'s order).
    public static func layer(position: Vec2, z: Double = 0, anchor: Vec2, scale: Vec2 = Vec2(1, 1),
                             rotation: Double = 0, tilt: Vec2 = .zero) -> Pose3D {
        Pose3D.translation(Vec3(-anchor.x, -anchor.y, 0))
            .then(.scale(scale.x, scale.y))
            .then(.turnZ(degrees: rotation))
            .then(.turnY(degrees: tilt.y))
            .then(.turnX(degrees: tilt.x))
            .then(.translation(Vec3(position.x, position.y, z)))
    }
}

/// How the shared space is seen: from `distance` pixels in front of the
/// plane z = 0, looking straight at `vanishingPoint` (in the space's own
/// pixels, usually its middle). Without a distance it is seen from
/// infinitely far, flat on: isometric.
public struct Camera3D: Sendable, Equatable {
    public var distance: Double?
    public var vanishingPoint: Vec2

    public init(distance: Double?, vanishingPoint: Vec2) {
        self.distance = distance
        self.vanishingPoint = vanishingPoint
    }

    /// Where a point of the space lands on the plane z = 0. Nil at or behind
    /// the viewer.
    public func project(_ p: Vec3) -> Vec2? {
        guard let d = distance else { return Vec2(p.x, p.y) }
        let q = 1 - p.z / d
        guard q > 1e-9 else { return nil }
        let c = vanishingPoint
        return Vec2(c.x + (p.x - c.x) / q, c.y + (p.y - c.y) / q)
    }

    /// The flat layer `pose` places, as it is seen: exact for every point
    /// of the layer, since a flat thing seen in perspective is a
    /// projective map of the plane. A point (s, t) of the layer is at
    /// O + s U + t V, at depth Z = O.z + s U.z + t V.z, and lands at
    /// c + (P - c) / (1 - Z / d), whose top and bottom are both linear in
    /// s and t.
    public func projection(of pose: Pose3D) -> Projective {
        guard let d = distance else {
            return Projective(a: pose.u.x, b: pose.u.y, c: pose.v.x, d: pose.v.y,
                              tx: pose.origin.x, ty: pose.origin.y, px: 0, py: 0, w: 1)
        }
        let c = vanishingPoint, u = pose.u, v = pose.v, o = pose.origin
        return Projective(a: u.x - c.x * u.z / d, b: u.y - c.y * u.z / d,
                          c: v.x - c.x * v.z / d, d: v.y - c.y * v.z / d,
                          tx: o.x - c.x * o.z / d, ty: o.y - c.y * o.z / d,
                          px: -u.z / d, py: -v.z / d, w: 1 - o.z / d)
    }

    /// Whether the layer's front, the side its picture is drawn on, faces
    /// the viewer, judged at its own point `at` (its middle, usually).
    public func seesFront(of pose: Pose3D, at: Vec2) -> Bool {
        // The front faces +z when flat, and U x V is +z there in a y down
        // space. Seen from the eye, or from straight ahead when isometric.
        let normal = pose.u.cross(pose.v)
        guard let d = distance else { return normal.z > 0 }
        let point = pose.apply(Vec3(at.x, at.y, 0))
        let eye = Vec3(vanishingPoint.x, vanishingPoint.y, d)
        return normal.dot(eye - point) > 0
    }
}

/// A layer placed in a shared space, as drawn: its whole transform into its
/// parent, and how near it is, to order it among its siblings (larger is
/// nearer, drawn over smaller). Boxed, since few layers are in 3D and every
/// layer carries one.
public enum Placed3D: Sendable, Equatable {
    case none
    indirect case placed(projection: Projective, depth: Double)

    /// The pose seen through `camera`, ordered by where the layer's own
    /// point `middle` lies.
    public init(_ pose: Pose3D, camera: Camera3D, middle: Vec2) {
        self = .placed(projection: camera.projection(of: pose), depth: pose.apply(Vec3(middle.x, middle.y, 0)).z)
    }

    public var depth: Double {
        if case .placed(_, let depth) = self { return depth }
        return 0
    }
}
