import Foundation

/// One item in the layer tree.
///
/// `id` is assigned once and never changes, including across duplication of the
/// file. Masks, selections, and a future Figma importer all refer to layers by
/// it, so treat it as the layer's identity rather than as a database key.
public struct Layer: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var isSoloed: Bool
    /// When the layer appears and disappears, in composition seconds.
    public var inPoint: Double
    public var outPoint: Double
    public var transform: Transform
    /// The box the layer is laid out in. Shapes draw to fill it, text wraps to
    /// its width when fixed, images and video are scaled into it, and a group
    /// clips to it when `clipsContent` is on.
    public var size: AnimatableProperty<Size2>
    /// 0 to 1. The inspector shows it as a percentage.
    public var opacity: AnimatableProperty<Double>
    /// Drop shadows and blurs, in the order they apply. A list, like fills, so
    /// that Figma's effect stack can be carried over whole.
    public var effects: [Effect]
    public var mask: MaskReference?
    public var content: LayerContent

    public init(id: UUID = UUID(), name: String, content: LayerContent, size: Size2,
                position: Vec2, inPoint: Double = 0, outPoint: Double) {
        self.id = id
        self.name = name
        self.isVisible = true
        self.isLocked = false
        self.isSoloed = false
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.transform = Transform(position: position, anchor: size.center)
        self.size = AnimatableProperty(size)
        self.opacity = AnimatableProperty(1)
        self.effects = []
        self.mask = nil
        self.content = content
    }

    public var isGroup: Bool {
        if case .group = content { return true }
        return false
    }

    /// The children of a group, or nothing for any other layer.
    public var children: [Layer] {
        get {
            if case .group(let group) = content { return group.children }
            return []
        }
        set {
            if case .group(var group) = content {
                group.children = newValue
                content = .group(group)
            }
        }
    }
}

/// Where a layer sits and how it is turned and scaled, around its anchor point.
public struct Transform: Codable, Sendable, Equatable {
    /// Where the anchor point sits, in the parent's space.
    public var position: AnimatableProperty<Vec2>
    /// Measured in pixels from the layer's own top-left corner. New layers put
    /// it at their centre.
    public var anchor: AnimatableProperty<Vec2>
    /// 1 is 100%.
    public var scale: AnimatableProperty<Vec2>
    /// Whether editing one scale axis moves the other with it. A property of
    /// the editor rather than of the motion, but it belongs to the layer.
    public var isScaleLinked: Bool
    /// Degrees, clockwise.
    public var rotation: AnimatableProperty<Double>

    public init(position: Vec2, anchor: Vec2) {
        self.position = AnimatableProperty(position)
        self.anchor = AnimatableProperty(anchor)
        self.scale = AnimatableProperty(.one)
        self.isScaleLinked = true
        self.rotation = AnimatableProperty(0)
    }
}

public enum LayerContent: Sendable, Equatable {
    case shape(ShapeContent)
    case text(TextContent)
    case image(ImageContent)
    case video(VideoContent)
    case audio(AudioContent)
    case group(GroupContent)
}

extension LayerContent: Codable {
    private enum Kind: String, Codable { case shape, text, image, video, audio, group }
    private enum CodingKeys: String, CodingKey { case type, shape, text, image, video, audio, group }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .shape: self = .shape(try c.decode(ShapeContent.self, forKey: .shape))
        case .text: self = .text(try c.decode(TextContent.self, forKey: .text))
        case .image: self = .image(try c.decode(ImageContent.self, forKey: .image))
        case .video: self = .video(try c.decode(VideoContent.self, forKey: .video))
        case .audio: self = .audio(try c.decode(AudioContent.self, forKey: .audio))
        case .group: self = .group(try c.decode(GroupContent.self, forKey: .group))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shape(let v): try c.encode(Kind.shape, forKey: .type); try c.encode(v, forKey: .shape)
        case .text(let v): try c.encode(Kind.text, forKey: .type); try c.encode(v, forKey: .text)
        case .image(let v): try c.encode(Kind.image, forKey: .type); try c.encode(v, forKey: .image)
        case .video(let v): try c.encode(Kind.video, forKey: .type); try c.encode(v, forKey: .video)
        case .audio(let v): try c.encode(Kind.audio, forKey: .type); try c.encode(v, forKey: .audio)
        case .group(let v): try c.encode(Kind.group, forKey: .type); try c.encode(v, forKey: .group)
        }
    }
}

public struct TextContent: Codable, Sendable, Equatable {
    public var text: String
    public var fontFamily: String
    /// 100 to 900, the CSS scale. The family's nearest face is used.
    public var fontWeight: Int
    public var fontSize: Double
    public var color: AnimatableProperty<RGBA>
    public var alignment: TextAlignment
    /// Extra space between letters, in pixels.
    public var letterSpacing: Double
    /// Baseline to baseline in pixels, or nil for the font's own.
    public var lineHeight: Double?
    public var sizing: TextSizing

