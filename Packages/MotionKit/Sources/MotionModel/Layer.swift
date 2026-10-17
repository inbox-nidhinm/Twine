import Foundation

/// One item in the layer tree. Its properties are its design state: how it
/// looks when no action is changing it. Layers last the whole composition;
/// they come and go through actions, such as Opacity and Hide/Show.
///
/// `id` is assigned once and never changes, including across duplication of the
/// file. Masks, selections, and a future Figma importer all refer to layers by
/// it, so treat it as the layer's identity rather than as a database key.
public struct Layer: Codable, Sendable, Equatable, Identifiable {
    /// Set only here and by `withID`, which copying uses, so nothing else
    /// can change a layer's identity.
    public private(set) var id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var isSoloed: Bool
    public var transform: Transform
    /// The box the layer is laid out in. Shapes draw to fill it, text wraps to
    /// its width when fixed, images and video are scaled into it, and a group
    /// clips to it when `clipsContent` is on.
    public var size: Size2
    /// 0 to 1. The inspector shows it as a percentage.
    public var opacity: Double
    /// Drop shadows and blurs, in the order they apply. A list, like fills, so
    /// that Figma's effect stack can be carried over whole.
    public var effects: [Effect]
    /// The layer masks the layers in front of it in the same group or frame,
    /// up to the next mask, as Figma's Use as Mask does: they show only
    /// where it draws, and it does not draw itself (4 October 2026). Left
    /// out of files when off.
    public var isMask: Bool
    /// A mask as projects kept one until 4 October 2026: the layer it names
    /// masks this one. Read from older files only and never written:
    /// `Masks.convertingLegacy` turns these into mask groups as a project
    /// opens.
    public var legacyMask: MaskReference?
    /// How the layer mixes with what is behind it. A group or frame left
    /// at Normal lets its children blend with what is behind it too, as
    /// Figma's Pass Through does.
    public var blendMode: BlendMode
    /// Whether changing its width or height changes the other with it, in
    /// the inspector and on the canvas, as Figma's constrain proportions. A
    /// setting of the editor rather than of the look. Off for new layers.
    public var keepsProportions: Bool
    public var content: LayerContent

    public init(id: UUID = UUID(), name: String, content: LayerContent, size: Size2, position: Vec2) {
        self.id = id
        self.name = name
        self.isVisible = true
        self.isLocked = false
        self.isSoloed = false
        self.transform = Transform(position: position, anchor: size.center)
        self.size = size
        self.opacity = 1
        self.effects = []
        self.isMask = false
        self.legacyMask = nil
        self.blendMode = .normal
        self.keepsProportions = false
        self.content = content
    }

    /// The layer whole under another id: every property carried, so one
    /// added later is carried too, which copying field by field forgot.
    func withID(_ id: UUID) -> Layer {
        var copy = self
        copy.id = id
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isVisible, isLocked, isSoloed, transform, size, opacity, effects, isMask, mask, blendMode, keepsProportions, content
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
        isSoloed = try c.decode(Bool.self, forKey: .isSoloed)
        transform = try c.decode(Transform.self, forKey: .transform)
        size = try c.decode(Size2.self, forKey: .size)
        opacity = try c.decode(Double.self, forKey: .opacity)
        effects = try c.decode([Effect].self, forKey: .effects)
        isMask = try c.decodeIfPresent(Bool.self, forKey: .isMask) ?? false
        legacyMask = try c.decodeIfPresent(MaskReference.self, forKey: .mask)
        // Blend modes arrived after the first files.
        blendMode = try c.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        keepsProportions = try c.decodeIfPresent(Bool.self, forKey: .keepsProportions) ?? false
        content = try c.decode(LayerContent.self, forKey: .content)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(isLocked, forKey: .isLocked)
        try c.encode(isSoloed, forKey: .isSoloed)
        try c.encode(transform, forKey: .transform)
        try c.encode(size, forKey: .size)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(effects, forKey: .effects)
        if isMask { try c.encode(isMask, forKey: .isMask) }
        // Left out at Normal, so files without blending read as before.
        if blendMode != .normal { try c.encode(blendMode, forKey: .blendMode) }
        // Left out when off, as it is for nearly every layer.
        if keepsProportions { try c.encode(keepsProportions, forKey: .keepsProportions) }
        try c.encode(content, forKey: .content)
    }

