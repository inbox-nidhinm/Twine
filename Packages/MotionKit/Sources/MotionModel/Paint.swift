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

public enum Paint: AnimatableValue {
    case solid(RGBA)
    case linearGradient(Gradient)
    case radialGradient(Gradient)
    /// A picture, as Figma paints one: every picture is a fill on a shape.
    /// Held by reference, so every paint stays as small to copy as a
    /// gradient: paints are copied in every layer's state on every frame.
    indirect case image(ImagePaint)

    public static func color(_ color: RGBA) -> Paint { .solid(color) }

    public var isRadialGradient: Bool {
        if case .radialGradient = self { return true }
        return false
    }

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    public var imagePaint: ImagePaint? {
        if case .image(let p) = self { return p }
        return nil
    }
}

extension Paint: Codable {
    private enum Kind: String, Codable { case solid, linearGradient, radialGradient, image }
    private enum CodingKeys: String, CodingKey { case type, color, gradient, image }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .solid: self = .solid(try c.decode(RGBA.self, forKey: .color))
        case .linearGradient: self = .linearGradient(try c.decode(Gradient.self, forKey: .gradient))
        case .radialGradient: self = .radialGradient(try c.decode(Gradient.self, forKey: .gradient))
        case .image: self = .image(try c.decode(ImagePaint.self, forKey: .image))
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
        case .image(let image):
            try c.encode(Kind.image, forKey: .type)
            try c.encode(image, forKey: .image)
        }
    }
}

/// A picture filling a shape. Where it sits is worked out from the layer's
/// box, so it follows the shape as it is resized.
public struct ImagePaint: AnimatableValue, Hashable {
    public var mediaID: UUID
    public var mode: ImageScaleMode
    /// Crop only: the whole picture's box, after its turns, as fractions of
    /// the layer's box. A box larger than the layer shows part of the
    /// picture; `ImageCrop.whole` stretches it to fit.
    public var crop: ImageCrop
    /// Quarter turns clockwise, 0 to 3, as Figma's rotate button makes.
    public var quarterTurns: Int
    /// Tile only: each tile's size as a multiple of the picture's own
    /// pixels.
    public var tileScale: Double
    /// 0 to 1.
    public var opacity: Double

    public init(mediaID: UUID, mode: ImageScaleMode = .fill, crop: ImageCrop = .whole,
                quarterTurns: Int = 0, tileScale: Double = 1, opacity: Double = 1) {
        self.mediaID = mediaID
        self.mode = mode
        self.crop = crop
        self.quarterTurns = quarterTurns
        self.tileScale = tileScale
        self.opacity = opacity
    }

    /// The turns kept to 0 through 3.
    public var turns: Int { ((quarterTurns % 4) + 4) % 4 }
}

/// A rectangle in fractions of a layer's box: 0,0 is its top-left corner and
/// a width of 1 its whole width.
public struct ImageCrop: AnimatableValue, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let whole = ImageCrop(x: 0, y: 0, width: 1, height: 1)
}

/// How a picture fills its shape, as Figma names the choices.
public enum ImageScaleMode: String, Codable, Sendable, CaseIterable {
    /// Covers the whole box, cropping what spills over, centred.
    case fill
    /// Shows the whole picture inside the box, centred.
    case fit
    /// Placed by hand: `ImagePaint.crop`.
    case crop
    /// Repeated from the top-left at the picture's own size, scaled.
    case tile

    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .crop: return "Crop"
        case .tile: return "Tile"
        }
    }
}

/// A gradient across the layer's box. `start` and `end` are fractions of the
/// box (0,0 top-left, 1,1 bottom-right) so the gradient follows the shape when
/// it is resized. For a radial gradient `start` is the centre and `end` a point
/// on its edge.
public struct Gradient: AnimatableValue {
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
    /// Round dots in place of dashes, the gap (the pattern's second number)
    /// the clear space between them. Left out of files when off.
    public var dotted: Bool = false
    /// How much of the path is drawn, and which way it grows.
    public var trim: TrimRange = .whole

    /// A dotted stroke's gap, or a dashed one's.
    public var gap: Double { dashPattern.count > 1 ? dashPattern[1] : dashPattern.first ?? 0 }

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
    }

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, paint, width, alignment, cap, join, dashPattern, dashOffset, dotted, trim, trimStart, trimEnd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        paint = try c.decode(Paint.self, forKey: .paint)
        width = try c.decode(Double.self, forKey: .width)
        alignment = try c.decode(StrokeAlignment.self, forKey: .alignment)
        cap = try c.decode(LineCap.self, forKey: .cap)
        join = try c.decode(LineJoin.self, forKey: .join)
        dashPattern = try c.decode([Double].self, forKey: .dashPattern)
        dashOffset = try c.decode(Double.self, forKey: .dashOffset)
        dotted = try c.decodeIfPresent(Bool.self, forKey: .dotted) ?? false
        if let trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim) {
            self.trim = trim
        } else {
            // Before 2 October 2026: a start and an end along the path.
            trim = TrimRange.reading(start: try c.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0,
                                     end: try c.decodeIfPresent(Double.self, forKey: .trimEnd) ?? 1).range
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(paint, forKey: .paint)
        try c.encode(width, forKey: .width)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(cap, forKey: .cap)
        try c.encode(join, forKey: .join)
        try c.encode(dashPattern, forKey: .dashPattern)
        try c.encode(dashOffset, forKey: .dashOffset)
        if dotted { try c.encode(dotted, forKey: .dotted) }
        if trim != .whole { try c.encode(trim, forKey: .trim) }
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