    public init(text: String, fontFamily: String = "SF Pro", fontWeight: Int = 400, fontSize: Double = 48,
                color: RGBA = .white, alignment: TextAlignment = .left, letterSpacing: Double = 0,
                lineHeight: Double? = nil, sizing: TextSizing = .autoWidth) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = AnimatableProperty(color)
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.sizing = sizing
    }
}

public enum TextAlignment: String, Codable, Sendable, CaseIterable {
    case left, center, right, justified
}

/// Auto width grows the box to fit the text on one line per paragraph. Fixed
/// width keeps the box's width and wraps inside it.
public enum TextSizing: String, Codable, Sendable, CaseIterable {
    case autoWidth, fixedWidth
}

public struct ImageContent: Codable, Sendable, Equatable {
    public var mediaID: UUID

    public init(mediaID: UUID) {
        self.mediaID = mediaID
    }
}

/// A video clip. The frame shown at composition time `t` is the one at
/// `trimStart + (t - inPoint)` in the source.
public struct VideoContent: Codable, Sendable, Equatable {
    public var mediaID: UUID
    public var trimStart: Double
    /// 1 is the clip's own level.
    public var volume: AnimatableProperty<Double>
    public var isMuted: Bool

    public init(mediaID: UUID, trimStart: Double = 0) {
        self.mediaID = mediaID
        self.trimStart = trimStart
        self.volume = AnimatableProperty(1)
        self.isMuted = false
    }
}

public struct AudioContent: Codable, Sendable, Equatable {
    public var mediaID: UUID
    public var trimStart: Double
    public var volume: AnimatableProperty<Double>
    public var isMuted: Bool

    public init(mediaID: UUID, trimStart: Double = 0) {
        self.mediaID = mediaID
        self.trimStart = trimStart
        self.volume = AnimatableProperty(1)
        self.isMuted = false
    }
}

/// Children are drawn in array order, so the last child is in front. The
/// renderer gives every group a container layer of its own, which is what lets
/// group opacity, group transforms and, later, group motion blur apply to the
/// children as one picture.
public struct GroupContent: Codable, Sendable, Equatable {
    public var children: [Layer]
    public var clipsContent: Bool

    public init(children: [Layer] = [], clipsContent: Bool = false) {
        self.children = children
        self.clipsContent = clipsContent
    }
}

/// A shape layer used as this layer's alpha mask. The mask layer stops drawing
/// on its own while it is used as one.
public struct MaskReference: Codable, Sendable, Equatable {
    public var layerID: UUID
    public var isInverted: Bool

    public init(layerID: UUID, isInverted: Bool = false) {
        self.layerID = layerID
        self.isInverted = isInverted
    }
}

public struct Effect: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var isEnabled: Bool
    public var kind: EffectKind

    public init(id: UUID = UUID(), isEnabled: Bool = true, kind: EffectKind) {
        self.id = id
        self.isEnabled = isEnabled
        self.kind = kind
    }
}

public enum EffectKind: Sendable, Equatable {
    case dropShadow(DropShadow)
    case layerBlur(LayerBlur)
}

extension EffectKind: Codable {
    private enum Kind: String, Codable { case dropShadow, layerBlur }
    private enum CodingKeys: String, CodingKey { case type, shadow, blur }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .dropShadow: self = .dropShadow(try c.decode(DropShadow.self, forKey: .shadow))
        case .layerBlur: self = .layerBlur(try c.decode(LayerBlur.self, forKey: .blur))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dropShadow(let v): try c.encode(Kind.dropShadow, forKey: .type); try c.encode(v, forKey: .shadow)
        case .layerBlur(let v): try c.encode(Kind.layerBlur, forKey: .type); try c.encode(v, forKey: .blur)
        }
    }
}

public struct DropShadow: Codable, Sendable, Equatable {
    public var color: AnimatableProperty<RGBA>
    public var offset: AnimatableProperty<Vec2>
    /// Blur radius in pixels.
    public var blur: AnimatableProperty<Double>
    /// 0 to 1, on top of the colour's own alpha.
    public var opacity: AnimatableProperty<Double>

    public init(color: RGBA = .black, offset: Vec2 = Vec2(0, 4), blur: Double = 8, opacity: Double = 0.25) {
        self.color = AnimatableProperty(color)
        self.offset = AnimatableProperty(offset)
        self.blur = AnimatableProperty(blur)
        self.opacity = AnimatableProperty(opacity)
    }
}

public struct LayerBlur: Codable, Sendable, Equatable {
    /// Gaussian radius in pixels.
    public var radius: AnimatableProperty<Double>

    public init(radius: Double = 4) {
        self.radius = AnimatableProperty(radius)
    }
}