    /// A group or a frame: anything with children.
    public var isGroup: Bool {
        if case .group = content { return true }
        return false
    }

    public var isFrame: Bool {
        if case .group(let g) = content { return g.frame != nil }
        return false
    }

    /// A frame's 3D space, or nil for a flat frame and anything else.
    /// Setting it on anything but a frame does nothing.
    public var space3D: Space3D? {
        get {
            if case .group(let g) = content { return g.frame?.space }
            return nil
        }
        set {
            guard case .group(var g) = content, var f = g.frame else { return }
            f.space = newValue
            g.frame = f
            content = .group(g)
        }
    }

    /// The fills, strokes and outline of a shape, or of a frame as a
    /// rectangle: whatever has a look of its own. Setting it on a frame keeps
    /// the rectangle's corners and drops any other outline.
    public var look: ShapeContent? {
        get {
            switch content {
            case .shape(let s): return s
            case .group(let g):
                guard let f = g.frame else { return nil }
                return ShapeContent(geometry: .rectangle(cornerRadii: f.cornerRadii), fills: f.fills, strokes: f.strokes)
            default: return nil
            }
        }
        set {
            guard let newValue else { return }
            switch content {
            case .shape: content = .shape(newValue)
            case .group(var g):
                guard var f = g.frame else { return }
                f.fills = newValue.fills
                f.strokes = newValue.strokes
                if case .rectangle(let radii) = newValue.geometry { f.cornerRadii = radii }
                g.frame = f
                content = .group(g)
            default: break
            }
        }
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
    public var position: Vec2
    /// Measured in pixels from the layer's own top-left corner. New layers put
    /// it at their centre.
    public var anchor: Vec2
    /// 1 is 100%.
    public var scale: Vec2
    /// Whether editing one scale axis moves the other with it. A property of
    /// the editor rather than of the motion, but it belongs to the layer.
    public var isScaleLinked: Bool
    /// Degrees, clockwise.
    public var rotation: Double
    /// Degrees each way, after scale and before rotation: `x` slants the
    /// layer's sides (its bottom moves right for a positive angle), `y` its
    /// top and bottom (its right side moves down).
    public var skew: Vec2
    /// A turn in depth, around the anchor, seen in perspective. See `Tilt`.
    public var tilt: Tilt
    /// Pixels towards the viewer (negative is away), in a frame in 3D
    /// (`Space3D`); anywhere else it changes nothing.
    public var z: Double
    /// Degrees of curve: `x` bends the layer round an upright line, so its
    /// width is that much of a circle's turn; `y` round a level line, along
    /// its height. Positive brings the middle towards the viewer, the edges
    /// curving away; negative hollows it. Seen through its frame's camera
    /// in 3D, or from its tilt's depth anywhere else.
    public var bend: Vec2

    public init(position: Vec2, anchor: Vec2) {
        self.position = position
        self.anchor = anchor
        self.scale = .one
        self.isScaleLinked = true
        self.rotation = 0
        self.skew = .zero
        self.tilt = .none
        self.z = 0
        self.bend = .zero
    }

    private enum CodingKeys: String, CodingKey { case position, anchor, scale, isScaleLinked, rotation, skew, tilt, z, bend }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decode(Vec2.self, forKey: .position)
        anchor = try c.decode(Vec2.self, forKey: .anchor)
        scale = try c.decode(Vec2.self, forKey: .scale)
        isScaleLinked = try c.decode(Bool.self, forKey: .isScaleLinked)
        rotation = try c.decode(Double.self, forKey: .rotation)
        // Files from before skew and tilt have neither.
        skew = try c.decodeIfPresent(Vec2.self, forKey: .skew) ?? .zero
        tilt = try c.decodeIfPresent(Tilt.self, forKey: .tilt) ?? .none
        z = try c.decodeIfPresent(Double.self, forKey: .z) ?? 0
        bend = try c.decodeIfPresent(Vec2.self, forKey: .bend) ?? .zero
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(position, forKey: .position)
        try c.encode(anchor, forKey: .anchor)
        try c.encode(scale, forKey: .scale)
        try c.encode(isScaleLinked, forKey: .isScaleLinked)
        try c.encode(rotation, forKey: .rotation)
        // Left out when the layer is straight, so most files stay as they were.
        if skew != .zero { try c.encode(skew, forKey: .skew) }
        if tilt != .none { try c.encode(tilt, forKey: .tilt) }
        if z != 0 { try c.encode(z, forKey: .z) }
        if bend != .zero { try c.encode(bend, forKey: .bend) }
    }
}

