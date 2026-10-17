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

extension Camera3D {
    /// The camera a layer outside any 3D frame is seen through: over its
    /// anchor (at `position`), from its tilt's depth, as its own tilt is.
    public static func own(position: Vec2, tilt: Tilt) -> Camera3D {
        Camera3D(distance: tilt.depth > 1 ? tilt.depth : Tilt.defaultDepth, vanishingPoint: position)
    }

    /// A flat layer outside any 3D frame placed `z` towards the viewer, as
    /// drawn: `Projective.layer` with its Z seen through its own camera.
    public static func ownProjection(position: Vec2, z: Double, anchor: Vec2, scale: Vec2, rotation: Double,
                                     skew: Vec2, tilt: Tilt, size: Size2) -> Projective {
        own(position: position, tilt: tilt).projection(of: .layer(position: position, z: z, anchor: anchor, scale: scale,
                                                                 rotation: rotation, skew: skew, tilt: tilt, size: size))
    }

    /// Where a point of a layer outside any 3D frame lands, its turn, tilt,
    /// Z and bend and all, for drawing one by hand (the preset tiles).
    public static func ownPoints(position: Vec2, z: Double, anchor: Vec2, scale: Vec2, rotation: Double, skew: Vec2,
                                 tilt: Tilt, bend: Vec2, size: Size2) -> (Vec2) -> Vec2? {
        let camera = own(position: position, tilt: tilt)
        let pose = Pose3D.layer(position: position, z: z, anchor: anchor, scale: scale, rotation: rotation,
                                skew: skew, tilt: tilt, size: size)
        let curve = Curve(size: size, bend: bend)
        return { p in camera.project(pose.apply(curve.point(p.x, p.y))) }
    }
}

/// A layer placed in a shared space, as drawn: its whole transform into its
/// parent, and how near it is, to order it among its siblings (larger is
/// nearer, drawn over smaller). A bent layer is no longer flat: it carries
/// a grid of where its points land (`BentMesh`), its projection then being
/// the one through its four corners, for outlines and clicks. Boxed, since
/// few layers are in 3D and every layer carries one.
public enum Placed3D: Sendable, Equatable {
    case none
    indirect case placed(projection: Projective, depth: Double)
    indirect case bent(projection: Projective, depth: Double, mesh: BentMesh)

    /// The pose seen through `camera`, ordered by where the layer's own
    /// point `middle` lies.
    public init(_ pose: Pose3D, camera: Camera3D, middle: Vec2) {
        self = .placed(projection: camera.projection(of: pose), depth: pose.apply(Vec3(middle.x, middle.y, 0)).z)
    }

    public var depth: Double {
        switch self {
        case .none: return 0
        case .placed(_, let depth), .bent(_, let depth, _): return depth
        }
    }

    public var projection: Projective? {
        switch self {
        case .none: return nil
        case .placed(let p, _), .bent(let p, _, _): return p
        }
    }

    public var mesh: BentMesh? {
        if case .bent(_, _, let mesh) = self { return mesh }
        return nil
    }
}

/// Where a bent layer's points land in its parent, on a grid of `columns`
/// by `rows` cells across its box: `points` row by row from the top-left,
/// `(rows + 1) * (columns + 1)` of them, in the parent's pixels.
public struct BentMesh: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var points: [Vec2]

    /// Cells across a bent direction, and along a straight one, which
    /// still needs a few to follow perspective: Core Animation stretches
    /// each cell flat.
    static let bentCells = 16
    static let straightCells = 4
    static let doubleCells = 8
}

/// A curve on a layer: its own point (u, v) moved off its flat plane onto
/// the curve, before its pose places it. `bend` is degrees of a circle's
/// turn across the width (x) and down the height (y); the middle stays
/// where it was, the edges curving away from the viewer when positive.
struct Curve {
    let size: Size2
    let bend: Vec2

    func point(_ u: Double, _ v: Double) -> Vec3 {
        var p = Vec3(u, v, 0)
        if let r = Self.radius(bend.x, size.width) {
            let phi = (u - size.width / 2) / r
            p.x = size.width / 2 + r * sin(phi)
            p.z += r * (cos(phi) - 1)
        }
        if let r = Self.radius(bend.y, size.height) {
            let theta = (v - size.height / 2) / r
            p.y = size.height / 2 + r * sin(theta)
            p.z += r * (cos(theta) - 1)
        }
        return p
    }

    /// The circle's radius, negative for a hollow; nil when straight.
    static func radius(_ degrees: Double, _ length: Double) -> Double? {
        guard abs(degrees) > 1e-6, length > 0 else { return nil }
        return length / (degrees * .pi / 180)
    }
}

