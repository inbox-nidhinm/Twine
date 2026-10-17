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

    /// A flat transform as a pose, on the plane z = 0.
    public init(_ flat: Affine) {
        self.init(u: Vec3(flat.a, flat.b, 0), v: Vec3(flat.c, flat.d, 0), w: Vec3(0, 0, 1),
                  origin: Vec3(flat.tx, flat.ty, 0))
    }

    /// A layer placed as `Projective.layer` places it, but in a shared
    /// space: its anchor (pixels from its top-left) at `position` and `z`
    /// towards the viewer, scaled, skewed and turned about the anchor as it
    /// is flat, then tilted in the space: on y and x about the anchor, in
    /// `Projective.tilt`'s order, or about a hinged tilt's hinge in its box
    /// of `size`, along the layer's own lines. The tilt's depth is the
    /// camera's to say, so it is not used.
    public static func layer(position: Vec2, z: Double = 0, anchor: Vec2, scale: Vec2 = Vec2(1, 1),
                             rotation: Double = 0, skew: Vec2 = .zero, tilt: Tilt = .none,
                             size: Size2 = Size2(0, 0)) -> Pose3D {
        let flat = Affine.layer(position: .zero, anchor: anchor, scale: scale, rotation: rotation, skew: skew)
        let base = Pose3D(flat)
        let at = Vec3(position.x, position.y, z)
        guard tilt.isTilted else { return base.then(.translation(at)) }
        guard let hinge = tilt.hinge else {
            return base.then(.turnY(degrees: tilt.y)).then(.turnX(degrees: tilt.x)).then(.translation(at))
        }
        let pivot = flat.apply(Vec2(hinge.x * size.width, hinge.y * size.height))
        return base.then(.translation(Vec3(-pivot.x, -pivot.y, 0))).then(.turnZ(degrees: -rotation))
            .then(.turnY(degrees: tilt.y)).then(.turnX(degrees: tilt.x))
            .then(.turnZ(degrees: rotation)).then(.translation(Vec3(pivot.x, pivot.y, 0) + at))
    }

    /// The same, with a plain turn on x and y for its tilt.
    public static func layer(position: Vec2, z: Double = 0, anchor: Vec2, scale: Vec2 = Vec2(1, 1),
                             rotation: Double = 0, tilt: Vec2) -> Pose3D {
        layer(position: position, z: z, anchor: anchor, scale: scale, rotation: rotation, tilt: Tilt(x: tilt.x, y: tilt.y))
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

/// A frame's 3D space as its children are placed in it: the camera, and
/// how depth and facing away change how they look.
struct SpaceContext {
    let camera: Camera3D
    /// How far behind the frame's plane depth fade and blur reach their
    /// full amount: the frame's longer side.
    let reach: Double
    let fade: Double
    let blur: Double
    let backs: Double

    init(_ space: Space3D, size: Size2) {
        let point = Vec2(space.vanishingPoint.x * size.width, space.vanishingPoint.y * size.height)
        camera = Camera3D(distance: space.isIsometric ? nil : max(space.distance, 1), vanishingPoint: point)
        reach = max(size.width, size.height, 1)
        fade = min(max(space.depthFade, 0), 1)
        blur = max(space.depthBlur, 0)
        backs = min(max(space.backOpacity, 0), 1)
    }

    /// Where `layer` sits in the space, `z` towards the viewer.
    func pose(of layer: ResolvedLayer, z: Double) -> Pose3D {
        .layer(position: layer.position, z: z, anchor: layer.anchor, scale: layer.scale, rotation: layer.rotation,
               skew: layer.skew, tilt: layer.tilt, size: layer.size)
    }

    /// `layer` placed in the space: drawn through the camera, ordered by
    /// its middle's depth, fainter and blurrier behind the frame's plane,
    /// dimmed with its back to the camera, and not drawn at all once any
    /// corner reaches the camera, where the picture would turn inside out.
    func place(_ layer: inout ResolvedLayer, z: Double) {
        let pose = pose(of: layer, z: z)
        let middle = Vec2(layer.size.width / 2, layer.size.height / 2)
        let placed = Placed3D(pose, camera: camera, middle: middle)
        layer.placed = placed
        guard case .placed(let projection, let depth) = placed else { return }
        let corners = [Vec2(0, 0), Vec2(layer.size.width, 0), Vec2(layer.size.width, layer.size.height), Vec2(0, layer.size.height)]
        if corners.contains(where: { projection.px * $0.x + projection.py * $0.y + projection.w < Self.nearest }) {
            layer.opacity = 0
            return
        }
        let behind = min(max(-depth / reach, 0), 1)
        layer.opacity *= 1 - fade * behind
        layer.blur += blur * behind
        if backs < 1, !camera.seesFront(of: pose, at: middle) { layer.opacity *= backs }
    }

    /// How small the perspective divide may get before a layer counts as
    /// at the camera: a twentieth, where it shows twenty times its size.
    static let nearest = 0.05

    /// Only where it matters: a moving layer's copies for motion blur.
    func projection(of layer: ResolvedLayer, z: Double) -> Projective {
        camera.projection(of: pose(of: layer, z: z))
    }
}
