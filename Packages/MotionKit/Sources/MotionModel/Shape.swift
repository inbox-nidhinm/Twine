import Foundation

public struct ShapeContent: Codable, Sendable, Equatable {
    public var geometry: ShapeGeometry
    public var fills: [Fill]
    public var strokes: [Stroke]

    public init(geometry: ShapeGeometry, fills: [Fill] = [], strokes: [Stroke] = []) {
        self.geometry = geometry
        self.fills = fills
        self.strokes = strokes
    }
}

/// What a shape is. Every kind except `path` is drawn to fill the layer's
/// `size`, so resizing a rectangle is just changing its size.
public enum ShapeGeometry: Sendable, Equatable {
    case rectangle(cornerRadii: AnimatableProperty<CornerRadii>)
    case ellipse
    /// A straight line across the middle of the box, left to right. Rotation
    /// points it anywhere, which is how Figma represents lines too.
    case line
    case polygon(sides: Int)
    /// `innerRadius` is the inner points' distance from the centre as a fraction
    /// of the outer radius.
    case star(points: Int, innerRadius: AnimatableProperty<Double>)
    /// Drawn with the pen tool, in the layer's own pixel space.
    ///
    /// Animatable so that shape morphing can arrive later without a format
    /// change. Until then a keyframed path holds each shape until the next.
    case path(AnimatableProperty<BezierPath>)

    public var isClosed: Bool {
        switch self {
        case .line: return false
        case .path(let path): return path.value.subpaths.allSatisfy(\.isClosed)
        default: return true
        }
    }
}

extension ShapeGeometry: Codable {
    private enum Kind: String, Codable { case rectangle, ellipse, line, polygon, star, path }
    private enum CodingKeys: String, CodingKey { case type, cornerRadii, sides, points, innerRadius, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .rectangle:
            self = .rectangle(cornerRadii: try c.decode(AnimatableProperty<CornerRadii>.self, forKey: .cornerRadii))
        case .ellipse: self = .ellipse
        case .line: self = .line
        case .polygon: self = .polygon(sides: try c.decode(Int.self, forKey: .sides))
        case .star:
            self = .star(points: try c.decode(Int.self, forKey: .points),
                         innerRadius: try c.decode(AnimatableProperty<Double>.self, forKey: .innerRadius))
        case .path: self = .path(try c.decode(AnimatableProperty<BezierPath>.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rectangle(let radii):
            try c.encode(Kind.rectangle, forKey: .type)
            try c.encode(radii, forKey: .cornerRadii)
        case .ellipse: try c.encode(Kind.ellipse, forKey: .type)
        case .line: try c.encode(Kind.line, forKey: .type)
        case .polygon(let sides):
            try c.encode(Kind.polygon, forKey: .type)
            try c.encode(sides, forKey: .sides)
        case .star(let points, let inner):
            try c.encode(Kind.star, forKey: .type)
            try c.encode(points, forKey: .points)
            try c.encode(inner, forKey: .innerRadius)
        case .path(let path):
            try c.encode(Kind.path, forKey: .type)
            try c.encode(path, forKey: .path)
        }
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