extension Projective {
    /// The flat map that takes a box of `size` at the origin onto the four
    /// points `corners` (its top-left, top-right, bottom-right and
    /// bottom-left), exactly at each: Heckbert's square to quadrilateral.
    /// Nil when the points are in a line.
    static func box(_ size: Size2, onto corners: [Vec2]) -> Projective? {
        guard corners.count == 4, size.width > 0, size.height > 0 else { return nil }
        let (p0, p1, p2, p3) = (corners[0], corners[1], corners[2], corners[3])
        let dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y
        let det = dx1 * dy2 - dx2 * dy1
        guard abs(det) > 1e-12 else { return nil }
        let g = (dx3 * dy2 - dx2 * dy3) / det, h = (dx1 * dy3 - dx3 * dy1) / det
        let square = Projective(a: p1.x - p0.x + g * p1.x, b: p1.y - p0.y + g * p1.y,
                                c: p3.x - p0.x + h * p3.x, d: p3.y - p0.y + h * p3.y,
                                tx: p0.x, ty: p0.y, px: g, py: h, w: 1)
        return Projective(.scale(Vec2(1 / size.width, 1 / size.height))).then(square)
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
    /// The whole space's turn about `middle`.
    let orbit: Vec2
    let middle: Vec3

    init(_ space: Space3D, size: Size2) {
        let point = Vec2(space.vanishingPoint.x * size.width, space.vanishingPoint.y * size.height)
        camera = Camera3D(distance: space.isIsometric ? nil : max(space.distance, 1), vanishingPoint: point)
        reach = max(size.width, size.height, 1)
        fade = min(max(space.depthFade, 0), 1)
        blur = max(space.depthBlur, 0)
        backs = min(max(space.backOpacity, 0), 1)
        orbit = space.orbit
        middle = Vec3(size.width / 2, size.height / 2, 0)
    }

    /// The camera a layer outside any 3D space is seen through, as its own
    /// tilt is: over its anchor, at its tilt's depth. Only a layer bent or
    /// moved in depth needs one.
    init(ownOf layer: ResolvedLayer) {
        camera = Camera3D.own(position: layer.position, tilt: layer.tilt)
        reach = 1
        fade = 0
        blur = 0
        backs = 1
        orbit = .zero
        middle = .zero
    }

    /// Where `layer` sits in the space, `z` towards the viewer, the space
    /// turned by its orbit.
    func pose(of layer: ResolvedLayer, z: Double) -> Pose3D {
        let pose = Pose3D.layer(position: layer.position, z: z, anchor: layer.anchor, scale: layer.scale,
                                rotation: layer.rotation, skew: layer.skew, tilt: layer.tilt, size: layer.size)
        guard orbit != .zero else { return pose }
        return pose.then(.translation(Vec3(-middle.x, -middle.y, 0)))
            .then(.turnY(degrees: orbit.y)).then(.turnX(degrees: orbit.x))
            .then(.translation(middle))
    }

    /// `layer` placed in the space: drawn through the camera, ordered by
    /// its middle's depth (unless `ordered` is false, for a layer bent
    /// among flat siblings), fainter and blurrier behind the frame's plane,
    /// dimmed with its back to the camera, and not drawn at all once any
    /// point reaches the camera, where the picture would turn inside out.
    /// A bent layer is drawn from a grid of its points, and drawn sharp:
    /// motion blur's copies step a flat picture.
    func place(_ layer: inout ResolvedLayer, z: Double, ordered: Bool = true) {
        let pose = pose(of: layer, z: z)
        let size = layer.size
        let middle = Vec2(size.width / 2, size.height / 2)
        let bend = layer.warp.bend
        let curve = Curve(size: size, bend: bend)
        let centre = pose.apply(curve.point(middle.x, middle.y))
        let depth = ordered ? centre.z : 0
        if bend != .zero, size.width > 0, size.height > 0 {
            // Curved both ways, a card is a small patch of a sphere, and
            // fewer cells follow it: 16 by 16 cost a globe of 36 cards 22 ms
            // a 1080p frame.
            let both = bend.x != 0 && bend.y != 0
            let cells = both ? BentMesh.doubleCells : BentMesh.bentCells
            let columns = bend.x != 0 ? cells : BentMesh.straightCells
            let rows = bend.y != 0 ? cells : BentMesh.straightCells
            var points: [Vec2] = []
            points.reserveCapacity((rows + 1) * (columns + 1))
            for j in 0...rows {
                for i in 0...columns {
                    let u = size.width * Double(i) / Double(columns), v = size.height * Double(j) / Double(rows)
                    guard let p = camera.project(pose.apply(curve.point(u, v))), Self.inFront(pose.apply(curve.point(u, v)), camera) else {
                        layer.opacity = 0
                        return
                    }
                    points.append(p)
                }
            }
            let corners = [points[0], points[columns], points[points.count - 1], points[points.count - 1 - columns]]
            guard let projection = Projective.box(size, onto: corners) else {
                layer.opacity = 0
                return
            }
            layer.placed = .bent(projection: projection, depth: depth, mesh: BentMesh(columns: columns, rows: rows, points: points))
            layer.motion = .none
        } else {
            let projection = camera.projection(of: pose)
            layer.placed = .placed(projection: projection, depth: depth)
            let corners = [Vec2(0, 0), Vec2(size.width, 0), Vec2(size.width, size.height), Vec2(0, size.height)]
            if corners.contains(where: { projection.px * $0.x + projection.py * $0.y + projection.w < Self.nearest }) {
                layer.opacity = 0
                return
            }
        }
        let behind = min(max(-centre.z / reach, 0), 1)
        layer.opacity *= 1 - fade * behind
        layer.blur += blur * behind
        if backs < 1, !camera.seesFront(of: pose, at: middle) { layer.opacity *= backs }
    }

    /// How small the perspective divide may get before a layer counts as
    /// at the camera: a twentieth, where it shows twenty times its size.
    static let nearest = 0.05

    static func inFront(_ p: Vec3, _ camera: Camera3D) -> Bool {
        guard let d = camera.distance else { return true }
        return 1 - p.z / d >= nearest
    }

    /// Only where it matters: a moving layer's copies for motion blur.
    func projection(of layer: ResolvedLayer, z: Double) -> Projective {
        camera.projection(of: pose(of: layer, z: z))
    }
}
