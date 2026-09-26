import Foundation
import MotionModel

/// Everything a renderer needs to draw one moment of a composition, with every
/// property already worked out. Renderers read this and nothing else, which is
/// what lets a Metal renderer or a motion-blur pass (several subframe scenes
/// averaged) slot in later without touching the model.
///
/// `layers` is flat and in drawing order, back to front, with each group
/// before its children. A group is a layer too, so a renderer can give it a
/// container of its own and apply the group's opacity, transform and clipping
/// to its children as one picture.
public struct ResolvedScene: Sendable, Equatable {
    public var time: Double
    public var size: Size2
    /// Nil when the composition's background is transparent.
    public var background: RGBA?
    public var layers: [ResolvedLayer]
    /// Layers used as masks, which draw only through the layers they mask.
    /// Kept apart from `layers` so nothing draws them by accident, but found
    /// by `layer(_:)`, so a selected mask still shows its box and handles.
    public var masks: [ResolvedLayer]

    public init(time: Double, size: Size2, background: RGBA?, layers: [ResolvedLayer], masks: [ResolvedLayer] = []) {
        self.time = time
        self.size = size
        self.background = background
        self.layers = layers
        self.masks = masks
    }

    public func layer(_ id: UUID) -> ResolvedLayer? {
        layers.first { $0.id == id } ?? masks.first { $0.id == id }
    }

    public func mask(_ id: UUID) -> ResolvedLayer? { masks.first { $0.id == id } }

    /// From a layer's own space into composition space, through every group
    /// it sits inside.
    public func worldTransform(of id: UUID) -> Affine? {
        guard let layer = layer(id) else { return nil }
        var transform = layer.transform
        var parent = layer.parentID
        while let pid = parent, let p = self.layer(pid) {
            transform = transform.then(p.transform)
            parent = p.parentID
        }
        return transform
    }

    /// The layer's box in composition space: its four corners, in order from
    /// the top-left, after rotation and scale.
    public func worldCorners(of id: UUID) -> [Vec2]? {
        guard let layer = layer(id), let world = worldTransform(of: id) else { return nil }
        return Box(origin: .zero, size: layer.size).corners.map(world.apply)
    }

    /// What the layer covers on screen, as an upright box in composition
    /// space: a turned layer's box is the one around its corners. A group's
    /// is the box around what is drawn inside it (clipped to its own box
    /// when it clips), since a group's own size is only where it was made.
    public func bounds(of id: UUID) -> Box? {
        guard let layer = layer(id) else { return nil }
        guard layer.content == .group else { return worldCorners(of: id).flatMap { Box(around: $0) } }
        let inside = layers.filter { $0.parentID == id }.compactMap { bounds(of: $0.id) }
        guard let first = inside.first else { return nil }
        let all = inside.dropFirst().reduce(first) { $0.union($1) }
        guard layer.clipsContent, let own = worldCorners(of: id).flatMap({ Box(around: $0) }) else { return all }
        let clipped = Box(minX: max(all.minX, own.minX), minY: max(all.minY, own.minY),
                          maxX: min(all.maxX, own.maxX), maxY: min(all.maxY, own.maxY))
        return clipped.width >= 0 && clipped.height >= 0 ? clipped : nil
    }
}

public struct ResolvedLayer: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var parentID: UUID?
    public var size: Size2
    public var position: Vec2
    public var anchor: Vec2
    public var scale: Vec2
    /// Degrees, clockwise.
    public var rotation: Double
    public var opacity: Double
    public var content: ResolvedContent
    public var shadow: ResolvedShadow?
    /// Pixels, as Figma measures blur (twice the Gaussian's standard
    /// deviation); 0 is none.
    public var blur: Double
    /// Shapes only: blurs what is behind the layer, inside its outline.
    public var backgroundBlur: BackgroundBlur?
    /// Groups only.
    public var clipsContent: Bool
    /// Another layer whose alpha shows or hides this one. Nil when the layer
    /// has no mask, or its mask is switched off or hidden, which (as in
    /// Figma) shows the layer whole.
    public var mask: ResolvedMask?

    /// From the layer's own space into its parent's.
    public var transform: Affine {
        .layer(position: position, anchor: anchor, scale: scale, rotation: rotation)
    }
}

public enum ResolvedContent: Sendable, Equatable {
    case shape(ResolvedShape)
    case text(ResolvedText)
    case image(mediaID: UUID)
    /// `sourceTime` is the moment in the clip to show.
    case video(mediaID: UUID, sourceTime: Double)
    case group
}

public struct ResolvedShape: Sendable, Equatable {
    /// In the layer's own pixel space.
    public var path: BezierPath
    public var isClosed: Bool
    /// Only the fills that are switched on, bottom first.
    public var fills: [ResolvedPaint]
    public var strokes: [ResolvedStroke]
}

public enum ResolvedPaint: Sendable, Equatable {
    case solid(RGBA)
    /// `start` and `end` in the layer's pixel space.
    case linear(stops: [GradientStop], start: Vec2, end: Vec2)
    /// `center` and `radius` in pixels. The radius is the distance from the
    /// centre to the model's edge point.
    case radial(stops: [GradientStop], center: Vec2, radius: Double)
}

public struct ResolvedStroke: Sendable, Equatable {
    public var paint: ResolvedPaint
    public var width: Double
    /// `.center` on open paths regardless of the model, since only a closed
    /// path has an inside and an outside.
    public var alignment: StrokeAlignment
    public var cap: LineCap
    public var join: LineJoin
    public var dashPattern: [Double]
    public var dashOffset: Double
    public var trimStart: Double
    public var trimEnd: Double
}

public struct ResolvedText: Sendable, Equatable {
    public var text: String
    /// Part way through a Counter or a Change Text: the words going out.
    public var swap: TextSwap?
    public var fontFamily: String
    public var fontWeight: Int
    public var fontSize: Double
    public var color: RGBA
    public var alignment: TextAlignment
    public var letterSpacing: Double
    public var lineHeight: Double?
    public var sizing: TextSizing
    public var tabularDigits: Bool

    public var style: TextStyle {
        TextStyle(fontFamily: fontFamily, fontWeight: fontWeight, fontSize: fontSize, alignment: alignment,
                  letterSpacing: letterSpacing, lineHeight: lineHeight, tabularDigits: tabularDigits)
    }
}

public struct ResolvedShadow: Sendable, Equatable {
    public var color: RGBA
    public var offset: Vec2
    /// As Figma measures it: twice the Gaussian's standard deviation.
    public var blur: Double
    public var opacity: Double
    /// Pixels the shadow's shape grows by before blurring; shapes only.
    public var spread: Double
}

public struct ResolvedMask: Sendable, Equatable {
    /// The mask, in `ResolvedScene.masks`.
    public var layerID: UUID
    /// Shows the layer where the mask is empty rather than where it draws.
    public var isInverted: Bool
    /// From the mask's own space into the masked layer's, through whatever
    /// groups either sits in.
    public var transform: Affine

    public init(layerID: UUID, isInverted: Bool, transform: Affine) {
        self.layerID = layerID
        self.isInverted = isInverted
        self.transform = transform
    }
}
