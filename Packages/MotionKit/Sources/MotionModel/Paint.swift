import Foundation

/// A fill on a shape. Shapes hold a list of these rather than one, because a
/// Figma node can carry several and a future importer should not have to drop
/// any. The MVP interface edits the first.
public struct Fill: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var isEnabled: Bool
    public var paint: Paint

    public init(id: UUID = UUID(), isEnabled: Bool = true, paint: Paint) {
        self.id = id
        self.isEnabled = isEnabled
        self.paint = paint
    }
}

public enum Paint: Sendable, Equatable {
    case solid(RGBA)
    case linearGradient(Gradient)
    case radialGradient(Gradient)

    public static func color(_ color: RGBA) -> Paint { .solid(color) }
}

extension Paint: Codable {
    private enum Kind: String, Codable { case solid, linearGradient, radialGradient }
    private enum CodingKeys: String, CodingKey { case type, color, gradient }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .solid: self = .solid(try c.decode(RGBA.self, forKey: .color))
        case .linearGradient: self = .linearGradient(try c.decode(Gradient.self, forKey: .gradient))
        case .radialGradient: self = .radialGradient(try c.decode(Gradient.self, forKey: .gradient))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let color):
            try c.encode(Kind.solid, forKey: .type)
            try c.encode(color, forKey: .color)
        case .linearGradient(let gradient):
            try c.encode(Kind.linearGradient, forKey: .type)
            try c.encode(gradient, forKey: .gradient)
        case .radialGradient(let gradient):
            try c.encode(Kind.radialGradient, forKey: .type)
            try c.encode(gradient, forKey: .gradient)
        }
    }
}

/// A gradient across the layer's box. `start` and `end` are fractions of the
/// box (0,0 top-left, 1,1 bottom-right) so the gradient follows the shape when
/// it is resized. For a radial gradient `start` is the centre and `end` a point
/// on its edge.
public struct Gradient: Codable, Sendable, Equatable {
    public var stops: [GradientStop]
    public var start: Vec2
    public var end: Vec2

    public init(stops: [GradientStop], start: Vec2 = Vec2(0, 0.5), end: Vec2 = Vec2(1, 0.5)) {
        self.stops = stops
        self.start = start
        self.end = end
    }
}

public struct GradientStop: AnimatableValue, Hashable {
    /// 0 at the gradient's start, 1 at its end.
    public var position: Double
    public var color: RGBA

    public init(position: Double, color: RGBA) {
        self.position = position
        self.color = color
    }
}

public struct Stroke: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var isEnabled: Bool
    public var paint: Paint
    public var width: Double
    public var alignment: StrokeAlignment
    public var cap: LineCap
    public var join: LineJoin
    /// Alternating dash and gap lengths in pixels. Empty means a solid line.
    public var dashPattern: [Double]
    public var dashOffset: Double
    /// How much of the path is drawn, as fractions of its length.
    public var trimStart: Double
    public var trimEnd: Double

    public init(id: UUID = UUID(), isEnabled: Bool = true, paint: Paint, width: Double = 1,
                alignment: StrokeAlignment = .center, cap: LineCap = .butt, join: LineJoin = .miter,
                dashPattern: [Double] = [], dashOffset: Double = 0) {
        self.id = id
        self.isEnabled = isEnabled
        self.paint = paint
        self.width = width
        self.alignment = alignment
        self.cap = cap
        self.join = join
        self.dashPattern = dashPattern
        self.dashOffset = dashOffset
        self.trimStart = 0
        self.trimEnd = 1
    }
}

/// Core Animation draws strokes centred on the path only. Inside and outside
/// are made by the renderer from a doubled stroke clipped to the shape, which
/// is only meaningful on closed paths; open paths always draw centred.
public enum StrokeAlignment: String, Codable, Sendable, CaseIterable {
    case center, inside, outside
}

public enum LineCap: String, Codable, Sendable, CaseIterable {
    case butt, round, square
}

public enum LineJoin: String, Codable, Sendable, CaseIterable {
    case miter, round, bevel
}