/// A layer turned in depth around its anchor, as a card tipping back or
/// turning side to side, and seen in perspective. `x` tips it around a
/// level line through the anchor (its top goes away for a positive angle),
/// `y` turns it around an upright line (its right side goes away). `depth`
/// is how far away the viewer is, in pixels: nearer looks more dramatic.
public struct Tilt: AnimatableValue {
    public var x: Double
    public var y: Double
    public var depth: Double
    /// Where it turns, as a share of the layer's box ((0, 0.5) is the middle
    /// of its left edge), for a page turning on its spine; nil turns about
    /// the anchor. Only the Page Turn preset sets one. A hinged tilt's lines
    /// follow the layer's own rotation, so the spine is its own edge, and it
    /// is seen from `hingeDistance` times the box's longer side, as the
    /// onboarding's pages are, whatever `depth` says. Left out of files
    /// when nil.
    public var hinge: Vec2?

    public init(x: Double, y: Double, depth: Double = Tilt.defaultDepth, hinge: Vec2? = nil) {
        self.x = x
        self.y = y
        self.depth = depth
        self.hinge = hinge
    }

    public static let defaultDepth = 1200.0
    /// How far a hinged tilt is seen from, in the box's longer sides: the
    /// onboarding's perspective of 0.35.
    public static let hingeDistance = 1 / 0.35
    public static let none = Tilt(x: 0, y: 0)

    /// Whether it turns at all; the depth alone changes nothing.
    public var isTilted: Bool { x != 0 || y != 0 }
}

public enum LayerContent: Sendable, Equatable {
    case shape(ShapeContent)
    case text(TextContent)
    case video(VideoContent)
    case audio(AudioContent)
    case group(GroupContent)
}

extension LayerContent: Codable {
    private enum Kind: String, Codable { case shape, text, video, audio, group }
    private enum CodingKeys: String, CodingKey { case type, shape, text, video, audio, group }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .shape: self = .shape(try c.decode(ShapeContent.self, forKey: .shape))
        case .text: self = .text(try c.decode(TextContent.self, forKey: .text))
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
    public var color: RGBA
    public var alignment: TextAlignment
    /// Extra space between letters, in pixels.
    public var letterSpacing: Double
    /// Baseline to baseline in pixels, or nil for the font's own.
    public var lineHeight: Double?
    public var sizing: TextSizing
    /// True when the fill (`color`) is switched off, leaving only the
    /// stroke; left out of files while it shows.
    public var hidesFill: Bool?
    /// An outline round the letters, solid only; nil for none.
    public var stroke: Stroke?

    public init(text: String, fontFamily: String = "SF Pro", fontWeight: Int = 400, fontSize: Double = 48,
                color: RGBA = .white, alignment: TextAlignment = .left, letterSpacing: Double = 0,
                lineHeight: Double? = nil, sizing: TextSizing = .autoWidth, stroke: Stroke? = nil) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.sizing = sizing
        self.stroke = stroke
    }

    public var showsFill: Bool { hidesFill != true }
}

public enum TextAlignment: String, Codable, Sendable, CaseIterable {
    case left, center, right, justified
}

/// Auto width grows the box to fit the text on one line per paragraph. Fixed
/// width keeps the box's width and wraps inside it.
public enum TextSizing: String, Codable, Sendable, CaseIterable {
    case autoWidth, fixedWidth
}

/// A video clip. When it plays, and which part of the file, is set by its
/// Play actions; the layer holds only what stays the same. (Pictures are
/// not layers of their own: a picture is a shape's fill, `Paint.image`.)
public struct VideoContent: Codable, Sendable, Equatable {
    public var mediaID: UUID
    /// 1 is the clip's own level.
    public var volume: Double
    public var isMuted: Bool
    /// How the frames sit in the layer's box when their shapes differ.
    public var fit: VideoFit

    public init(mediaID: UUID, volume: Double = 1, isMuted: Bool = false, fit: VideoFit = .fill) {
        self.mediaID = mediaID
        self.volume = volume
        self.isMuted = isMuted
        self.fit = fit
    }

