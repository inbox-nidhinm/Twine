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
    public let layers: [ResolvedLayer]
    /// Layers used as masks, which draw only through the layers they mask.
    /// Kept apart from `layers` so nothing draws them by accident, but found
    /// by `layer(_:)`, so a selected mask still shows its box and handles.
    public let masks: [ResolvedLayer]

    /// Where each layer is in `layers` or `masks`, so finding one by id,
    /// which hit testing, snapping and every world transform do for every
    /// layer, never searches the whole list.
    private let index: [UUID: Slot]

    private struct Slot: Sendable, Equatable {
        var isMask: Bool
        var position: Int
    }

    public init(time: Double, size: Size2, background: RGBA?, layers: [ResolvedLayer], masks: [ResolvedLayer] = []) {
        self.time = time
        self.size = size
        self.background = background
        self.layers = layers
        self.masks = masks
        var made: [UUID: Slot] = [:]
        made.reserveCapacity(layers.count + masks.count)
        for (i, layer) in masks.enumerated() { made[layer.id] = Slot(isMask: true, position: i) }
        for (i, layer) in layers.enumerated() { made[layer.id] = Slot(isMask: false, position: i) }
        index = made
    }

    public func layer(_ id: UUID) -> ResolvedLayer? {
        guard let slot = index[id] else { return nil }
        return slot.isMask ? masks[slot.position] : layers[slot.position]
    }

    public func mask(_ id: UUID) -> ResolvedLayer? {
        guard let slot = index[id], slot.isMask else { return nil }
        return masks[slot.position]
    }

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
    /// A frame's is its own box.
    public func bounds(of id: UUID) -> Box? {
        guard let layer = layer(id) else { return nil }
        // A frame's box is its own, as in Figma, whatever is inside it.
        guard layer.content == .group, layer.frame == nil else { return worldCorners(of: id).flatMap { Box(around: $0) } }
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
    /// Drop shadows, bottom first. The first is the one the Shadow action
    /// drives.
    public var shadows: [ResolvedShadow]
    /// Shapes and frames only: shadows inside the outline, over the fills.
    public var innerShadows: [ResolvedShadow]
    public var blendMode: BlendMode
    /// Pixels, as Figma measures blur (twice the Gaussian's standard
    /// deviation); 0 is none.
    public var blur: Double
    /// Shapes only: blurs what is behind the layer, inside its outline.
    public var backgroundBlur: BackgroundBlur?
    /// Groups only. A frame clips to its own outline, rounded corners and
    /// all.
    public var clipsContent: Bool
    /// A frame's own fills, strokes and outline, drawn behind its children
    /// (the fills) and in front of them (the strokes). Nil for everything
    /// else, plain groups included.
    public var frame: ResolvedShape?
    /// Another layer whose alpha shows or hides this one. Nil when the layer
    /// has no mask, or its mask is switched off or hidden, which (as in
    /// Figma) shows the layer whole.
    public var mask: ResolvedMask?

    /// A shape's fills, strokes and outline, or a frame's.
    public var look: ResolvedShape? {
        if case .shape(let s) = content { return s }
        return frame
    }

    /// The first drop shadow, the one the Shadow action drives.
    public var shadow: ResolvedShadow? { shadows.first }

    /// From the layer's own space into its parent's.
    public var transform: Affine {
        .layer(position: position, anchor: anchor, scale: scale, rotation: rotation)
    }
}

public enum ResolvedContent: Sendable, Equatable {
    case shape(ResolvedShape)
    case text(ResolvedText)
    /// `sourceTime` is the moment in the clip to show.
    case video(mediaID: UUID, sourceTime: Double, fit: VideoFit)
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
    /// Held by reference, so the other paints stay small to copy.
    indirect case image(ResolvedImage)
}

/// A picture fill, placed. Drawn inside the shape's outline only.
public struct ResolvedImage: Sendable, Equatable {
    public var mediaID: UUID
    /// The whole picture's box in the layer's pixels, after its turns. For
    /// a tiled picture, the first tile, repeated right and down from it
    /// until the layer is covered.
    public var frame: Box
    /// Quarter turns clockwise, 0 to 3.
    public var turns: Int
    public var tiles: Bool
    public var opacity: Double
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
