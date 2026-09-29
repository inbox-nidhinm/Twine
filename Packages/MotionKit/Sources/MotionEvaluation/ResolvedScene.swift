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

    /// From a layer's own space into composition space as it is drawn,
    /// through every group, tilts and all. Clicks and outlines follow this;
    /// editing works in `worldTransform`, which is flat.
    public func worldProjection(of id: UUID) -> Projective? {
        guard let layer = layer(id) else { return nil }
        var transform = layer.projection
        var parent = layer.parentID
        while let pid = parent, let p = self.layer(pid) {
            transform = transform.then(p.projection)
            parent = p.parentID
        }
        return transform
    }

    /// The layer's box in composition space: its four corners, in order from
    /// the top-left, after rotation, scale, skew and tilt. Nil when a corner
    /// is turned past the viewer.
    public func worldCorners(of id: UUID) -> [Vec2]? {
        guard let layer = layer(id), let world = worldProjection(of: id) else { return nil }
        let corners = Box(origin: .zero, size: layer.size).corners.compactMap(world.apply)
        return corners.count == 4 ? corners : nil
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
    /// Skew and tilt, boxed when there are any (see `Warp`).
    public var warp: Warp = .none
    /// A clip of the layer's own box from a Mask preset, or `.none`.
    public var reveal: Reveal = .none
    /// Motion blur: the layer drawn several times across the shutter and
    /// averaged, or `.none`.
    public var motion: MotionSpread = .none
    /// Degrees each way (see `Transform.skew`).
    public var skew: Vec2 { warp.skew }
    /// A turn in depth (see `Tilt`), which `transform` leaves out and
    /// `projection` has.
    public var tilt: Tilt { warp.tilt }

    /// A shape's fills, strokes and outline, or a frame's.
    public var look: ResolvedShape? {
        if case .shape(let s) = content { return s }
        return frame
    }

    /// The first drop shadow, the one the Shadow action drives.
    public var shadow: ResolvedShadow? { shadows.first }

    /// From the layer's own space into its parent's, flat: everything but a
    /// tilt. What editing works in.
    public var transform: Affine {
        .layer(position: position, anchor: anchor, scale: scale, rotation: rotation, skew: skew)
    }

    /// From the layer's own space into its parent's as drawn, tilt and all.
    public var projection: Projective {
        .layer(position: position, anchor: anchor, scale: scale, rotation: rotation, skew: skew, tilt: tilt)
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
    public var fillRule: FillRule
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
    /// Whether the letters are filled with `color`; false leaves only the
    /// stroke.
    public var showsFill: Bool = true
    public var stroke: ResolvedTextStroke?
    /// While a text preset moves its letters, words or lines one by one,
    /// each of them, drawn in place of the whole text; empty otherwise.
    public var units: [ResolvedTextUnit] = []

    public var style: TextStyle {
        TextStyle(fontFamily: fontFamily, fontWeight: fontWeight, fontSize: fontSize, alignment: alignment,
                  letterSpacing: letterSpacing, lineHeight: lineHeight, tabularDigits: tabularDigits)
    }
}

/// An outline round a text's letters.
public struct ResolvedTextStroke: Sendable, Hashable {
    public var color: RGBA
    public var width: Double
    public var alignment: StrokeAlignment
    public var join: LineJoin

    public init(color: RGBA, width: Double, alignment: StrokeAlignment, join: LineJoin) {
        self.color = color
        self.width = width
        self.alignment = alignment
        self.join = join
    }
}

/// One letter, word or line of a text, moved on its own by a text preset.
/// How motion blur draws a layer: `count` copies averaged together, the
/// first placed by `start` (from the layer's own space into its parent's, in
/// place of its `projection`) and each next by `step` more, taken in the
/// layer's own space first. Across a shutter, a fraction of a frame, motion
/// is steady enough that one step repeated follows it. Boxed, as `Warp` is,
/// so a layer without it costs nothing to copy.
public enum MotionSpread: Sendable, Equatable {
    case none
    indirect case spread(start: Projective, step: Projective, count: Int)

    /// From the first copy's place and the next one's, or `.none` when they
    /// are the same place, or the first cannot be undone.
    public init(first: Projective, next: Projective, count: Int) {
        let same = abs(first.a - next.a) + abs(first.b - next.b) + abs(first.c - next.c) + abs(first.d - next.d)
            + abs(first.tx - next.tx) + abs(first.ty - next.ty) + abs(first.px - next.px) + abs(first.py - next.py)
            + abs(first.w - next.w) < 1e-9
        guard count > 1, !same, let back = first.inverted else {
            self = .none
            return
        }
        self = .spread(start: first, step: next.then(back), count: count)
    }
}

/// How many copies motion blur draws: a few while editing, many in exports.
public enum MotionBlurSamples {
    public static let preview = 8
    public static let export = 24
}

public struct ResolvedTextUnit: Sendable, Equatable {
    /// Its characters, in UTF-16 units of the text.
    public var range: NSRange
    /// Its box in the text's own space, where it sits at rest.
    public var box: Box
    /// From its own box (origin at its top-left) into the text's space, as
    /// it is drawn now: moved, scaled, turned and tilted about its centre.
    public var transform: Projective
    public var opacity: Double
    /// In Figma's units, as `ResolvedLayer.blur`.
    public var blur: Double
    /// A clip of its own box, or `.none`.
    public var reveal: Reveal
    /// Motion blur, as a layer's (`ResolvedLayer.motion`).
    public var motion: MotionSpread = .none

    public init(range: NSRange, box: Box, transform: Projective, opacity: Double, blur: Double, reveal: Reveal) {
        self.range = range
        self.box = box
        self.transform = transform
        self.opacity = opacity
        self.blur = blur
        self.reveal = reveal
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
    /// groups either sits in, tilts and all.
    public var transform: Projective

    public init(layerID: UUID, isInverted: Bool, transform: Projective) {
        self.layerID = layerID
        self.isInverted = isInverted
        self.transform = transform
    }
}