    private enum CodingKeys: String, CodingKey { case mediaID, volume, isMuted, fit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try c.decode(UUID.self, forKey: .mediaID)
        volume = try c.decode(Double.self, forKey: .volume)
        isMuted = try c.decode(Bool.self, forKey: .isMuted)
        // Added with Replace Video, after the first files with video.
        fit = try c.decodeIfPresent(VideoFit.self, forKey: .fit) ?? .fill
    }
}

/// A video's frames in its layer's box: covering it, cropping what spills
/// over, or shown whole inside it. Both centred.
public enum VideoFit: String, Codable, Sendable, CaseIterable {
    case fill, fit

    public var title: String { self == .fill ? "Fill" : "Fit" }
}

/// A sound, played by its Play actions.
public struct AudioContent: Codable, Sendable, Equatable {
    public var mediaID: UUID
    public var volume: Double
    public var isMuted: Bool

    public init(mediaID: UUID, volume: Double = 1, isMuted: Bool = false) {
        self.mediaID = mediaID
        self.volume = volume
        self.isMuted = isMuted
    }
}

/// Children are drawn in array order, so the last child is in front. The
/// renderer gives every group a container layer of its own, which is what lets
/// group opacity, group transforms and, later, group motion blur apply to the
/// children as one picture.
///
/// A group with a `frame` is a frame, as in Figma: a box of its own with
/// fills behind its children, strokes in front of them, rounded corners it
/// clips to, and a size that resizing changes (a group scales instead).
public struct GroupContent: Codable, Sendable, Equatable {
    public var children: [Layer]
    public var clipsContent: Bool
    /// Nil for a plain group.
    public var frame: FrameStyle?

    public init(children: [Layer] = [], clipsContent: Bool = false, frame: FrameStyle? = nil) {
        self.children = children
        self.clipsContent = clipsContent
        self.frame = frame
    }

    private enum CodingKeys: String, CodingKey { case children, clipsContent, frame }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        children = try c.decode([Layer].self, forKey: .children)
        clipsContent = try c.decode(Bool.self, forKey: .clipsContent)
        // Frames arrived after the first files with groups.
        frame = try c.decodeIfPresent(FrameStyle.self, forKey: .frame)
    }
}

/// A frame's own look: what a rectangle has, in the frame's box.
public struct FrameStyle: Codable, Sendable, Equatable {
    public var fills: [Fill]
    public var strokes: [Stroke]
    public var cornerRadii: CornerRadii
    /// A frame in 3D holds its children in one shared space, seen through
    /// one camera; nil for a flat frame, and left out of files then.
    public var space: Space3D?

    public init(fills: [Fill] = [], strokes: [Stroke] = [], cornerRadii: CornerRadii = .zero, space: Space3D? = nil) {
        self.fills = fills
        self.strokes = strokes
        self.cornerRadii = cornerRadii
        self.space = space
    }
}

/// How a frame in 3D shows its children: each placed in one space by its
/// own place, Z, turn and tilt, seen through one camera, and drawn nearest
/// on top. Its children's tilts turn in that space, seen through the
/// camera rather than from their own depth. Only a frame's own children
/// are placed: a group or frame inside one is a flat card in it.
public struct Space3D: AnimatableValue {
    /// How far in front of the frame the camera is, in pixels: nearer
    /// makes the perspective stronger. Ignored when isometric.
    public var distance: Double
    /// Seen from infinitely far, flat on: nothing grows nearer or shrinks
    /// further away.
    public var isIsometric: Bool
    /// The point the camera looks straight at, as a share of the frame's
    /// box: (0.5, 0.5) is its middle.
    public var vanishingPoint: Vec2
    /// 0 to 1: how much fainter a layer is behind the frame's plane,
    /// reaching the full amount one frame's longer side behind it.
    public var depthFade: Double
    /// Figma's pixels: how much blurrier a layer is behind the frame's
    /// plane, the full amount one frame's longer side behind it.
    public var depthBlur: Double
    /// 0 to 1: how strongly a layer shows when its back is to the camera.
    /// 1 shows it whole, 0 hides it.
    public var backOpacity: Double
    /// Degrees the whole space is turned about the frame's middle, as if
    /// the camera went round it: `x` tips it, the top going away, `y`
    /// turns it, the right going away. A ring of cards spins on `y`.
    public var orbit: Vec2

