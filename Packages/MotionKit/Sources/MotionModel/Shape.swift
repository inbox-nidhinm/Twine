import Foundation

public struct ShapeContent: Codable, Sendable, Equatable {
    public var geometry: ShapeGeometry
    public var fills: [Fill]
    public var strokes: [Stroke]
    /// Which parts of a path that crosses itself, or has shapes inside
    /// shapes, are inside it.
    public var fillRule: FillRule

    public init(geometry: ShapeGeometry, fills: [Fill] = [], strokes: [Stroke] = [], fillRule: FillRule = .nonZero) {
        self.geometry = geometry
        self.fills = fills
        self.strokes = strokes
        self.fillRule = fillRule
    }

    private enum CodingKeys: String, CodingKey { case geometry, fills, strokes, fillRule }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        geometry = try c.decode(ShapeGeometry.self, forKey: .geometry)
        fills = try c.decode([Fill].self, forKey: .fills)
        strokes = try c.decode([Stroke].self, forKey: .strokes)
        // Arrived with SVG import; everything before was non-zero.
        fillRule = try c.decodeIfPresent(FillRule.self, forKey: .fillRule) ?? .nonZero
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(geometry, forKey: .geometry)
        try c.encode(fills, forKey: .fills)
        try c.encode(strokes, forKey: .strokes)
        if fillRule != .nonZero { try c.encode(fillRule, forKey: .fillRule) }
    }

    /// Where the first picture is among the fills, if there is one: the
    /// picture the inspector shows, Replace changes and crop moves.
    public var pictureIndex: Int? {
        fills.firstIndex { $0.paint.isImage }
    }
}

/// SVG's and Figma's two ways of deciding what is inside a path: non-zero
/// fills everything a path winds round; even-odd leaves every other
/// enclosed part empty, so a shape inside another cuts a hole.
public enum FillRule: String, Codable, Sendable {
    case nonZero, evenOdd
}

/// What a shape is. Every kind except `path` is drawn to fill the layer's
/// `size`, so resizing a rectangle is just changing its size.
public enum ShapeGeometry: Sendable, Equatable {
    case rectangle(cornerRadii: CornerRadii)
    /// A full ellipse, or with `arc`, a slice or a ring of one.
    case ellipse(arc: EllipseArc)
    /// A straight line across the middle of the box, left to right. Rotation
    /// points it anywhere, which is how Figma represents lines too.
    case line
    case polygon(sides: Int)
    /// `innerRadius` is the inner points' distance from the centre as a fraction
    /// of the outer radius. `cornerRadius` rounds every point, in pixels.
    case star(points: Int, innerRadius: Double, cornerRadius: Double)
    /// Drawn with the pen tool, in the layer's own pixel space.
    case path(BezierPath)

    public var isRectangle: Bool {
        if case .rectangle = self { return true }
        return false
    }

    public var isClosed: Bool {
        switch self {
        case .line: return false
        case .path(let path): return path.subpaths.allSatisfy(\.isClosed)
        default: return true
        }
    }
}

extension ShapeGeometry: Codable {
    private enum Kind: String, Codable { case rectangle, ellipse, line, polygon, star, path }
    private enum CodingKeys: String, CodingKey { case type, cornerRadii, sides, points, innerRadius, cornerRadius, arc, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .rectangle:
            self = .rectangle(cornerRadii: try c.decode(CornerRadii.self, forKey: .cornerRadii))
        // Arcs and star corners arrived after the first files were written.
        case .ellipse: self = .ellipse(arc: try c.decodeIfPresent(EllipseArc.self, forKey: .arc) ?? .full)
        case .line: self = .line
        case .polygon: self = .polygon(sides: try c.decode(Int.self, forKey: .sides))
        case .star:
            self = .star(points: try c.decode(Int.self, forKey: .points),
                         innerRadius: try c.decode(Double.self, forKey: .innerRadius),
                         cornerRadius: try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0)
        case .path: self = .path(try c.decode(BezierPath.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rectangle(let radii):
            try c.encode(Kind.rectangle, forKey: .type)
            try c.encode(radii, forKey: .cornerRadii)
        case .ellipse(let arc):
            try c.encode(Kind.ellipse, forKey: .type)
            if arc != .full { try c.encode(arc, forKey: .arc) }
        case .line: try c.encode(Kind.line, forKey: .type)
        case .polygon(let sides):
            try c.encode(Kind.polygon, forKey: .type)
            try c.encode(sides, forKey: .sides)
        case .star(let points, let inner, let corner):
            try c.encode(Kind.star, forKey: .type)
            try c.encode(points, forKey: .points)
            try c.encode(inner, forKey: .innerRadius)
            if corner != 0 { try c.encode(corner, forKey: .cornerRadius) }
        case .path(let path):
            try c.encode(Kind.path, forKey: .type)
            try c.encode(path, forKey: .path)
        }
    }
}

/// How much of an ellipse is drawn, as Figma describes it. Angles are in
/// degrees, clockwise from three o'clock; the slice runs from `start` round
/// to `end`. `innerRadius` cuts a hole in the middle, as a fraction of the
/// outer size: 0 is solid, 0.8 a thin ring.
public struct EllipseArc: AnimatableValue, Hashable {
    public var start: Double
    public var end: Double
    public var innerRadius: Double

    public init(start: Double = 0, end: Double = 360, innerRadius: Double = 0) {
        self.start = start
        self.end = end
        self.innerRadius = innerRadius
    }

    public static let full = EllipseArc()

    /// Whether the slice goes all the way round.
    public var isWhole: Bool { abs(end - start) >= 360 - 1e-9 }
}

/// A star's shape: how many points, how far in the inner ones sit, and how
/// round the points are.
public struct StarShape: AnimatableValue, Hashable {
    public var points: Int
    public var innerRadius: Double
    public var cornerRadius: Double

    public init(points: Int, innerRadius: Double, cornerRadius: Double = 0) {
        self.points = points
        self.innerRadius = innerRadius
        self.cornerRadius = cornerRadius
    }
}

/// A bezier path of one or more subpaths. Kept as plain data rather than a
/// `CGPath` so it can be stored, compared, and later parsed from SVG or
/// combined by boolean operations without touching Core Graphics.
public struct BezierPath: AnimatableValue, Hashable {
    public var subpaths: [Subpath]

    public init(subpaths: [Subpath] = []) {
        self.subpaths = subpaths
    }
}

public struct Subpath: Codable, Sendable, Hashable {
    public var points: [PathPoint]
    public var isClosed: Bool

    public init(points: [PathPoint], isClosed: Bool) {
        self.points = points
        self.isClosed = isClosed
    }
}

/// An anchor point with its two handles, stored as offsets from the anchor.
/// A zero handle is a sharp corner on that side.
public struct PathPoint: Codable, Sendable, Hashable {
    public var position: Vec2
    public var inHandle: Vec2
    public var outHandle: Vec2

    public init(_ position: Vec2, inHandle: Vec2 = .zero, outHandle: Vec2 = .zero) {
        self.position = position
        self.inHandle = inHandle
        self.outHandle = outHandle
    }
}