    public init(distance: Double = Tilt.defaultDepth, isIsometric: Bool = false, vanishingPoint: Vec2 = Vec2(0.5, 0.5),
                depthFade: Double = 0, depthBlur: Double = 0, backOpacity: Double = 1, orbit: Vec2 = .zero) {
        self.distance = distance
        self.isIsometric = isIsometric
        self.vanishingPoint = vanishingPoint
        self.depthFade = depthFade
        self.depthBlur = depthBlur
        self.backOpacity = backOpacity
        self.orbit = orbit
    }

    private enum CodingKeys: String, CodingKey {
        case distance, isIsometric, vanishingPoint, depthFade, depthBlur, backOpacity, orbit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Space3D()
        distance = try c.decodeIfPresent(Double.self, forKey: .distance) ?? standard.distance
        isIsometric = try c.decodeIfPresent(Bool.self, forKey: .isIsometric) ?? false
        vanishingPoint = try c.decodeIfPresent(Vec2.self, forKey: .vanishingPoint) ?? standard.vanishingPoint
        depthFade = try c.decodeIfPresent(Double.self, forKey: .depthFade) ?? 0
        depthBlur = try c.decodeIfPresent(Double.self, forKey: .depthBlur) ?? 0
        backOpacity = try c.decodeIfPresent(Double.self, forKey: .backOpacity) ?? 1
        orbit = try c.decodeIfPresent(Vec2.self, forKey: .orbit) ?? .zero
    }

    public func encode(to encoder: Encoder) throws {
        // Only what differs from a new space, so a frame just switched to
        // 3D writes `{}`.
        var c = encoder.container(keyedBy: CodingKeys.self)
        let standard = Space3D()
        if distance != standard.distance { try c.encode(distance, forKey: .distance) }
        if isIsometric { try c.encode(isIsometric, forKey: .isIsometric) }
        if vanishingPoint != standard.vanishingPoint { try c.encode(vanishingPoint, forKey: .vanishingPoint) }
        if depthFade != 0 { try c.encode(depthFade, forKey: .depthFade) }
        if depthBlur != 0 { try c.encode(depthBlur, forKey: .depthBlur) }
        if backOpacity != 1 { try c.encode(backOpacity, forKey: .backOpacity) }
        if orbit != .zero { try c.encode(orbit, forKey: .orbit) }
    }
}

/// How projects before 4 October 2026 kept a mask: on the masked layer, the
/// layer masking it, which stopped drawing on its own. Read only, for
/// `Layer.legacyMask`; its inversion is dropped as the mask converts.
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
    /// A shadow cast inward from the shape's edge, inside its fill. Shapes
    /// and frames only.
    case innerShadow(DropShadow)
    case layerBlur(LayerBlur)
    case backgroundBlur(BackgroundBlur)
}

extension EffectKind: Codable {
    private enum Kind: String, Codable { case dropShadow, innerShadow, layerBlur, backgroundBlur }
    private enum CodingKeys: String, CodingKey { case type, shadow, blur }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .dropShadow: self = .dropShadow(try c.decode(DropShadow.self, forKey: .shadow))
        case .innerShadow: self = .innerShadow(try c.decode(DropShadow.self, forKey: .shadow))
        case .layerBlur: self = .layerBlur(try c.decode(LayerBlur.self, forKey: .blur))
        case .backgroundBlur: self = .backgroundBlur(try c.decode(BackgroundBlur.self, forKey: .blur))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dropShadow(let v): try c.encode(Kind.dropShadow, forKey: .type); try c.encode(v, forKey: .shadow)
        case .innerShadow(let v): try c.encode(Kind.innerShadow, forKey: .type); try c.encode(v, forKey: .shadow)
        case .layerBlur(let v): try c.encode(Kind.layerBlur, forKey: .type); try c.encode(v, forKey: .blur)
        case .backgroundBlur(let v): try c.encode(Kind.backgroundBlur, forKey: .type); try c.encode(v, forKey: .blur)
        }
    }
}

/// Blur amounts are Figma's: twice the standard deviation of the Gaussian,
/// the same number CSS takes for a shadow's blur. A layer blur of 8 in Figma
/// looks the same here.
public struct DropShadow: AnimatableValue {
    public var color: RGBA
    public var offset: Vec2
    /// Blur in pixels, as Figma measures it.
    public var blur: Double
    /// 0 to 1, on top of the colour's own alpha.
    public var opacity: Double
    /// How far the shadow's shape grows past the layer's (or, negative,
    /// shrinks inside it) before it is blurred. Shapes only.
    public var spread: Double

    public init(color: RGBA = .black, offset: Vec2 = Vec2(0, 4), blur: Double = 8, opacity: Double = 0.25,
                spread: Double = 0) {
        self.color = color
        self.offset = offset
        self.blur = blur
        self.opacity = opacity
        self.spread = spread
    }

    /// No shadow at all, which is what a Shadow action on a layer designed
    /// without one starts from. Its opacity is what makes it none; the colour
    /// stays solid so that raising the opacity alone brings a shadow back.
    public static let noShadow = DropShadow(color: .black, offset: .zero, blur: 0, opacity: 0)

    private enum CodingKeys: String, CodingKey { case color, offset, blur, opacity, spread }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(RGBA.self, forKey: .color)
        offset = try c.decode(Vec2.self, forKey: .offset)
        blur = try c.decode(Double.self, forKey: .blur)
        opacity = try c.decode(Double.self, forKey: .opacity)
        // Added after the first files with shadows were written.
        spread = try c.decodeIfPresent(Double.self, forKey: .spread) ?? 0
    }
}

public struct LayerBlur: Codable, Sendable, Equatable {
    /// Pixels, as Figma measures blur.
    public var radius: Double

    public init(radius: Double = 4) {
        self.radius = radius
    }
}

/// Blurs whatever is behind the layer, seen through its fills: frosted
/// glass. Shapes only, since it follows the shape's outline.
public struct BackgroundBlur: AnimatableValue {
    /// Pixels, as Figma measures blur.
    public var radius: Double
    /// 0 to 1: how much of the blurred background shows over the sharp one.
    public var blend: Double

    public init(radius: Double = 16, blend: Double = 1) {
        self.radius = radius
        self.blend = blend
    }

    /// No blur, which is what a Background Blur action on a layer designed
    /// without one starts from.
    public static let noBlur = BackgroundBlur(radius: 0, blend: 1)
}

extension Layer {
    /// The first picture fill of a shape, with where it is among the fills.
    public var picture: (index: Int, paint: ImagePaint)? {
        guard let shape = look, let i = shape.pictureIndex,
              let paint = shape.fills[i].paint.imagePaint else { return nil }
        return (i, paint)
    }

    /// Every imported file the layer shows or plays.
    public var mediaIDs: [UUID] {
        switch content {
        case .shape, .group: return look?.fills.compactMap { $0.paint.imagePaint?.mediaID } ?? []
        case .video(let v): return [v.mediaID]
        case .audio(let a): return [a.mediaID]
        case .text: return []
        }
    }
}

/// Figma's blend modes, by the names its menu shows. Linear Burn and
/// Linear Dodge are Figma's Plus Darker and Plus Lighter.
public enum BlendMode: String, Codable, Sendable, CaseIterable {
    case normal
    case darken, multiply, linearBurn, colorBurn
    case lighten, screen, linearDodge, colorDodge
    case overlay, softLight, hardLight
    case difference, exclusion
    case hue, saturation, color, luminosity

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .darken: return "Darken"
        case .multiply: return "Multiply"
        case .linearBurn: return "Linear Burn"
        case .colorBurn: return "Colour Burn"
        case .lighten: return "Lighten"
        case .screen: return "Screen"
        case .linearDodge: return "Linear Dodge"
        case .colorDodge: return "Colour Dodge"
        case .overlay: return "Overlay"
        case .softLight: return "Soft Light"
        case .hardLight: return "Hard Light"
        case .difference: return "Difference"
        case .exclusion: return "Exclusion"
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .color: return "Colour"
        case .luminosity: return "Luminosity"
        }
    }

    /// Figma's menu groups them: darkening, lightening, contrast, comparing,
    /// and by component.
    public static let groups: [[BlendMode]] = [
        [.normal],
        [.darken, .multiply, .linearBurn, .colorBurn],
        [.lighten, .screen, .linearDodge, .colorDodge],
        [.overlay, .softLight, .hardLight],
        [.difference, .exclusion],
        [.hue, .saturation, .color, .luminosity],
    ]
}
